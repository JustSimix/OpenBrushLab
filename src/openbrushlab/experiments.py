# SPDX-License-Identifier: GPL-3.0-only
"""Offline comparisons for manually observed interrupted / paused trials.

Not HealthKit evidence. No BLE functions or inferred pause-byte meanings.
"""
import json
from collections import Counter
from pathlib import Path
from .sessions import load_capture


def measured_times(observation):
    def seconds(name):
        value = observation.get(name)
        if value is None:
            return None
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not 0 <= value <= 7200:
            raise ValueError("invalid manual measurement")
        return float(value)
    elapsed, pause, active = (seconds(k) for k in
                              ("stopwatch_elapsed_s", "stopwatch_pause_s", "stopwatch_active_s"))
    reasons=[]
    basis="explicit-stopwatch-active" if active is not None else None
    if observation.get("scenario") == "A":
        if pause not in (None,0):
            reasons.append("scenario-A-has-pause-measurement")
        if active is None and elapsed is not None:
            active,basis=elapsed,"elapsed-no-pause-scenario-A"
    elif observation.get("scenario") == "B":
        if observation.get("pause_control_supported") is not True:
            reasons.append("pause-support-not-confirmed")
        if active is None and elapsed is not None and pause is not None and elapsed >= pause:
            active,basis=elapsed-pause,"elapsed-minus-measured-pause"
        if elapsed is not None and pause is not None and elapsed < pause:
            reasons.append("pause-longer-than-elapsed")
    else:
        raise ValueError("unknown trial scenario")
    if active is not None and elapsed is not None and active > elapsed + 2:
        reasons.append("active-longer-than-elapsed")
    if active is not None and elapsed is not None and pause is not None and abs(elapsed-pause-active)>2:
        reasons.append("inconsistent-manual-timers")
    precision=observation.get("measurement_precision_s")
    if precision is None or isinstance(precision,bool) or not isinstance(precision,(int,float)) or not 0 < precision <= 2:
        reasons.append("stopwatch-precision-not-confirmed-within-2s")
    if active is None:
        reasons.append("missing-active-stopwatch-duration")
    return {"elapsed_s":elapsed,"pause_s":pause,"active_s":active,"basis":basis,"review_reasons":reasons}


def read_records(path):
    header,result=load_capture(path)
    if result["status"]!="complete-candidate" or not result["capture_finished"] or not result["query_confirmed_sent"]:
        raise ValueError("trial requires complete confirmed transport")
    rows=[json.loads(s) for s in Path(path).read_text(encoding="utf-8").splitlines()]
    data=b"".join(bytes.fromhex(row["hex"]) for row in rows if row.get("event")=="frame" and row.get("after_query") is True)
    count=result["declared_count"]
    raw=[data[7+i*42:7+(i+1)*42] for i in range(count)]
    return header,result,raw


def assess_record(record, observation, *, new_record_count):
    measured=measured_times(observation)
    actual=record["actual_duration_candidate_s"]
    planned=record["scheduled_duration_s"]
    expected=observation.get("program_expected_s")
    reasons=list(measured["review_reasons"])
    if new_record_count!=1:
        reasons.append("multiple-new-records-no-automatic-association")
    if observation.get("status") not in ("performed-awaiting-analysis","analyzed"):
        reasons.append("physical-trial-not-confirmed-performed")
    difference=None if measured["active_s"] is None else actual-measured["active_s"]
    agrees=difference is not None and abs(difference)<=2
    score=observation.get("displayed_score")
    score_match=None if score is None else score==record["score_raw"]
    result={"observed":measured,"decoded":{"scheduled_s":planned,"actual_candidate_s":actual,
              "score_raw":record["score_raw"],"device_local_timestamp":record["device_local_timestamp"]},
            "actual_minus_stopwatch_s":difference,"within_2s":agrees,
            "score_matches_display":score_match,"review_reasons":reasons,
            "timestamp_alignment":"manual-review-required", "healthkit_ready":False}
    # Different wall duration is not, by itself, proof of a pause encoding.
    if observation.get("scenario")=="A":
        result["interrupted_duration_criterion"]=("pass-numeric-candidate-needs-manual-time-association"
            if agrees and planned==expected==75 and actual<planned and not reasons else "not-established")
    else:
        result["pause_semantics"]="not-established; compare active and elapsed separately"
        result["matches_elapsed_within_2s"]=measured["elapsed_s"] is not None and abs(actual-measured["elapsed_s"])<=2
    return result


def analyze_trial(before_path,after_path,observation):
    before_header,before,before_raw=read_records(before_path)
    after_header,after,after_raw=read_records(after_path)
    if before_header["device_key"]!=after_header["device_key"]:
        raise ValueError("different device identities")
    old=Counter(before_raw)
    added=[]
    for raw,record in zip(after_raw,after["records"]):
        if old[raw]:
            old[raw]-=1
        else:
            added.append((raw,record))
    reference=observation.get("reference_full_cycle_fingerprint")
    baseline=[raw for raw,record in zip(before_raw,before["records"])
              if reference and record["record_fingerprint"]==reference]
    comparisons=[]
    for raw,record in added:
        item=assess_record(record,observation,new_record_count=len(added))
        item["raw_offset_7_8_be"]=int.from_bytes(raw[7:9],"big")
        item["raw_offset_9_10_be"]=int.from_bytes(raw[9:11],"big")
        if len(baseline)==1:
            item["changed_offsets_vs_full_cycle"]=[i for i in range(42) if raw[i]!=baseline[0][i]]
        comparisons.append(item)
    return {"scenario":observation.get("scenario"),"new_record_count":len(added),
            "retained_exact_count":len(after_raw)-len(added),"comparisons":comparisons,
            "pause_bytes_interpretation":"unknown: changing bytes are correlations, not pause flags",
            "association":"confirm timestamps/program/display manually before accepting criterion",
            "healthkit_ready":False}
