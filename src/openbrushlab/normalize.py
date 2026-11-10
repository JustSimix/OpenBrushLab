# SPDX-License-Identifier: GPL-3.0-only
"""Private JSON session archive and HealthKit staging; offline only.

Timezone index table adapted from dzikus, see THIRD_PARTY_NOTICES.md.
No platform HealthKit writes and no BLE imports or operations.
"""
import hashlib
import json
import os
import tempfile
from collections import Counter
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo
from .sessions import load_capture

OFFSET_MINUTES = (-720, -660, -600, -540, -480, -420, -360, -300, -240,
                  -210, -180, -120, -60, 0, 60, 120, 180, 210, 240, 270,
                  300, 330, 345, 360, 390, 420, 480, 540, 570, 600, 660, 720, 780)
STORE_FORMAT = "openbrushlab-private-sessions"
EXPORT_FORMAT = "openbrushlab-healthkit-staging"


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def read_json(path):
    path = Path(path)
    if path.stat().st_size > 32 * 1024 * 1024:
        raise ValueError("JSON file too large")
    return json.loads(path.read_text(encoding="utf-8"))


def utc_text(value):
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def aware_datetime(value):
    result = datetime.fromisoformat(value)
    if result.tzinfo is None or result.utcoffset() is None:
        raise ValueError("timezone required")
    return result


def verify_time(local_text, wire_index, zone_name, captured_at):
    """Wire offset disambiguates folds; IANA roundtrip rejects nonexistent times."""
    reasons = []
    result = {"local": local_text, "wire_index": wire_index, "iana_zone": zone_name,
              "wire_offset_minutes": None, "utc_timestamp_candidate": None,
              "iana_status": "not-checked", "reasons": reasons}
    if not isinstance(local_text, str):
        reasons.append("invalid-device-date")
        return result
    try:
        local = datetime.fromisoformat(local_text)
        if local.tzinfo is not None or local.year < 2015:
            raise ValueError("invalid local date")
    except ValueError:
        reasons.append("invalid-device-date")
        return result
    if type(wire_index) is not int or not 1 <= wire_index <= len(OFFSET_MINUTES):
        reasons.append("unknown-wire-timezone")
        return result
    offset = OFFSET_MINUTES[wire_index - 1]
    result["wire_offset_minutes"] = offset
    instant = local.replace(tzinfo=timezone(timedelta(minutes=offset))).astimezone(timezone.utc)
    result["utc_timestamp_candidate"] = utc_text(instant)
    zone = ZoneInfo(zone_name)
    roundtrip = instant.astimezone(zone)
    valid_instants = set()
    for fold in (0, 1):
        candidate = local.replace(tzinfo=zone, fold=fold).astimezone(timezone.utc)
        if candidate.astimezone(zone).replace(tzinfo=None) == local:
            valid_instants.add(candidate)
    if not valid_instants:
        result["iana_status"] = "nonexistent-local-time"
        reasons.append("nonexistent-local-time")
    elif roundtrip.replace(tzinfo=None) != local:
        result["iana_status"] = "wire-offset-mismatch"
        reasons.append("wire-offset-mismatch")
    else:
        result["iana_status"] = "fold-disambiguated-by-wire-offset" if len(valid_instants) == 2 else "matches-wire-offset"
    try:
        captured = aware_datetime(captured_at)
        if instant > captured + timedelta(minutes=5):
            reasons.append("session-after-capture-clock")
    except (ValueError, TypeError):
        reasons.append("invalid-capture-timestamp")
    return result


def event_id(device, record):
    # Do not key on score/duration: enrichment must not create another event.
    # Invalid dates / inline records have no reliable semantic identity.
    if record.get("kind") == "full-record" and record.get("device_local_timestamp"):
        identity = [device, record["device_local_timestamp"], record.get("timezone_raw"), record.get("scheme_raw")]
        quality = "device-local-time-offset-and-scheme"
    else:
        identity = [device, "unresolved", record["record_fingerprint"]]
        quality = "binary-record-only"
    return digest(["openbrushlab-session-v1", identity]), quality


def observations_from_file(path):
    if path is None:
        return {}
    document = read_json(path)
    if not isinstance(document, dict) or document.get("schema") != 1 or not isinstance(document.get("observations"), list):
        raise ValueError("invalid observation file")
    found = {}
    for entry in document["observations"]:
        if not isinstance(entry, dict) or entry.get("kind") != "user-reported-completed-cycle":
            raise ValueError("unsupported observation")
        key = entry.get("record_fingerprint")
        if not isinstance(key, str) or len(key) != 64 or key in found:
            raise ValueError("invalid or duplicate observation fingerprint")
        found[key] = entry
    return found


