#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
L=$1; O=${BENCH_OUT:-/tmp/steambridge-bench}
for _ in 1 2 3 4 5 6 7 8; do
  "$D"/state.sh >/dev/null; h=$(python3 "$D"/hl.py $O/st.png)
  [ "$h" = "PC PERFORMANCE TEST" ] && break
  python3 "$D"/hold.py down; sleep 3
done
[ "$h" = "PC PERFORMANCE TEST" ] || { echo "$L: not on PC test (hl=$h)"; exit 1; }
python3 "$D"/hold.py return; sleep 12
c=$(ps -Ao pcpu,comm | awk '/BatmanAK/{print $1}' | head -1)
[ "${c%.*}" -gt 110 ] || { python3 "$D"/hold.py return; sleep 12; c=$(ps -Ao pcpu,comm | awk '/BatmanAK/{print $1}' | head -1); }
[ "${c%.*}" -gt 110 ] || { echo "$L: did not start"; exit 1; }
: > $O/$L.log
for i in $(seq 1 46); do
  g=$(ioreg -r -c IOAccelerator -d 1 | grep -oE '"Device Utilization %"=[0-9]+' | head -1 | cut -d= -f2)
  ws=$(ps -Ao pcpu,comm | awk '/bin\/wineserver/{print $1}' | head -1)
  gm=$(ps -Ao pcpu,comm | awk '/BatmanAK/{print $1}' | head -1)
  echo "$i gpu=$g game=$gm ws=$ws" >> $O/$L.log; sleep 2
done
for _ in $(seq 1 40); do [ "$("$D"/state.sh)" = results ] && break; sleep 3; done
cp $O/st.png $O/res_$L.png
[ -n "$FULLCAP" ] && screencapture -x -t png "$FULLCAP"
R=$(python3 "$D"/resocr.py "$O/res_$L.png")
awk -v L="$L" -v R="$R" '{split($2,a,"=");split($3,b,"=");split($4,c,"=");g+=a[2];m+=b[2];w+=c[2];n++} END{printf "%s min/max/avg=%s gpu=%.0f%% game=%.0f%% wineserver=%.1f%%\n",L,R,g/n,m/n,w/n}' $O/$L.log | tee -a $O/RESULTS.txt
python3 "$D"/hold.py return; sleep 6
