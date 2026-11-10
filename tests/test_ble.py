import asyncio
import io
import json
from types import SimpleNamespace as Obj
import pytest
from openbrushlab.ble import scan, inspect, run_ble
from openbrushlab.privacy import JsonLog
from openbrushlab.protocol import standard_uuid


def char(short, payload=b"", service="180a", properties=None, handle=1):
    return Obj(uuid=standard_uuid(short), properties=properties or ["read"],
               handle=handle, descriptors=[], payload=payload)


def fixture(chars=None):
    if chars is None:
        chars = [char("2a24", b"OCLEANY3P"), char("2a26", b"1.0.0.36"),
                 char("2a27", b"Rev.D"), char("2a28", b"1.0.0.36")]
    serial = char("2a25", b"private-serial")
    services = [Obj(uuid=standard_uuid("180a"), handle=1, characteristics=chars + [serial]),
                Obj(uuid=standard_uuid("180f"), handle=8, characteristics=[char("2a19", b"\x50")])]
    class FakeClient:
        calls = []
        disconnected = False
        def __init__(self, device, **kwargs):
            assert kwargs["pair"] is False
            self.services = services
        async def __aenter__(self):
            return self
        async def __aexit__(self, *exc):
            FakeClient.disconnected = True
        async def read_gatt_char(self, c):
            FakeClient.calls.append(c.uuid)
            if isinstance(c.payload, Exception):
                raise c.payload
            return c.payload
        async def write_gatt_char(self, *args, **kwargs):
            pytest.fail("BLE write attempted")
        async def write_gatt_descriptor(self, *args, **kwargs):
            pytest.fail("descriptor write attempted")
        async def start_notify(self, *args, **kwargs):
            pytest.fail("CCCD subscription attempted")
    return FakeClient


def device():
    return Obj(address="AA:BB:CC:DD:EE:FF", name="Oclean Alice")


def test_scan_redacts_identifiers_and_payloads():
    adv = Obj(local_name="Oclean Alice", service_uuids=[], rssi=-55,
              manufacturer_data={1: b"private-serial"})
    class Scanner:
        @staticmethod
        async def discover(**kwargs):
            return {"address": (device(), adv), "other": (Obj(address="11:22:33:44:55:66", name="Bob"),
                                                       Obj(local_name=None, service_uuids=[], rssi=-60))}
    stream = io.StringIO()
    result = asyncio.run(scan(Scanner, 1, JsonLog(stream)))
    assert len(result) == 1
    text = stream.getvalue()
    assert all(secret not in text for secret in [device().address, "Alice", "Bob", "private-serial"])


def test_reads_allowlist_only_and_disconnects():
    client = fixture()
    stream = io.StringIO()
    assert asyncio.run(inspect(client, device(), "read", 1, JsonLog(stream))) == 0
    assert len(client.calls) == 5
    assert standard_uuid("2a25") not in client.calls
    assert client.disconnected
    assert '"compatibility": "unvalidated"' in stream.getvalue()


def test_backend_exception_is_not_logged():
    client = fixture([char("2a24", RuntimeError("AA:BB:CC:DD:EE:FF private-serial"))])
    stream = io.StringIO()
    assert asyncio.run(inspect(client, device(), "read", 1, JsonLog(stream))) == 2
    assert "private-serial" not in stream.getvalue()
    assert device().address not in stream.getvalue()
    assert client.disconnected


def test_gatt_enumeration_does_no_reads():
    client = fixture()
    stream = io.StringIO()
    assert asyncio.run(inspect(client, device(), "gatt", 1, JsonLog(stream))) == 0
    assert client.calls == []
    assert "private-serial" not in stream.getvalue()


def test_ambiguous_read_is_skipped():
    client = fixture([char("2a24", b"OCLEANY3P"), char("2a24", b"OCLEANY3PD", handle=2)])
    assert asyncio.run(inspect(client, device(), "read", 1, JsonLog(io.StringIO()))) == 2
    assert standard_uuid("2a24") not in client.calls