def verify_observation(record, evidence):
    if evidence is None:
        return False
    try:
        observed = datetime.fromisoformat(evidence["reported_start_local_minute"])
        local = datetime.fromisoformat(record["device_local_timestamp"])
        if observed.tzinfo is not None or observed.second or observed.microsecond:
            return False
        return (observed <= local < observed + timedelta(minutes=1)
                and type(evidence["completed_duration_s"]) is int
                and evidence["completed_duration_s"] == record["actual_duration_candidate_s"] == record["scheduled_duration_s"]
                and type(evidence["displayed_score"]) is int
                and evidence["displayed_score"] == record["score_raw"]
                and evidence.get("source") == "user-chat")
    except (KeyError, ValueError, TypeError):
        return False


def build_events(captures, observations, zone_name):
    groups = {}
    for capture_id, capture in sorted(captures.items()):
        for record in capture["records"]:
            key, quality = event_id(capture["device_key"], record)
            group = groups.setdefault(key, {"id": key, "identity_quality": quality, "device_key": capture["device_key"],
                                            "occurrences": [], "variants": {}})
            group["occurrences"].append(capture_id)
            variant = group["variants"].setdefault(record["record_fingerprint"], {"record": record, "sources": []})
            variant["sources"].append(capture_id)
    events = {}
    for key, group in sorted(groups.items()):
        variants = list(group["variants"].values())
        record = variants[0]["record"]
        reasons = set(record["issues"])
        signatures = {canonical({f: v["record"].get(f) for f in ("scheduled_duration_s", "actual_duration_candidate_s", "score_raw")})
                      for v in variants}
        if len(variants) != 1:
            reasons.add("multiple-binary-variants-require-review")
        if len(signatures) != 1:
            reasons.add("conflicting-session-variants")
        if record["kind"] != "full-record":
            reasons.add("incomplete-record")
        if record["score_raw"] == 1:
            reasons.add("device-score-void-marker")
        if record["actual_duration_candidate_s"] <= 14:
            reasons.add("short-session-needs-review")
        times = []
        for capture_id in set(group["occurrences"]):
            capture = captures[capture_id]
            if not capture["transport_complete"]:
                reasons.add("unverified-capture-transport")
            if capture.get("model") != "OCLEANY3X" or capture.get("software") != "1.0.0.36":
                reasons.add("unvalidated-model-or-revision")
            time_result = verify_time(record["device_local_timestamp"], record["timezone_raw"], zone_name, capture["captured_at_utc"])
            times.append(time_result)
            reasons.update(time_result["reasons"])
            if time_result["utc_timestamp_candidate"]:
                try:
                    inferred_end = aware_datetime(time_result["utc_timestamp_candidate"]) + timedelta(seconds=record["actual_duration_candidate_s"])
                    if inferred_end > aware_datetime(capture["captured_at_utc"]) + timedelta(seconds=5):
                        reasons.add("completed-session-ends-after-capture")
                except (ValueError, TypeError):
                    pass
        verified = any(verify_observation(v["record"], observations.get(v["record"]["record_fingerprint"])) for v in variants)
        if not verified:
            reasons.add("no-matching-user-observation")
        time_result = times[0]
        event = {"session_id": key, "identity_quality": group["identity_quality"],
                 "variant_count": len(variants), "source_capture_ids": sorted(set(group["occurrences"])),
                 "observation_count": len(group["occurrences"]),
                 "record_fingerprints": sorted(group["variants"]),
                 "device_local_timestamp": record["device_local_timestamp"],
                 "device_datetime_raw": record.get("device_datetime_raw"),
                 "scheduled_duration_s": record["scheduled_duration_s"],
                 "active_duration_candidate_s": record["actual_duration_candidate_s"],
                 "score_raw": record["score_raw"], "scheme_raw": record["scheme_raw"],
                 "time_verification": time_result, "user_observation_verified": verified,
                 "review_reasons": sorted(reasons), "export_status": "hold" if reasons else "candidate-for-ios-review",
                 "healthkit_ready": False}
        if not reasons:
            instant = aware_datetime(time_result["utc_timestamp_candidate"])
            event.update(start_utc=utc_text(instant), end_utc=utc_text(instant + timedelta(seconds=record["actual_duration_candidate_s"])),
                         start_basis="device-timestamp-supported-by-user-start-minute",
                         end_basis="derived-from-start-plus-duration-of-reported-completed-cycle",
                         pause_handling="not-independently-validated", time_zone=zone_name)
        events[key] = event
    return events


