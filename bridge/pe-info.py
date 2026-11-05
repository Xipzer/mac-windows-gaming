#!/usr/bin/env python3

import hashlib
import struct
import sys

MACHINE = {0x014C: "i386", 0x8664: "x86_64"}


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: pe-info.py <pe-file>")

    data = bytearray(open(sys.argv[1], "rb").read())
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        sys.exit(f"{sys.argv[1]}: not a PE file")

    machine = struct.unpack_from("<H", data, pe + 4)[0]
    for off in (pe + 8, pe + 24 + 64):
        data[off:off + 4] = b"\0\0\0\0"

    print(MACHINE.get(machine, hex(machine)), hashlib.sha256(data).hexdigest()[:16])


if __name__ == "__main__":
    main()
