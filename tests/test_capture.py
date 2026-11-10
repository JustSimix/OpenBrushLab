import asyncio
import io
import json
from pathlib import Path
from types import SimpleNamespace as Obj
import pytest
from openbrushlab.capture import run_capture, SESSION_TX, SESSION_RX, SESSION_QUERY, private_device_key
from openbrushlab.sessions import decode_frames, decode_record, decode_capture, MAGIC
from openbrushlab.privacy import JsonLog
from openbrushlab.protocol import standard_uuid, OCLEAN_SERVICE_UUID


def record(actual=70, scheduled=120, date=None):
    raw = bytearray(42)
    raw[:6] = date or bytes([26, 11, 10, 9, 30, 0])
    raw[6] = 1
    raw[7:9] = scheduled.to_bytes(2, "big")
    raw[9:11] = actual.to_bytes(2, "big")
    raw[17] = 15
    raw[33] = 80
    return bytes(raw)


def packet(*records):
    return MAGIC + len(records).to_bytes(2, "big") + b"".join(records)


def args(tmp_path, **kwargs):
    values = dict(allow_session_query=True, address=None, index=1, scan_seconds=0.001,
                  operation_timeout=0.2, total_timeout=1, listen_seconds=0.001,
                  capture_dir=str(tmp_path))
    values.update(kwargs)
    return Obj(**values)


class Scanner:
    calls = 0
    @classmethod
    async def discover(cls, **kwargs):
        cls.calls += 1
        d = Obj(address="AA:BB:CC:DD:EE:FF", name="Oclean PRIVATE-NAME")
        return {"one": (d, Obj(local_name=d.name, service_uuids=[], rssi=-40))}


def client_type(*, model=b"OCLEANY3X", version=b"1.0.0.36", payload=None,
                subscribe_error=False, write_error=False, enter_timeout=False,
                subscribe_timeout=False, disconnect_error=False, duplicate_tx=False):
    def char(uuid, props, data=b""):
        return Obj(uuid=uuid, properties=props, data=data)
    model_char = char(standard_uuid("2a24"), ["read"], model)
    version_char = char(standard_uuid("2a28"), ["read"], version)
    tx = char(SESSION_TX, ["read", "write"])
    rx = char(SESSION_RX, ["read", "notify"])
    vendor = [tx, rx] + ([tx] if duplicate_tx else [])
    class Client:
        instances = []
        def __init__(self, device, **kw):
            assert kw["pair"] is False
            self.services = [Obj(uuid=standard_uuid("180a"), characteristics=[model_char, version_char]),
                             Obj(uuid=OCLEAN_SERVICE_UUID, characteristics=vendor)]
            self.calls = []
            self.disconnected = False
            self.instances.append(self)
        async def __aenter__(self):
            if enter_timeout:
                await asyncio.sleep(10)
            return self
        async def __aexit__(self, *exc):
            self.disconnected = True
            if disconnect_error:
                raise RuntimeError("private exception")
        async def read_gatt_char(self, char):
            self.calls.append(("read", char.uuid))
            return char.data
        async def start_notify(self, char, cb):
            self.calls.append(("subscribe", char.uuid))
            self.callback = cb
            if subscribe_error:
                raise RuntimeError("PRIVATE AA:BB:CC:DD:EE:FF")
            if subscribe_timeout:
                await asyncio.sleep(10)
        async def stop_notify(self, char):
            self.calls.append(("unsubscribe", char.uuid))
        async def write_gatt_char(self, char, data, *, response):
            self.calls.append(("write", char.uuid, bytes(data), response))
            assert char.uuid == SESSION_TX and bytes(data) == bytes.fromhex("0307") and response is True
            if write_error:
                raise RuntimeError("PRIVATE AA:BB:CC:DD:EE:FF")
            body = packet(record()) if payload is None else payload
            for i in range(0, len(body), 20):
                self.callback(rx, body[i:i+20])
    return Client


@pytest.mark.parametrize("split", [1, 2, 5, 7, 18, 20, 41, 49])
def test_fragmented_stream(split):
    body = packet(record(), record(actual=90))
    result = decode_frames([body[i:i+split] for i in range(0, len(body), split)])
    assert result["status"] == "complete-candidate"
    assert [r["actual_duration_candidate_s"] for r in result["records"]] == [70, 90]
    assert result["records"][0]["scheduled_duration_s"] == 120
    assert not result["records"][0]["healthkit_ready"]


@pytest.mark.parametrize("body,status", [
    (b"", "incomplete"), (b"0307", "incomplete"), (bytes(7), "unknown-format"),
    (MAGIC + (65).to_bytes(2, "big"), "invalid-record-count"),
    (packet(record())[:-1], "incomplete"),
    (packet(record()) + b"x", "unexpected-trailing-bytes"),
    (MAGIC + bytes(2), "zero-count-no-complete-history"),
])
def test_malformed_streams(body, status):
    assert decode_frames([body])["status"] == status


