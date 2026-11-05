#!/usr/bin/env python3
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[2]

wanted = {}
for path in sorted((root / "dylib").rglob("*.c")):
    text = path.read_text()
    for pattern in (r'\.signature\s*=\s*"([^"]+)"',
                    r'sb_resolve_find\s*\(\s*\w+\s*,\s*"([^"]+)"',
                    r'sb_lookup_address\s*\(\s*\w+\s*,\s*\n?\s*"([^"]+)"'):
        for name in re.findall(pattern, text):
            wanted.setdefault(name, path.relative_to(root))

if not wanted:
    sys.exit("sigcheck: no signature names found in dylib/, the patterns are stale")

dbs = sorted((root / "signatures").rglob("*.json"))
if not dbs:
    sys.exit("sigcheck: no signature database under signatures/")

status = 0
for db in dbs:
    have = {s["name"] for s in json.load(db.open())["signatures"]}
    rel = db.relative_to(root)

    missing = {n: src for n, src in wanted.items() if n not in have}
    for name in sorted(missing):
        print("%s: MISSING %s (wanted by %s)" % (rel, name, missing[name]))
        status = 1

    for name in sorted(have - set(wanted)):
        print("%s: unused %s" % (rel, name))
        status = 1

    if not missing and have == set(wanted):
        print("%s: %d signatures, all referenced" % (rel, len(have)))

sys.exit(status)
