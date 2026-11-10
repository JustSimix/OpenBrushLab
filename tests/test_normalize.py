import io
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
import pytest
from openbrushlab.normalize import (verify_time, event_id, normalize, atomic_json,
                                    stage_events, archive_lock, EXPORT_FORMAT)
from openbrushlab.sessions import load_capture, MAGIC


def raw_record(*, actual=75, score=59, date=(26,11,10,11,37,15), tz=15, scheme=231):
    raw = bytearray(42)
    raw[:6] = bytes(date)
    raw[6] = scheme
    raw[7:9] = (75).to_bytes(2,"big")
    raw[9:11] = actual.to_bytes(2,"big")
    raw[17] = tz
    raw[33] = score
    return bytes(raw)


def capture(tmp_path, name, records=None, *, device="a"*64, complete=True,
            captured="2026-11-10T10:40:00Z", model="OCLEANY3X", revision="1.0.0.36"):
    records = [raw_record()] if records is None else records
    body = MAGIC + len(records).to_bytes(2,"big") + b"".join(records)
    rows = [{"schema":1, "event":"capture_header", "device_key":device,
             "captured_at_utc":captured,"model":model,"software":revision},
            {"event":"query_sent"},
            {"event":"frame","after_query":True,"hex":body.hex()}]
    if complete:
        rows.append({"event":"capture_footer"})
    path = tmp_path / name
    path.write_text("\n".join(json.dumps(r) for r in rows), encoding="utf-8")
    return path


def evidence(tmp_path, path, **overrides):
    _, decoded = load_capture(path)
    value = {"kind":"user-reported-completed-cycle", "source":"user-chat",
             "record_fingerprint":decoded["records"][0]["record_fingerprint"],
             "reported_start_local_minute":"2026-11-10T11:37",
             "completed_duration_s":75,"displayed_score":59}
    value.update(overrides)
    output = tmp_path / "evidence.json"
    output.write_text(json.dumps({"schema":1,"observations":[value]}))
    return output


def outputs(tmp_path):
    return tmp_path / "data/sessions.json", tmp_path / "data/healthkit.json"


@pytest.mark.parametrize("local,wire,expected,status", [
    ("2026-11-10T11:37:15",15,"2026-11-10T10:37:15Z","matches-wire-offset"),
    ("2026-07-10T11:37:15",16,"2026-07-10T09:37:15Z","matches-wire-offset"),
    ("2026-10-25T02:30:00",16,"2026-10-25T00:30:00Z","fold-disambiguated-by-wire-offset"),
    ("2026-10-25T02:30:00",15,"2026-10-25T01:30:00Z","fold-disambiguated-by-wire-offset"),
])
def test_timezone_winter_summer_and_fold(local,wire,expected,status):
    result = verify_time(local,wire,"Europe/Rome","2026-12-01T12:00:00Z")
    assert result["utc_timestamp_candidate"] == expected
    assert result["iana_status"] == status and not result["reasons"]


@pytest.mark.parametrize("local,wire,reason", [
    (None,15,"invalid-device-date"),
    ("2000-01-01T10:00:00",15,"invalid-device-date"),
    ("2026-11-10T11:37:15+01:00",15,"invalid-device-date"),
    ("2026-11-10T11:37:15",0,"unknown-wire-timezone"),
    ("2026-11-10T11:37:15",34,"unknown-wire-timezone"),
    ("2026-11-10T11:37:15",True,"unknown-wire-timezone"),
    ("2026-07-10T11:37:15",15,"wire-offset-mismatch"),
    ("2026-03-29T02:30:00",15,"nonexistent-local-time"),
])
def test_invalid_dates_offsets_and_spring_gap(local,wire,reason):
    assert reason in verify_time(local,wire,"Europe/Rome","2026-12-01T12:00:00Z")["reasons"]


def test_future_device_clock_and_bad_capture_timestamp():
    assert "session-after-capture-clock" in verify_time("2026-11-10T11:37:15",15,"Europe/Rome","2026-11-10T09:00:00Z")["reasons"]
    assert "invalid-capture-timestamp" in verify_time("2026-11-10T11:37:15",15,"Europe/Rome","2026-11-10T10:40:00")["reasons"]