def test_read_timeout_disconnects():
    Base = fixture()
    class Slow(Base):
        async def read_gatt_char(self, c):
            await asyncio.sleep(1)
    assert asyncio.run(inspect(Slow, device(), "read", 0.001, JsonLog(io.StringIO()))) == 2
    assert Base.disconnected


def test_total_timeout():
    class Scanner:
        @staticmethod
        async def discover(**kwargs):
            await asyncio.sleep(1)
    args = Obj(total_timeout=0.001, scan_seconds=1, all_devices=False)
    with pytest.raises(TimeoutError):
        asyncio.run(run_ble(args, JsonLog(io.StringIO()), Scanner, fixture()))


def test_tokens_change_between_runs_but_ignore_address_case():
    a, b = JsonLog(io.StringIO()), JsonLog(io.StringIO())
    assert a.token(device().address) == a.token(device().address.lower())
    assert a.token(device().address) != b.token(device().address)


def test_jsonl_output_and_exclusive_file(tmp_path):
    path = tmp_path / "capture.jsonl"
    stream = io.StringIO()
    with JsonLog(stream, path) as log:
        log.emit("test", battery=80)
    assert json.loads(path.read_text())["battery"] == 80
    assert path.read_text() == stream.getvalue()
    with pytest.raises(FileExistsError):
        with JsonLog(io.StringIO(), path):
            pass


@pytest.mark.parametrize("index,address,expected", [(1, None, 0), (2, None, 1), (None, "aa:bb:cc:dd:ee:ff", 0), (None, "00:00:00:00:00:00", 1)])
def test_target_selection(index, address, expected):
    class Scanner:
        @staticmethod
        async def discover(**kwargs):
            return {"one": (device(), Obj(local_name="Oclean", service_uuids=[], rssi=-50))}
    args = Obj(command="read", address=address, index=index, total_timeout=1,
               scan_seconds=0.01, all_devices=False, operation_timeout=0.1)
    assert asyncio.run(run_ble(args, JsonLog(io.StringIO()), Scanner, fixture())) == expected


def test_total_timeout_disconnects_connected_client():
    class Scanner:
        @staticmethod
        async def discover(**kwargs):
            return {"one": (device(), Obj(local_name="Oclean", service_uuids=[], rssi=-50))}
    Base = fixture()
    class Slow(Base):
        async def read_gatt_char(self, c):
            await asyncio.sleep(1)
    args = Obj(command="read", address=None, index=1, total_timeout=0.01,
               scan_seconds=0.001, all_devices=False, operation_timeout=1)
    with pytest.raises(TimeoutError):
        asyncio.run(run_ble(args, JsonLog(io.StringIO()), Scanner, Slow))
    assert Base.disconnected


def test_reported_y3x_revisions_compare_after_all_reads():
    # Regression based on user-supplied read results; no hardware involved.
    client = fixture([char("2a24", b"OCLEANY3X"), char("2a26", b"1.0"),
                      char("2a27", b"unknown-private-hardware"), char("2a28", b"1.0.0.36")])
    stream = io.StringIO()
    assert asyncio.run(inspect(client, device(), "read", 1, JsonLog(stream))) == 0
    rows = [json.loads(line) for line in stream.getvalue().splitlines()]
    comparisons = [row for row in rows if row["event"] == "target_comparison"]
    assert len(comparisons) == 1
    assert rows[-1] == comparisons[0]
    assert comparisons[0]["matches"] is True
    assert comparisons[0]["matching_fields"] == ["software"]
    assert comparisons[0]["observed_revisions"] == {"firmware": "1.0", "software": "1.0.0.36"}
    assert "unknown-private-hardware" not in stream.getvalue()


def test_missing_revisions_are_unknown_not_mismatch():
    client = fixture([char("2a24", b"OCLEANY3X")])
    stream = io.StringIO()
    assert asyncio.run(inspect(client, device(), "read", 1, JsonLog(stream))) == 2
    rows = [json.loads(line) for line in stream.getvalue().splitlines()]
    assert rows[-1]["event"] == "target_comparison"
    assert rows[-1]["matches"] is None
    assert rows[-1]["matching_fields"] == []
