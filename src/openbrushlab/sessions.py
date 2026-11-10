# SPDX-License-Identifier: GPL-3.0-only
"""Offline TYPE1 candidate decoder adapted from dzikus' documented 42B layout.

No BLE imports. This does not certify Y3X timestamps or export to HealthKit.
"""
import hashlib
import json
from datetime import datetime
from pathlib import Path

MAGIC = bytes.fromhex("03072a4223")
MAX_RECORDS = 64
MAX_BYTES = 8192
MAX_FRAMES = 256


def decode_record(raw, *, inline=False, device_key=""):
    required = 11 if inline else 42
    if len(raw) != required:
        raise ValueError("invalid record size")
    issues = []
    try:
        date = datetime(2000 + raw[0], *raw[1:6])
        if date.year < 2015:
            raise ValueError("implausible year")
        timestamp = date.isoformat()
    except ValueError:
        timestamp = None
        issues.append("invalid-or-unverified-device-date")
    scheduled = int.from_bytes(raw[7:9], "big")
    actual = int.from_bytes(raw[9:11], "big")
    if not 0 < actual <= 7200 or not 0 < scheduled <= 7200 or actual > scheduled:
        issues.append("duration-needs-review")
    if inline:
        issues.append("inline-fragment-not-complete-history-or-proven-newest")
    return {
        "kind": "inline-fragment" if inline else "full-record",
        "record_fingerprint": hashlib.sha256(device_key.encode() + b"\0" + raw).hexdigest(),
        "device_local_timestamp": timestamp,
        "device_datetime_raw": list(raw[:6]),
        "timestamp_semantics": "start-or-end-unvalidated",
        "scheme_raw": raw[6], "scheduled_duration_s": scheduled,
        "actual_duration_candidate_s": actual,
        "timezone_raw": None if inline else raw[17],
        "score_raw": None if inline else raw[33],
        "issues": issues, "protocol_validation": "upstream-layout-candidate",
        "healthkit_ready": False,
    }


def decode_frames(frames, device_key=""):
    if len(frames) > MAX_FRAMES or sum(map(len, frames)) > MAX_BYTES:
        return {"status": "capture-limit-exceeded", "records": []}
    data = b"".join(frames)
    result = {"status": "incomplete", "records": [], "received_bytes": len(data)}
    if len(data) < 7:
        return result
    if data[:5] != MAGIC:
        return {**result, "status": "unknown-format"}
    count = int.from_bytes(data[5:7], "big")
    result["declared_count"] = count
    if count > MAX_RECORDS:
        return {**result, "status": "invalid-record-count"}
    if count == 0:
        result["status"] = "zero-count-no-complete-history"
        if len(data) >= 18:
            raw = data[7:18]
            if raw[:3] != bytes(3):
                result["records"] = [decode_record(raw, inline=True, device_key=device_key)]
        return result
    required = 7 + count * 42
    result["expected_bytes"] = required
    if len(data) < required:
        return result
    if len(data) > required:
        # Observed on OCLEANY3X: fixed 20-byte notifications, final packet
        # zero-filled to 20 bytes (32 records => 1351 bytes + 9 zero bytes).
        # Accept ONLY padding within that last fixed-size packet. Extra frames,
        # nonzero tails and variable-size framing remain unknown.
        trailing = data[required:]
        if not (0 < len(trailing) < 20 and all(len(frame) == 20 for frame in frames)
                and all(value == 0 for value in trailing)):
            return {**result, "status": "unexpected-trailing-bytes"}
        result["transport_padding_zero_bytes"] = len(trailing)
    result["records"] = [decode_record(data[7+i*42:7+(i+1)*42], device_key=device_key)
                         for i in range(count)]
    result["status"] = "complete-candidate"
    fingerprints = [r["record_fingerprint"] for r in result["records"]]
    result["duplicate_record_count"] = len(fingerprints) - len(set(fingerprints))
    return result


def load_capture(path):
    """Load and decode a private raw capture without writing any output."""
    path = Path(path)
    if path.stat().st_size > 131072:
        raise ValueError("capture file too large")
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    if len(rows) > MAX_FRAMES + 32 or any(not isinstance(row, dict) for row in rows):
        raise ValueError("invalid capture rows")
    if not rows or rows[0].get("event") != "capture_header" or rows[0].get("schema") != 1:
        raise ValueError("not an OpenBrushLab capture")
    header = rows[0]
    key = header.get("device_key", "")
    if not isinstance(key, str) or len(key) != 64 or any(c not in "0123456789abcdef" for c in key):
        raise ValueError("invalid capture identity")
    selected = [r for r in rows if r.get("event") == "frame" and r.get("after_query") is True]
    if len(selected) > MAX_FRAMES:
        raise ValueError("too many frames")
    frames = []
    for row in selected:
        value = row.get("hex")
        if not isinstance(value, str) or len(value) > 1024:
            raise ValueError("invalid frame")
        frames.append(bytes.fromhex(value))
    result = decode_frames(frames, key)
    if any(r.get("limit_or_storage_error") is True for r in rows):
        result["status"] = "capture-limit-exceeded"
    result["capture_finished"] = any(r.get("event") == "capture_footer" for r in rows)
    result["query_confirmed_sent"] = any(r.get("event") == "query_sent" for r in rows)
    if not result["capture_finished"] or not result["query_confirmed_sent"]:
        result["transport_warning"] = "capture-incomplete-or-write-not-confirmed"
    return header, result


def decode_capture(path, output):
    _, result = load_capture(path)
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")
    return result
