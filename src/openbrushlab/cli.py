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
    p = argparse.ArgumentParser(description="OpenBrushLab: BLE di sola lettura, nessuna subscription")
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
    s = sub.add_parser("decode-status", help="solo offline, payload sintetico o gia redatto")
    s.add_argument("hex_payload")
    s.add_argument("--log")
    return p


def main(argv=None):
    p = parser()
    args = p.parse_args(argv)
    if args.command in ("read", "gatt"):
        args.address = args.address or (os.environ.get("OPENBRUSHLAB_ADDRESS") if not args.index else None)
        if not args.index and not args.address:
            p.error("specificare --index oppure --address / OPENBRUSHLAB_ADDRESS")
    try:
        with JsonLog(sys.stdout, args.log) as log:
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
