# SPDX-License-Identifier: GPL-3.0-only
"""Schema-based logging: never serialize arbitrary BLE objects or exceptions."""
import hashlib
import hmac
import json
import secrets
from datetime import datetime, timezone
from pathlib import Path


class JsonLog:
    def __init__(self, stream, path=None):
        self.stream = stream
        self.path = Path(path) if path else None
        self._key = secrets.token_bytes(32)
        self._file = None

    def token(self, address):
        return "device-" + hmac.new(self._key, address.upper().encode(), hashlib.sha256).hexdigest()[:16]

    def __enter__(self):
        if self.path:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            # Exclusive creation avoids overwriting previous captures.
            self._file = self.path.open("x", encoding="utf-8")
        return self

    def emit(self, event, **safe_fields):
        # Callers pass curated values only; this is not a general-purpose sanitizer.
        row = {"schema": 1, "utc": datetime.now(timezone.utc).isoformat(),
               "event": event, **safe_fields}
        line = json.dumps(row, ensure_ascii=True)
        self.stream.write(line + "\n")
        if self._file:
            self._file.write(line + "\n")
            self._file.flush()

    def __exit__(self, *exc):
        if self._file:
            self._file.close()