def test_zero_count_inline_is_not_newest_or_full_history():
    result = decode_frames([MAGIC + bytes(2) + record()[:13]])
    assert result["status"] == "zero-count-no-complete-history"
    assert result["records"][0]["kind"] == "inline-fragment"
    assert result["records"][0]["timezone_raw"] is None
    assert result["records"][0]["issues"]


def test_zero_count_zero_date_does_not_invent_session():
    assert decode_frames([MAGIC + bytes(2) + bytes(13)])["records"] == []


@pytest.mark.parametrize("raw", [record(date=bytes(6)), record(actual=0), record(actual=200)])
def test_suspicious_record_needs_review(raw):
    assert decode_record(raw)["issues"]


def test_duplicates_retained_and_counted():
    result = decode_frames([packet(record(), record())])
    assert len(result["records"]) == 2
    assert result["duplicate_record_count"] == 1
    assert decode_record(record(), device_key="a")["record_fingerprint"] != decode_record(record(), device_key="b")["record_fingerprint"]


def test_limits():
    assert decode_frames([b"x"]*257)["status"] == "capture-limit-exceeded"
    assert decode_frames([bytes(8193)])["status"] == "capture-limit-exceeded"


def test_capture_gate_precedes_scan_and_files(tmp_path):
    class Never:
        @staticmethod
        async def discover(**kw):
            pytest.fail("scan without opt-in")
    assert asyncio.run(run_capture(args(tmp_path, allow_session_query=False), JsonLog(io.StringIO()), Never, client_type())) == 1
    assert list(tmp_path.iterdir()) == []


def test_only_one_query_private_capture_and_cleanup(tmp_path):
    Client = client_type()
    stream = io.StringIO()
    assert asyncio.run(run_capture(args(tmp_path), JsonLog(stream), Scanner, Client)) == 0
    client = Client.instances[0]
    assert client.calls == [("read", standard_uuid("2a24")), ("read", standard_uuid("2a28")),
                            ("subscribe", SESSION_RX), ("write", SESSION_TX, SESSION_QUERY, True),
                            ("unsubscribe", SESSION_RX)]
    assert client.disconnected
    output = stream.getvalue()
    assert all(secret not in output for secret in ["PRIVATE-NAME", "AA:BB:CC:DD:EE:FF", "2026-11-10T09:30:00", record().hex()])
    raw = next(tmp_path.glob("*.raw.jsonl"))
    decoded = json.loads(next(tmp_path.glob("*.decoded.json")).read_text())
    assert decoded["records"][0]["actual_duration_candidate_s"] == 70
    assert decoded["query_confirmed_sent"] is True
    assert raw.exists()


@pytest.mark.parametrize("config", [dict(model=b"OCLEANY3P"), dict(version=b"1.0.0.35"), dict(duplicate_tx=True)])
def test_wrong_target_or_ambiguous_channel_never_writes(tmp_path, config):
    Client = client_type(**config)
    assert asyncio.run(run_capture(args(tmp_path), JsonLog(io.StringIO()), Scanner, Client)) == 1
    assert not any(c[0] in ("write", "subscribe") for c in Client.instances[0].calls)
    assert Client.instances[0].disconnected


@pytest.mark.parametrize("config", [dict(subscribe_error=True), dict(write_error=True),
                                    dict(enter_timeout=True), dict(subscribe_timeout=True)])
def test_error_does_not_retry_or_leak_and_disconnects(tmp_path, config):
    Client = client_type(**config)
    stream = io.StringIO()
    assert asyncio.run(run_capture(args(tmp_path, operation_timeout=0.001), JsonLog(stream), Scanner, Client)) == 1
    client = Client.instances[0]
    assert client.disconnected
    assert len([c for c in client.calls if c[0] == "write"]) <= 1
    assert "PRIVATE" not in stream.getvalue()
    if config.get("write_error"):
        assert ("unsubscribe", SESSION_RX) in client.calls
        assert next(tmp_path.glob("*.raw.jsonl")).exists()


def test_empty_response_has_no_fabricated_sessions(tmp_path):
    assert asyncio.run(run_capture(args(tmp_path), JsonLog(io.StringIO()), Scanner, client_type(payload=b""))) == 2
    decoded = json.loads(next(tmp_path.glob("*.decoded.json")).read_text())
    assert decoded["status"] == "incomplete" and decoded["records"] == []


def test_local_key_is_stable_private_and_case_insensitive(tmp_path):
    assert private_device_key(tmp_path, "aa") == private_device_key(tmp_path, "AA")
    assert private_device_key(tmp_path, "aa") != private_device_key(tmp_path, "bb")


