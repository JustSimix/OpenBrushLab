# SPDX-License-Identifier: GPL-3.0-only
"""Only scanning, service enumeration and allowlisted GATT reads.

No notification subscription: enabling CCCD can itself cause a GATT write.
"""
import asyncio
from .protocol import (OCLEAN_SERVICE_UUID, READ_FIELDS, EXPECTED_SERVICES, decode_value)


async def scan(scanner, timeout, log, all_devices=False):
    found = await scanner.discover(timeout=timeout, return_adv=True)
    candidates = []
    for device, adv in sorted(found.values(), key=lambda pair: pair[0].address.upper()):
        name = adv.local_name or device.name or ""
        likely = "oclean" in name.lower() or OCLEAN_SERVICE_UUID in [u.lower() for u in adv.service_uuids]
        if not (likely or all_devices):
            continue
        candidates.append(device)
        log.emit("advertisement", index=len(candidates), device=log.token(device.address),
                 oclean_candidate=likely, rssi=adv.rssi)
    log.emit("scan_complete", count=len(candidates))
    return candidates


async def inspect(client_factory, device, mode, timeout, log):
    async with client_factory(device, pair=False, timeout=timeout) as client:
        log.emit("connected", device=log.token(device.address))
        if mode == "gatt":
            for service in client.services:
                log.emit("service", uuid=service.uuid, handle=service.handle)
                for char in service.characteristics:
                    log.emit("characteristic", service=service.uuid, uuid=char.uuid,
                             handle=char.handle, properties=sorted(char.properties),
                             descriptors=[{"uuid": d.uuid, "handle": d.handle} for d in char.descriptors])
            return 0
        available = {}
        for service in client.services:
            for char in service.characteristics:
                field = READ_FIELDS.get(char.uuid.lower())
                if field and service.uuid.lower() == EXPECTED_SERVICES[field]:
                    available.setdefault(char.uuid.lower(), []).append(char)
        failures = 0
        for uuid, field in READ_FIELDS.items():
            matches = available.get(uuid, [])
            if len(matches) != 1 or "read" not in matches[0].properties:
                log.emit("read_skipped", field=field, reason="missing-unreadable-or-ambiguous")
                failures += 1
                continue
            try:
                async with asyncio.timeout(timeout):
                    payload = await client.read_gatt_char(matches[0])
                value = decode_value(field, payload)
                log.emit("read", field=field, value=value)
                if field == "firmware":
                    log.emit("target_comparison", expected="1.0.0.36", matches=value == "1.0.0.36",
                             compatibility="unvalidated")
            except Exception:
                # Backend messages may include addresses, paths or identifiers.
                log.emit("read_failed", field=field, reason="read-or-decode-error")
                failures += 1
        return 2 if failures else 0


async def run_ble(args, log, scanner=None, client_factory=None):
    if scanner is None or client_factory is None:
        from bleak import BleakScanner, BleakClient
        scanner = scanner or BleakScanner
        client_factory = client_factory or BleakClient
    async with asyncio.timeout(args.total_timeout):
        devices = await scan(scanner, args.scan_seconds, log, args.all_devices)
        if args.command == "scan":
            return 0
        if args.address:
            matches = [d for d in devices if d.address.upper() == args.address.upper()]
            if len(matches) != 1:
                log.emit("error", reason="target-not-found-use-all-if-unnamed")
                return 1
            device = matches[0]
        else:
            if not args.index or args.index > len(devices):
                log.emit("error", reason="index-not-found")
                return 1
            device = devices[args.index - 1]
        return await inspect(client_factory, device, args.command, args.operation_timeout, log)
