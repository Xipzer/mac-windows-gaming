import hashlib
import json
import sys

JOIN_WITHIN = 16


def ranges(a, b):
    assert len(a) == len(b), 'the detour lives in section padding, so the size never changes'
    out, start, last = [], None, None
    for i in range(len(a)):
        if a[i] == b[i]:
            continue
        if start is not None and i - last > JOIN_WITHIN:
            out.append((start, last + 1))
            start = None
        if start is None:
            start = i
        last = i
    if start is not None:
        out.append((start, last + 1))
    return [{'offset': s, 'bytes': b[s:e].hex()} for s, e in out]


def main():
    clean_path, patched_path, engine, file, note = sys.argv[1:]
    clean, patched = open(clean_path, 'rb').read(), open(patched_path, 'rb').read()
    spec = {
        'engine': engine,
        'file': file,
        'clean_sha256': hashlib.sha256(clean).hexdigest(),
        'patched_sha256': hashlib.sha256(patched).hexdigest(),
        'note': note,
        'ranges': ranges(clean, patched),
    }
    json.dump(spec, sys.stdout, indent=1)
    print()


if __name__ == '__main__':
    main()
