# SPDX-License-Identifier: GPL-3.0-only
import argparse
import asyncio
import math
import os
import sys
from .ble import run_ble
from .privacy import JsonLog
from .protocol import decode_status


def positive(value):
    result = float(value)
    if not math.isfinite(result) or result <= 0:
        raise argparse.ArgumentTypeError("serve un numero finito maggiore di zero")
    return result


def positive_index(value):
    result = int(value)
    if result < 1:
        raise argparse.ArgumentTypeError("indice minimo: 1")
    return result


def parser():
    p = argparse.ArgumentParser(description="OpenBrushLab: diagnostica read-only e cattura sessioni separata con opt-in")
    sub = p.add_subparsers(dest="command", required=True)
    for name in ("scan", "gatt", "read"):
        s = sub.add_parser(name)
        s.add_argument("--scan-seconds", type=positive, default=8)
        s.add_argument("--operation-timeout", type=positive, default=15)
        s.add_argument("--total-timeout", type=positive, default=60)
        s.add_argument("--all", dest="all_devices", action="store_true", help="include dispositivi senza nome Oclean")
        s.add_argument("--log", help="nuovo file JSONL; non sovrascrive")
        if name != "scan":
            g = s.add_mutually_exclusive_group()
            g.add_argument("--index", type=positive_index)
            g.add_argument("--address", default=None)
    s = sub.add_parser("capture-sessions", help="opt-in: write 0307 + subscription fbb90, nessuna conferma")
    s.add_argument("--allow-session-query", action="store_true", help="autorizza la richiesta 0307 e la subscription/cleanup CCCD")
    s.add_argument("--scan-seconds", type=positive, default=8)
    s.add_argument("--operation-timeout", type=positive, default=30)
    s.add_argument("--total-timeout", type=positive, default=75)
    s.add_argument("--listen-seconds", type=positive, default=12)
    s.add_argument("--capture-dir", default="captures")
    s.add_argument("--log")
    g = s.add_mutually_exclusive_group()
    g.add_argument("--index", type=positive_index)
    g.add_argument("--address")
    s = sub.add_parser("normalize-sessions", help="archivio JSON e staging HealthKit, solo offline")
    s.add_argument("--capture-dir", default="captures")
    s.add_argument("--store", default="data/sessions.json")
    s.add_argument("--export", default="data/healthkit-candidates.json")
    s.add_argument("--observations", help="JSON privato delle osservazioni utente verificate")
    s.add_argument("--timezone", default="Europe/Rome", help="zona IANA per confronto, mai correzione implicita")
    s.add_argument("--log")
    s = sub.add_parser("decode-sessions", help="decodifica offline una cattura privata")
    s.add_argument("capture_file")
    s.add_argument("--output", required=True, help="nuovo JSON privato, non sovrascrive")
    s.add_argument("--log")
    s = sub.add_parser("decode-status", help="solo offline, payload sintetico o gia redatto")
    s.add_argument("hex_payload")
    s.add_argument("--log")
    return p


def main(argv=None):
    p = parser()
    args = p.parse_args(argv)
    if args.command in ("read", "gatt", "capture-sessions"):
        args.address = args.address or (os.environ.get("OPENBRUSHLAB_ADDRESS") if not args.index else None)
        if not args.index and not args.address:
            p.error("specificare --index oppure --address / OPENBRUSHLAB_ADDRESS")
    if args.command == "capture-sessions" and not args.allow_session_query:
        p.error("capture-sessions richiede --allow-session-query; nessuna operazione BLE eseguita")
    try:
        with JsonLog(sys.stdout, args.log) as log:
            if args.command == "normalize-sessions":
                from pathlib import Path
                from zoneinfo import ZoneInfoNotFoundError
                from .normalize import normalize
                try:
                    paths = list(Path(args.capture_dir).glob("*.raw.jsonl"))
                    if not paths and not Path(args.store).exists():
                        log.emit("error", reason="no-session-captures")
                        return 1
                    summary = normalize(paths, args.store, args.export,
                                        observations_path=args.observations, zone_name=args.timezone)
                    log.emit("normalization_summary", **summary)
                    return 0
                except ZoneInfoNotFoundError:
                    log.emit("error", reason="invalid-iana-zone-or-install-tzdata")
                except FileExistsError:
                    log.emit("error", reason="archive-locked")
                except (ValueError, TypeError, KeyError, AttributeError):
                    log.emit("error", reason="invalid-normalization-input-originals-preserved")
                return 1
            if args.command == "decode-sessions":
                from .sessions import decode_capture
                try:
                    result = decode_capture(args.capture_file, args.output)
                    log.emit("session_decode_summary", status=result["status"], records=len(result["records"]), healthkit_ready=False)
                    return 0 if result["status"] in ("complete-candidate", "zero-count-no-complete-history") else 2
                except (ValueError, TypeError, KeyError):
                    log.emit("error", reason="invalid-session-capture")
                    return 1
            if args.command == "capture-sessions":
                from .capture import run_capture
                return asyncio.run(run_capture(args, log))
            if args.command == "decode-status":
                try:
                    log.emit("offline_status", **decode_status(bytes.fromhex(args.hex_payload)))
                    return 0
                except ValueError:
                    log.emit("error", reason="invalid-status-payload")
                    return 1
            try:
                return asyncio.run(run_ble(args, log))
            except TimeoutError:
                log.emit("error", reason="total-timeout")
            except ImportError:
                log.emit("error", reason="install-dependencies")
            except Exception:
                log.emit("error", reason="ble-operation-failed-see-windows-troubleshooting")
            return 1
    except KeyboardInterrupt:
        return 130
    except OSError:
        print('{"schema":1,"event":"error","reason":"output-file-unavailable-or-already-exists"}', file=sys.stderr)
        return 1