def test_archive_is_idempotent_and_preserves_stable_sync_ids(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl")
    b = capture(tmp_path,"b.raw.jsonl", captured="2026-11-10T10:42:00Z")
    obs = evidence(tmp_path,a)
    store, export = outputs(tmp_path)
    summary = normalize([a,b],store,export,observations_path=obs)
    assert summary["unique_sessions"] == 1 and summary["duplicate_observations"] == 1
    assert summary["ios_review_candidates"] == 1
    first_store, first_export = store.read_bytes(), export.read_bytes()
    summary = normalize([b,a,a],store,export,observations_path=obs)
    assert summary["new_captures"] == 0
    assert store.read_bytes() == first_store and export.read_bytes() == first_export
    candidate = json.loads(first_export)["candidates"][0]
    assert candidate["start_date"] == "2026-11-10T10:37:15Z"
    assert candidate["end_date"] == "2026-11-10T10:38:30Z"
    assert candidate["duration_seconds"] == 75
    assert type(candidate["metadata"]["HKMetadataKeySyncVersion"]) is int
    assert candidate["metadata"]["HKMetadataKeySyncVersion"] == 1
    assert candidate["requires_review"] and candidate["end_time_is_derived"]


def test_incremental_archive_keeps_old_sessions_after_ring_overwrite(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl")
    b = capture(tmp_path,"b.raw.jsonl",[raw_record(date=(26,11,10,11,38,15))])
    store, export = outputs(tmp_path)
    normalize([a],store,export)
    summary = normalize([b],store,export)
    assert summary["unique_sessions"] == 2 and summary["captures"] == 2
    assert summary["ios_review_candidates"] == 0


def test_same_timestamp_different_brushes_not_merged(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl")
    b = capture(tmp_path,"b.raw.jsonl",device="b"*64)
    assert normalize([a,b],*outputs(tmp_path))["unique_sessions"] == 2


def test_score_or_duration_variants_are_conflicts_not_new_session(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl")
    b = capture(tmp_path,"b.raw.jsonl",[raw_record(actual=60)])
    store, export = outputs(tmp_path)
    summary = normalize([a,b],store,export,observations_path=evidence(tmp_path,a))
    assert summary["unique_sessions"] == 1 and summary["merged_distinct_variants"] == 1
    assert summary["ios_review_candidates"] == 0
    assert "conflicting-session-variants" in next(iter(json.loads(store.read_text())["sessions"].values()))["review_reasons"]


def test_invalid_old_dates_preserved_without_guessing_year(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl",[raw_record(date=(0,1,8,8,52,0))])
    store, export = outputs(tmp_path)
    normalize([a],store,export)
    event = next(iter(json.loads(store.read_text())["sessions"].values()))
    assert event["device_local_timestamp"] is None
    assert event["device_datetime_raw"] == [0,1,8,8,52,0]
    assert event["time_verification"]["utc_timestamp_candidate"] is None
    assert event["export_status"] == "hold"


@pytest.mark.parametrize("config,reason", [
    ({"complete":False},"unverified-capture-transport"),
    ({"model":"OCLEANY3P"},"unvalidated-model-or-revision"),
    ({"revision":"1.0.0.35"},"unvalidated-model-or-revision"),
])
def test_incomplete_transport_and_unvalidated_profiles_are_held(tmp_path,config,reason):
    a = capture(tmp_path,"a.raw.jsonl",**config)
    store, export = outputs(tmp_path)
    summary = normalize([a],store,export,observations_path=evidence(tmp_path,a))
    assert summary["ios_review_candidates"] == 0
    assert reason in next(iter(json.loads(store.read_text())["sessions"].values()))["review_reasons"]


@pytest.mark.parametrize("change", [{"displayed_score":60},{"completed_duration_s":74},
                                    {"reported_start_local_minute":"2026-11-10T11:36"},
                                    {"source":"guessed"}])
def test_evidence_must_match_actual_observation(tmp_path,change):
    a = capture(tmp_path,"a.raw.jsonl")
    assert normalize([a],*outputs(tmp_path),observations_path=evidence(tmp_path,a,**change))["ios_review_candidates"] == 0


def test_short_and_voided_records_not_exported(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl",[raw_record(actual=3,score=1)])
    summary = normalize([a],*outputs(tmp_path))
    assert summary["ios_review_candidates"] == 0
    assert summary["review_reason_counts"]["device-score-void-marker"] == 1


def test_retracted_observation_emits_reconciliation_and_monotonic_version(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl")
    obs = evidence(tmp_path,a)
    store, export = outputs(tmp_path)
    normalize([a],store,export,observations_path=obs)
    obs.write_text(json.dumps({"schema":1,"observations":[]}))
    normalize([],store,export,observations_path=obs)
    manifest = json.loads(export.read_text())
    assert not manifest["candidates"] and len(manifest["retired_candidates"]) == 1
    obs = evidence(tmp_path,a)
    normalize([],store,export,observations_path=obs)
    assert json.loads(export.read_text())["candidates"][0]["metadata"]["HKMetadataKeySyncVersion"] == 2


def test_sync_version_changes_only_when_payload_changes():
    event = {"export_status":"candidate-for-ios-review", "start_utc":"2026-11-10T10:37:15Z",
             "end_utc":"2026-11-10T10:38:30Z", "active_duration_candidate_s":75,"time_zone":"Europe/Rome"}
    registry, first = stage_events({"one":event},{})
    same, second = stage_events({"one":event},registry)
    assert first == second and registry == same
    event["end_utc"] = "2026-11-10T10:38:29Z"
    registry, third = stage_events({"one":event},registry)
    assert third["candidates"][0]["metadata"]["HKMetadataKeySyncVersion"] == 2


def test_archive_lock_and_corruption_preserve_originals(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl")
    store, export = outputs(tmp_path)
    with archive_lock(store):
        with pytest.raises(FileExistsError):
            normalize([a],store,export)
    store.write_text('{"private":"original"}')
    with pytest.raises(ValueError):
        normalize([a],store,export)
    assert store.read_text() == '{"private":"original"}'
    assert not Path(str(store)+".lock").exists()


def test_modified_capture_original_is_not_silently_reimported(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl")
    store, export = outputs(tmp_path)
    normalize([a],store,export)
    previous = store.read_bytes()
    a.write_text(a.read_text()+"\n")
    with pytest.raises(ValueError):
        normalize([a],store,export)
    assert store.read_bytes() == previous


def test_input_output_collisions_refused(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl")
    original = a.read_bytes()
    with pytest.raises(ValueError):
        normalize([a],a,tmp_path/"export.json")
    assert a.read_bytes() == original
    with pytest.raises(ValueError):
        normalize([a],tmp_path/"out.json",tmp_path/"out.json")


def test_atomic_write_preserves_original_on_replace_failure(tmp_path,monkeypatch):
    target = tmp_path/"archive.json"
    target.write_text("original")
    import openbrushlab.normalize as mod
    def fail(*args):
        raise OSError("simulated replacement failure")
    monkeypatch.setattr(mod.os,"replace",fail)
    with pytest.raises(OSError):
        atomic_json(target,{"new":True})
    assert target.read_text() == "original"
    assert not list(tmp_path.glob("*.tmp"))


def test_cli_is_offline_and_prints_counts_not_private_dates(tmp_path,capsys):
    from openbrushlab.cli import main
    a = capture(tmp_path,"a.raw.jsonl")
    store, export = outputs(tmp_path)
    assert main(["normalize-sessions","--capture-dir",str(tmp_path),"--store",str(store),
                 "--export",str(export),"--observations",str(evidence(tmp_path,a))]) == 0
    printed = capsys.readouterr().out
    assert "normalization_summary" in printed
    assert all(value not in printed for value in ["2026-11-10T11:37:15", "2026-11-10T10:37:15Z", "a"*64])
    assert json.loads(export.read_text())["writes_to_apple_health"] is False


def test_observations_survive_incremental_runs_without_external_file(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl")
    store, export = outputs(tmp_path)
    normalize([a],store,export,observations_path=evidence(tmp_path,a))
    summary = normalize([],store,export)
    assert summary["ios_review_candidates"] == 1
    assert json.loads(export.read_text())["candidates"][0]["metadata"]["HKMetadataKeySyncVersion"] == 1


def test_same_wall_time_different_fold_offsets_are_distinct_sessions(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl",[raw_record(date=(26,10,25,2,30,0),tz=16)])
    b = capture(tmp_path,"b.raw.jsonl",[raw_record(date=(26,10,25,2,30,0),tz=15)])
    summary = normalize([a,b],*outputs(tmp_path))
    assert summary["unique_sessions"] == 2


def test_failed_manifest_can_be_regenerated_without_version_inflation(tmp_path,monkeypatch):
    import openbrushlab.normalize as module
    a = capture(tmp_path,"a.raw.jsonl")
    store, export = outputs(tmp_path)
    obs = evidence(tmp_path,a)
    original = module.atomic_json
    def fail_export(path,doc):
        if Path(path) == export:
            raise OSError("simulated manifest failure")
        original(path,doc)
    monkeypatch.setattr(module,"atomic_json",fail_export)
    with pytest.raises(OSError):
        normalize([a],store,export,observations_path=obs)
    assert store.exists() and not export.exists()
    monkeypatch.setattr(module,"atomic_json",original)
    normalize([],store,export)
    assert json.loads(export.read_text())["candidates"][0]["metadata"]["HKMetadataKeySyncVersion"] == 1


def test_completed_session_cannot_end_after_capture(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl",captured="2026-11-10T10:37:30Z")
    store, export = outputs(tmp_path)
    summary = normalize([a],store,export,observations_path=evidence(tmp_path,a))
    assert summary["ios_review_candidates"] == 0
    assert summary["review_reason_counts"]["completed-session-ends-after-capture"] == 1


def test_distinct_raw_variants_do_not_silently_become_one_export(tmp_path):
    a = capture(tmp_path,"a.raw.jsonl")
    changed = bytearray(raw_record())
    changed[23] = 1
    b = capture(tmp_path,"b.raw.jsonl",[bytes(changed)])
    store, export = outputs(tmp_path)
    summary = normalize([a,b],store,export,observations_path=evidence(tmp_path,a))
    assert summary["unique_sessions"] == 1
    assert summary["ios_review_candidates"] == 0
    assert summary["review_reason_counts"]["multiple-binary-variants-require-review"] == 1
