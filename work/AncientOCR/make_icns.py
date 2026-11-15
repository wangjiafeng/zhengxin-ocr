#!/usr/bin/env python3
"""Create a modern PNG-backed ICNS file from an iconset directory."""

from __future__ import annotations

import struct
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make_icns.py ICONSET OUTPUT.icns")
    iconset = Path(sys.argv[1])
    output = Path(sys.argv[2])
    entries = [
        (b"icp4", "icon_16x16.png"),
        (b"icp5", "icon_32x32.png"),
        (b"icp6", "icon_32x32@2x.png"),
        (b"ic07", "icon_128x128.png"),
        (b"ic08", "icon_256x256.png"),
        (b"ic09", "icon_512x512.png"),
        (b"ic10", "icon_512x512@2x.png"),
    ]
    payloads = []
    for kind, filename in entries:
        data = (iconset / filename).read_bytes()
        payloads.append(kind + struct.pack(">I", len(data) + 8) + data)
    body = b"".join(payloads)
    output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    main()
