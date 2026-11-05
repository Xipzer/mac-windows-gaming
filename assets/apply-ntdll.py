#!/usr/bin/env python3

import hashlib
import json
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 1
    spec = json.load(open(sys.argv[1]))
    path = sys.argv[2]
    data = bytearray(open(path, "rb").read())
    have = hashlib.sha256(data).hexdigest()
    if have == spec["patched_sha256"]:
        print(f"already patched: {path}")
        return 0
    if have != spec["clean_sha256"]:
        print(f"unknown ntdll.dll ({have}); expected clean {spec['clean_sha256']} "
              f"from engine {spec['engine']}", file=sys.stderr)
        return 2
    for r in spec["ranges"]:
        b = bytes.fromhex(r["bytes"])
        data[r["offset"]:r["offset"] + len(b)] = b
    got = hashlib.sha256(data).hexdigest()
    if got != spec["patched_sha256"]:
        print(f"patch produced {got}, expected {spec['patched_sha256']}", file=sys.stderr)
        return 3
    open(path, "wb").write(data)
    print(f"patched: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
