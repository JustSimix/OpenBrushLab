import pytest
from openbrushlab.protocol import decode_status, decode_value


@pytest.mark.parametrize("payload", [b"", b"\x01\x02", b"\x65", b"\xff"])
def test_bad_battery(payload):
    with pytest.raises(ValueError):
        decode_value("battery", payload)


@pytest.mark.parametrize("value", [0, 50, 100])
def test_battery(value):
    assert decode_value("battery", bytes([value])) == value


@pytest.mark.parametrize("field,payload,expected", [
    ("model", b"OCLEANY3PD", "OCLEANY3PD"),
    ("firmware", b"1.0.0.36\x00", "1.0.0.36"),
    ("hardware", b"Rev.D", "Rev.D"),
    ("model", b"Alice-AA:BB:CC:DD:EE:FF", "[redacted-unrecognized-value]"),
    ("firmware", b"secret-serial", "[redacted-unrecognized-value]"),
])
def test_information_privacy(field, payload, expected):
    assert decode_value(field, payload) == expected


def test_synthetic_status():
    result = decode_status(bytes.fromhex("0303020e74500000"))
    assert result == {"dock_code": 2, "voltage_mv": 3700, "battery": 80,
                      "validation": "upstream-layout-only"}


@pytest.mark.parametrize("payload", ["", "0303020e745000", "0303020e7450000000", "0203020e74500000", "0303040e74500000", "0303020e74ff0000"])
def test_invalid_status(payload):
    with pytest.raises(ValueError):
        decode_status(bytes.fromhex(payload))
