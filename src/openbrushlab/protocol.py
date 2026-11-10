# SPDX-License-Identifier: GPL-3.0-only
"""Constants adapted from deniskie (MIT); status layout from dzikus (GPL-3.0).

See THIRD_PARTY_NOTICES.md. No command builders or transmit path.
"""
import re

OCLEAN_SERVICE_UUID = "8082caa8-41a6-4021-91c6-56f9b954cc18"
READ_NOTIFY_CHAR_UUID = "5f78df94-798c-46f5-990a-855b673fbb86"


def standard_uuid(short):
    return f"0000{short}-0000-1000-8000-00805f9b34fb"


# Deliberately excludes Serial Number (2A25), System ID (2A23), vendor payloads.
READ_FIELDS = {
    standard_uuid("2a24"): "model",
    standard_uuid("2a26"): "firmware",
    standard_uuid("2a27"): "hardware",
    standard_uuid("2a28"): "software",
    standard_uuid("2a19"): "battery",
}
EXPECTED_SERVICES = {
    "model": standard_uuid("180a"), "firmware": standard_uuid("180a"),
    "hardware": standard_uuid("180a"), "software": standard_uuid("180a"),
    "battery": standard_uuid("180f"),
}


def decode_value(field, payload):
    if field == "battery":
        if len(payload) != 1 or payload[0] > 100:
            raise ValueError("invalid battery")
        return payload[0]
    text = bytes(payload).decode("ascii").rstrip("\x00").strip()
    # Unexpected strings can contain names or serials: never export them.
    pattern = r"OCLEAN[A-Z0-9]{1,16}" if field == "model" else r"(?:Rev\.[ A-Za-z]|[0-9]+(?:\.[0-9]+){1,5})"
    if not re.fullmatch(pattern, text):
        return "[redacted-unrecognized-value]"
    return text


def decode_status(payload):
    """Offline ONLY, TYPE1 candidate; not evidence for firmware 1.0.0.36."""
    if len(payload) != 8 or payload[:2] != bytes.fromhex("0303"):
        raise ValueError("expected eight-byte TYPE1 status")
    if payload[5] > 100 or payload[2] not in (1, 2, 3):
        raise ValueError("invalid status values")
    return {"dock_code": payload[2], "voltage_mv": int.from_bytes(payload[3:5], "big"),
            "battery": payload[5], "validation": "upstream-layout-only"}
