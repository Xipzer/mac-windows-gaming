#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
L=$1; P=$2; W=$3; O=${BENCH_OUT:-/tmp/steambridge-bench}; : > "$O/$L.log"
sh "$W" & wp=$!
while kill -0 $wp 2>/dev/null; do
  g=$(ioreg -r -c IOAccelerator -d 1 | grep -oE '"Device Utilization %"=[0-9]+' | head -1 | cut -d= -f2)
  c=$(ps -Ao pcpu,comm | awk -v p="$P" '$0~p && /Z:/{print $1}' | head -1)
  rm -f "$D"/r.png; usecomputer screenshot "$D"/r.png >/dev/null 2>&1; for _ in 1 2 3 4 5; do [ -s "$D"/r.png ] && break; sleep 0.5; done
  h=$(python3 "$D"/hudfps.py "$D"/r.png 2>/dev/null)
  echo "gpu=$g game=$c hud=$h" >> "$O/$L.log"
done
python3 - "$O/$L.log" "$L" <<'PY'
import sys,re,statistics as st
f=[];g=[];c=[]
for l in open(sys.argv[1]):
    m=re.search(r'gpu=(\d+) game=([\d.]+) hud=([\d.]+)',l)
    if m: g.append(int(m[1]));c.append(float(m[2]));f.append(float(m[3]))
if f:
    f.sort(); low=f[max(0,len(f)//10-1)]
    print(f"{sys.argv[2]} fps avg={st.mean(f):.0f} p10={low:.0f} min={f[0]:.0f} n={len(f)} gpu={st.mean(g):.0f}% game={st.mean(c):.0f}%")
else: print(sys.argv[2],"no HUD fps read")
PY
