# SPDX-License-Identifier: GPL-3.0-only
"""Opt-in, bounded session query. Never imported by the read-only commands.

Only one application write is allowed: 03 07 -> fbb89, response=True.
Subscribe/unsubscribe fbb90 may write its CCCD. No ACK, settings or OTA.
"""
import asyncio
import hashlib
import hmac
import json
import secrets
import time
from datetime import datetime, timezone
from pathlib import Path
from .ble import scan
from .protocol import OCLEAN_SERVICE_UUID, standard_uuid, decode_value
from .sessions import MAX_BYTES, MAX_FRAMES, decode_capture

SESSION_TX = "5f78df94-798c-46f5-990a-855b673fbb89"
SESSION_RX = "5f78df94-798c-46f5-990a-855b673fbb90"
SESSION_QUERY = bytes.fromhex("0307")


def unique_char(client, service_uuid, char_uuid, property_name):
    matches = [c for s in client.services if s.uuid.lower() == service_uuid
               for c in s.characteristics if c.uuid.lower() == char_uuid]
    if len(matches) != 1 or property_name not in matches[0].properties:
        raise ValueError("missing-or-ambiguous-capability")
    return matches[0]


def private_device_key(directory, address):
    # Private, persistent correlation key; never put this key in public logs.
    path = directory / ".device-key"
    try:
        with path.open("xb") as stream:
            key = secrets.token_bytes(32)
            stream.write(key)
    except FileExistsError:
        key = path.read_bytes()
    if len(key) != 32:
        raise ValueError("invalid-local-key")
    return hmac.new(key, address.upper().encode(), hashlib.sha256).hexdigest()


async def run_capture(args, log, scanner=None, client_factory=None):
    # Gate checked before imports, files, scan or connection.
    if not args.allow_session_query:
        log.emit("error", reason="session-query-not-authorized")
        return 1
    if scanner is None or client_factory is None:
        from bleak import BleakScanner, BleakClient
        scanner = scanner or BleakScanner
        client_factory = client_factory or BleakClient
    phase = "scan"
    raw_path = None
    try:
        async with asyncio.timeout(args.total_timeout):
            devices = await scan(scanner, args.scan_seconds, log, False)
            if args.address:
                selected = [d for d in devices if d.address.upper() == args.address.upper()]
            elif len(devices) == 1 and args.index == 1:
                selected = devices
            else:
                selected = []
            if len(selected) != 1:
                log.emit("error", reason="capture-requires-one-explicit-target")
                return 1
            device = selected[0]
            phase = "connect-and-discover"
            client_context = client_factory(device, pair=False, timeout=args.operation_timeout)
            try:
                async with asyncio.timeout(args.operation_timeout):
                    client = await client_context.__aenter__()
            except BaseException:
                try:
                    async with asyncio.timeout(10):
                        await client_context.__aexit__(None, None, None)
                except Exception:
                    log.emit("cleanup_warning", reason="failed-connect-cleanup-not-confirmed")
                raise
            try:
                phase = "verify-target"
                for short, field, expected in (("2a24", "model", "OCLEANY3X"),
                                                ("2a28", "software", "1.0.0.36")):
                    char = unique_char(client, standard_uuid("180a"), standard_uuid(short), "read")
                    async with asyncio.timeout(args.operation_timeout):
                        value = decode_value(field, await client.read_gatt_char(char))
                    if value != expected:
                        log.emit("error", reason="target-revision-or-model-not-verified")
                        return 1
                tx = unique_char(client, OCLEAN_SERVICE_UUID, SESSION_TX, "write")
                rx = unique_char(client, OCLEAN_SERVICE_UUID, SESSION_RX, "notify")
                directory = Path(args.capture_dir)
                directory.mkdir(parents=True, exist_ok=True)
                device_key = private_device_key(directory, device.address)
                stem = "sessions-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + secrets.token_hex(4)
                raw_path = directory / (stem + ".raw.jsonl")
                started = time.monotonic()
                state = {"frames": 0, "bytes": 0, "after_query": False, "failed": False}
                stop = asyncio.Event()
                subscribed = False
                with raw_path.open("x", encoding="utf-8") as raw_file:
                    def save(event, **fields):
                        row = {"schema": 1, "event": event, "elapsed_s": round(time.monotonic()-started, 6), **fields}
                        raw_file.write(json.dumps(row) + "\n")
                        raw_file.flush()

                    save("capture_header", device_key=device_key, model="OCLEANY3X", software="1.0.0.36",
                         captured_at_utc=datetime.now(timezone.utc).isoformat(),
                         privacy="private-local-raw-do-not-publish", protocol="TYPE1-candidate")

                    def on_frame(sender, data):
                        if state["failed"]:
                            return
                        try:
                            payload = bytes(data)
                            if len(payload) > 512 or state["frames"] >= MAX_FRAMES or state["bytes"] + len(payload) > MAX_BYTES:
                                state["failed"] = True
                                save("capture_limit")
                                stop.set()
                                return
                            state["frames"] += 1
                            state["bytes"] += len(payload)
                            save("frame", sequence=state["frames"], after_query=state["after_query"], hex=payload.hex())
                        except Exception:
                            state["failed"] = True
                            stop.set()

                    try:
                        phase = "subscribe-session-channel"
                        async with asyncio.timeout(args.operation_timeout):
                            await client.start_notify(rx, on_frame)
                        subscribed = True
                        phase = "send-single-session-query"
                        state["after_query"] = True
                        save("query_attempt", opcode="0307")
                        async with asyncio.timeout(args.operation_timeout):
                            await client.write_gatt_char(tx, SESSION_QUERY, response=True)
                        save("query_sent", opcode="0307")
                        log.emit("session_query_sent", opcode="0307", acknowledgement_sent=False)
                        phase = "receive-session-stream"
                        try:
                            await asyncio.wait_for(stop.wait(), timeout=args.listen_seconds)
                        except TimeoutError:
                            pass
                    finally:
                        if subscribed:
                            try:
                                async with asyncio.timeout(5):
                                    await client.stop_notify(rx)
                            except Exception:
                                log.emit("cleanup_warning", reason="unsubscribe-failed-disconnect-follows")
                    save("capture_footer", frames=state["frames"], bytes=state["bytes"],
                         limit_or_storage_error=state["failed"], acknowledgement_sent=False)
                log.emit("capture_saved", frames=state["frames"], bytes=state["bytes"],
                         raw_file=raw_path.name, private=True)
                if state["failed"]:
                    return 2
            finally:
                try:
                    async with asyncio.timeout(10):
                        await client_context.__aexit__(None, None, None)
                except Exception:
                    log.emit("cleanup_warning", reason="disconnect-not-confirmed")
        phase = "offline-decode"
        result = decode_capture(raw_path, raw_path.with_name(raw_path.name.replace(".raw.jsonl", ".decoded.json")))
        log.emit("session_decode_summary", status=result["status"], records=len(result["records"]),
                 records_needing_review=sum(bool(r["issues"]) for r in result["records"]),
                 healthkit_ready=False)
        return 0 if result["status"] in ("complete-candidate", "zero-count-no-complete-history") else 2
    except TimeoutError:
        log.emit("error", reason="capture-timeout", phase=phase, raw_may_be_partial=raw_path is not None)
        return 1
    except Exception:
        log.emit("error", reason="capture-failed", phase=phase, raw_may_be_partial=raw_path is not None)
        return 1