def test_offline_capture_validation_and_no_overwrite(tmp_path):
    rows = [{"schema": 1, "event": "capture_header", "device_key": "a"*64},
            {"event": "frame", "after_query": False, "hex": "00"},
            {"event": "frame", "after_query": True, "hex": packet(record()).hex()}]
    path = tmp_path / "raw.jsonl"
    path.write_text("\n".join(json.dumps(r) for r in rows))
    output = tmp_path / "decoded.json"
    result = decode_capture(path, output)
    assert result["status"] == "complete-candidate"
    assert result["transport_warning"]
    with pytest.raises(FileExistsError):
        decode_capture(path, output)
    path.write_text('[1,2]')
    with pytest.raises(ValueError):
        decode_capture(path, tmp_path / "other.json")


def test_cli_requires_opt_in_without_ble(monkeypatch):
    from openbrushlab.cli import main
    monkeypatch.delenv("OPENBRUSHLAB_ADDRESS", raising=False)
    with pytest.raises(SystemExit):
        main(["capture-sessions", "--index", "1"])


def test_write_path_is_explicit_constant_and_isolated():
    import ast
    import openbrushlab.capture as module
    tree = ast.parse(Path(module.__file__).read_text())
    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)]
    writes = [n for n in calls if n.func.attr == "write_gatt_char"]
    assert len(writes) == 1
    assert isinstance(writes[0].args[1], ast.Name) and writes[0].args[1].id == "SESSION_QUERY"
    assert SESSION_QUERY == b"\x03\x07"
    assert not any(n.func.attr in {"write_gatt_descriptor", "pair", "unpair"} for n in calls)


def test_total_timeout_during_listening_unsubscribes_and_disconnects(tmp_path):
    Client = client_type()
    assert asyncio.run(run_capture(args(tmp_path, total_timeout=0.01, listen_seconds=1),
                                   JsonLog(io.StringIO()), Scanner, Client)) == 1
    assert Client.instances[0].disconnected
    assert ("unsubscribe", SESSION_RX) in Client.instances[0].calls
    assert next(tmp_path.glob("*.raw.jsonl")).exists()


def test_multiple_candidates_refused_without_address(tmp_path):
    class Many(Scanner):
        @classmethod
        async def discover(cls, **kwargs):
            found = await Scanner.discover(**kwargs)
            found["other"] = (Obj(address="11:22:33:44:55:66", name="Oclean other"),
                              Obj(local_name="Oclean other", service_uuids=[], rssi=-50))
            return found
    Client = client_type()
    assert asyncio.run(run_capture(args(tmp_path), JsonLog(io.StringIO()), Many, Client)) == 1
    assert Client.instances == []


def test_oversized_frame_stops_without_another_query(tmp_path):
    Base = client_type()
    class Oversized(Base):
        async def write_gatt_char(self, char, data, *, response):
            self.calls.append(("write", char.uuid, bytes(data), response))
            self.callback(None, bytes(513))
    assert asyncio.run(run_capture(args(tmp_path), JsonLog(io.StringIO()), Scanner, Oversized)) == 2
    assert len([c for c in Oversized.instances[0].calls if c[0] == "write"]) == 1
    assert Oversized.instances[0].disconnected


def test_offline_cli_replay_does_not_leak_records(tmp_path, capsys):
    from openbrushlab.cli import main
    Client = client_type()
    assert asyncio.run(run_capture(args(tmp_path), JsonLog(io.StringIO()), Scanner, Client)) == 0
    path = next(tmp_path.glob("*.raw.jsonl"))
    assert main(["decode-sessions", str(path), "--output", str(tmp_path / "replayed.json")]) == 0
    assert "2026-11-10T09:30:00" not in capsys.readouterr().out


def test_observed_y3x_fixed20_zero_padding():
    body = packet(*[record() for _ in range(32)])
    assert len(body) == 1351
    body += bytes(9)
    frames = [body[i:i+20] for i in range(0, len(body), 20)]
    result = decode_frames(frames)
    assert result["status"] == "complete-candidate"
    assert result["transport_padding_zero_bytes"] == 9
    assert len(result["records"]) == 32


@pytest.mark.parametrize("variant", ["nonzero", "extra-full-frame", "one-oversized-frame"])
def test_padding_is_not_blanket_trailing_acceptance(variant):
    body = packet(*[record() for _ in range(32)]) + bytes(9)
    if variant == "nonzero":
        body = body[:-1] + b"x"
    if variant == "extra-full-frame":
        body += bytes(20)
    frames = [body] if variant == "one-oversized-frame" else [body[i:i+20] for i in range(0,len(body),20)]
    assert decode_frames(frames)["status"] == "unexpected-trailing-bytes"
