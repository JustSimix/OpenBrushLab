import pytest
from openbrushlab.experiments import measured_times,assess_record
from openbrushlab.sessions import decode_record


def synthetic_record(actual,planned=75,score=42):
    # Entirely synthetic; no personal capture, date, IDs or motion bytes.
    raw=bytearray(42)
    raw[:6]=bytes([20,2,3,4,5,6])
    raw[7:9]=planned.to_bytes(2,"big")
    raw[9:11]=actual.to_bytes(2,"big")
    raw[33]=score
    return decode_record(raw)


def observation(scenario="A",**values):
    result=dict(scenario=scenario,program_expected_s=75,status="performed-awaiting-analysis",
                stopwatch_elapsed_s=30,stopwatch_active_s=None,stopwatch_pause_s=None,
                displayed_score=None,measurement_precision_s=0.5)
    result.update(values)
    return result


@pytest.mark.parametrize("actual,passes",[(28,True),(30,True),(32,True),(33,False),(75,False)])
def test_interrupted_duration_vs_program(actual,passes):
    result=assess_record(synthetic_record(actual),observation(),new_record_count=1)
    assert result["interrupted_duration_criterion"].startswith("pass-") is passes
    assert result["decoded"]["scheduled_s"]==75


def test_pause_active_vs_elapsed_remain_separate():
    obs=observation("B",stopwatch_elapsed_s=85,stopwatch_pause_s=10,pause_control_supported=True)
    result=assess_record(synthetic_record(75),obs,new_record_count=1)
    assert result["observed"]["active_s"]==75 and result["within_2s"]
    assert not result["matches_elapsed_within_2s"]
    assert result["pause_semantics"].startswith("not-established")


def test_pause_elapsed_encoding_not_falsely_called_active():
    obs=observation("B",stopwatch_elapsed_s=85,stopwatch_pause_s=10,pause_control_supported=True)
    result=assess_record(synthetic_record(85),obs,new_record_count=1)
    assert result["matches_elapsed_within_2s"] and not result["within_2s"]


@pytest.mark.parametrize("change,reason",[
    ({"status":"planned-not-performed"},"physical-trial-not-confirmed-performed"),
    ({"measurement_precision_s":None},"stopwatch-precision-not-confirmed-within-2s"),
    ({"stopwatch_active_s":50,"stopwatch_elapsed_s":30},"active-longer-than-elapsed"),
])
def test_missing_or_inconsistent_observations_do_not_pass(change,reason):
    result=assess_record(synthetic_record(30),observation(**change),new_record_count=1)
    assert reason in result["review_reasons"]
    assert result["interrupted_duration_criterion"]=="not-established"


def test_multiple_new_records_not_automatically_associated():
    result=assess_record(synthetic_record(30),observation(),new_record_count=2)
    assert result["interrupted_duration_criterion"]=="not-established"


def test_unsupported_pause_not_assumed():
    result=measured_times(observation("B",pause_control_supported=False))
    assert "pause-support-not-confirmed" in result["review_reasons"]


def test_template_does_not_replace_completed_cycle_evidence(tmp_path):
    import json
    from openbrushlab.normalize import observations_from_file
    path=tmp_path/"observations.json"
    known={"kind":"user-reported-completed-cycle","record_fingerprint":"a"*64}
    path.write_text(json.dumps({"schema":1,"observations":[known],"experiments":{"A":{"status":"planned"}}}))
    assert observations_from_file(path)=={"a"*64:known}


def test_offline_trial_comparison_uses_only_synthetic_capture(tmp_path):
    from test_normalize import capture,raw_record
    from openbrushlab.experiments import analyze_trial
    from openbrushlab.sessions import load_capture
    baseline=raw_record(date=(20,2,3,4,5,6),actual=75,score=42,scheme=1)
    interrupted=raw_record(date=(20,2,3,4,10,6),actual=30,score=42,scheme=1)
    before=capture(tmp_path,"before.raw.jsonl",[baseline],captured="2020-02-03T04:09:00Z")
    after=capture(tmp_path,"after.raw.jsonl",[baseline,interrupted],captured="2020-02-03T04:12:00Z")
    _,decoded=load_capture(before)
    obs=observation(reference_full_cycle_fingerprint=decoded["records"][0]["record_fingerprint"])
    result=analyze_trial(before,after,obs)
    assert result["new_record_count"]==1 and result["retained_exact_count"]==1
    comparison=result["comparisons"][0]
    assert comparison["raw_offset_7_8_be"]==75
    assert comparison["raw_offset_9_10_be"]==30
    assert comparison["changed_offsets_vs_full_cycle"]==[4,10]
    assert result["pause_bytes_interpretation"].startswith("unknown")


def test_restart_with_two_records_is_not_assigned_to_one_trial(tmp_path):
    from test_normalize import capture,raw_record
    from openbrushlab.experiments import analyze_trial
    a=raw_record(date=(20,2,3,4,5,6),actual=75,score=42,scheme=1)
    b=raw_record(date=(20,2,3,4,10,6),actual=20,score=42,scheme=1)
    c=raw_record(date=(20,2,3,4,11,6),actual=55,score=42,scheme=1)
    before=capture(tmp_path,"before.raw.jsonl",[a])
    after=capture(tmp_path,"after.raw.jsonl",[a,b,c])
    report=analyze_trial(before,after,observation("B",stopwatch_elapsed_s=85,
                         stopwatch_pause_s=10,pause_control_supported=True))
    assert report["new_record_count"]==2
    assert all("multiple-new-records-no-automatic-association" in c["review_reasons"] for c in report["comparisons"])