def stage_events(events, previous_registry):
    registry = json.loads(json.dumps(previous_registry))
    candidates = []
    for key, event in sorted(events.items()):
        if event["export_status"] != "candidate-for-ios-review":
            continue
        payload = {"session_id": key, "type_identifier": "HKCategoryTypeIdentifierToothbrushingEvent",
                   "category_value": "notApplicable", "start_date": event["start_utc"], "end_date": event["end_utc"],
                   "duration_seconds": event["active_duration_candidate_s"], "time_zone": event["time_zone"],
                   "end_time_is_derived": True, "requires_review": True}
        content_hash = digest(payload)
        old = registry.get(key)
        version = 1 if old is None else old["version"] + int(old["payload_hash"] != content_hash or not old["currently_staged"])
        registry[key] = {"version": version, "payload_hash": content_hash, "currently_staged": True}
        payload["metadata"] = {"HKMetadataKeySyncIdentifier": "openbrushlab:toothbrushing:v1:" + key,
                               "HKMetadataKeySyncVersion": version, "HKMetadataKeyTimeZone": event["time_zone"]}
        candidates.append(payload)
    active = {p["session_id"] for p in candidates}
    retired = []
    for key, state in registry.items():
        if key not in active:
            state["currently_staged"] = False
            retired.append({"sync_identifier": "openbrushlab:toothbrushing:v1:" + key,
                            "reason": "no-longer-a-validated-candidate-requires-ios-reconciliation"})
    manifest = {"format": EXPORT_FORMAT, "schema": 1, "writes_to_apple_health": False,
                "requires_ios_healthkit_authorization": True, "requires_review": True,
                "candidates": candidates, "retired_candidates": retired,
                "held_session_count": len(events) - len(candidates)}
    return registry, manifest


def atomic_json(path, document):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=path.name + ".", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(document, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


@contextmanager
def archive_lock(path):
    lock = Path(str(path) + ".lock")
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("x", encoding="utf-8") as stream:
        stream.write("OpenBrushLab normalization in progress\n")
    try:
        yield
    finally:
        lock.unlink()


def normalize(capture_paths, store_path, export_path, *, observations_path=None, zone_name="Europe/Rome"):
    capture_paths = list(capture_paths)
    ZoneInfo(zone_name)  # fail before writes if the IANA database is unavailable
    store_path, export_path = Path(store_path), Path(export_path)
    protected = {Path(p).resolve() for p in capture_paths}
    if observations_path:
        protected.add(Path(observations_path).resolve())
    if store_path.resolve() == export_path.resolve() or store_path.resolve() in protected or export_path.resolve() in protected:
        raise ValueError("output collides with protected input")
    supplied_observations = observations_from_file(observations_path) if observations_path is not None else None
    with archive_lock(store_path):
        if store_path.exists():
            store = read_json(store_path)
            if not isinstance(store, dict) or store.get("format") != STORE_FORMAT or store.get("schema") != 1:
                raise ValueError("invalid archive; original preserved")
            if not isinstance(store.get("captures"), dict) or not isinstance(store.get("sync_registry"), dict):
                raise ValueError("invalid archive structure")
        else:
            store = {"format": STORE_FORMAT, "schema": 1, "captures": {}, "sync_registry": {}}
        if export_path.exists():
            previous_export = read_json(export_path)
            if not isinstance(previous_export, dict) or previous_export.get("format") != EXPORT_FORMAT or previous_export.get("schema") != 1:
                raise ValueError("invalid export; original preserved")
        observations = supplied_observations if supplied_observations is not None else store.get("observations", {})
        if not isinstance(observations, dict):
            raise ValueError("invalid stored observations")
        captures = store["captures"]
        imported = 0
        for path in sorted({Path(p) for p in capture_paths}):
            if path.stat().st_size > 131072:
                raise ValueError("capture too large")
            capture_hash = hashlib.sha256(path.read_bytes()).hexdigest()
            if capture_hash in captures:
                continue
            if any(c["filename"] == path.name and source_hash != capture_hash for source_hash, c in captures.items()):
                raise ValueError("capture filename changed content; original archive preserved")
            header, result = load_capture(path)
            captures[capture_hash] = {"filename": path.name, "device_key": header["device_key"],
                "model": header.get("model"), "software": header.get("software"),
                "captured_at_utc": header.get("captured_at_utc"), "status": result["status"],
                "transport_complete": result["status"] == "complete-candidate" and result["capture_finished"] and result["query_confirmed_sent"],
                "records": result["records"]}
            imported += 1
        events = build_events(captures, observations, zone_name)
        registry, manifest = stage_events(events, store["sync_registry"])
        store.update(sessions=events, sync_registry=registry, observations=observations, iana_zone=zone_name,
                     privacy="private-not-encrypted-do-not-publish", writes_to_apple_health=False)
        record_count = sum(len(c["records"]) for c in captures.values())
        summary = {"captures": len(captures), "new_captures": imported, "record_observations": record_count,
                   "unique_sessions": len(events),
                   "duplicate_observations": record_count-sum(len(e["record_fingerprints"]) for e in events.values()),
                   "merged_distinct_variants": sum(len(e["record_fingerprints"]) for e in events.values())-len(events),
                   "ios_review_candidates": len(manifest["candidates"]), "held_sessions": manifest["held_session_count"],
                   "review_reason_counts": dict(Counter(reason for event in events.values() for reason in event["review_reasons"])),
                   "writes_to_apple_health": False}
        store["summary"] = {k: v for k, v in summary.items() if k != "new_captures"}
        # Each file is atomically replaced. A failed manifest write is recoverable
        # by rerunning: stable registry versions regenerate the same staging file.
        atomic_json(store_path, store)
        atomic_json(export_path, manifest)
        return summary
