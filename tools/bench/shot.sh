#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
T=${BENCH_OUT:-/tmp/steambridge-bench}
n="${1:-s}_$(date +%H%M%S)"
rm -f "$D"/raw.png; usecomputer screenshot "$D"/raw.png >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$D"/raw.png ] && break; sleep 1; done; sleep 1
sips -Z 1000 "$D"/raw.png --out "$T/$n.png" >/dev/null && cp "$T/$n.png" "$T/st.png" && echo "$T/$n.png"
