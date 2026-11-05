#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
O=${BENCH_OUT:-/tmp/steambridge-bench}/sweep; mkdir -p $O
E="$(cat "$HOME/Library/Application Support/Steam/steamapps/compatdata/208650/steambridge.env")"
for m in "1024 665" "1147 745" "1280 800" "1352 878" "1512 982" "1800 1169"; do
  set -- $m; W=$(($1*2)); H=$(($2*2)); L="S${W}x${H}"
  pkill -f 'Z:.*BatmanAK.exe'; for _ in $(seq 1 40); do pgrep -f 'compatibilitytools.d/steambridge/./run' >/dev/null || break; sleep 1; done
  "$D"/dispmode set $1 $2 120; sleep 3
  python3 "$D"/setres.py $W $H >/dev/null
  "$D"/relaunch.sh "$E" >/dev/null || { echo "$L launch/nav failed"; continue; }
  "$D"/bench2.sh ${L}_warm >/dev/null
  FULLCAP=$O/full_$L.png "$D"/bench2.sh ${L} | tee -a $O/SWEEP.txt
  echo "$L $(sips -g pixelWidth -g pixelHeight $O/full_$L.png | awk '/pixel/{printf "%s ",$2}')" >> $O/captures.txt
done
pkill -f 'Z:.*BatmanAK.exe'; sleep 15
"$D"/dispmode set 1512 982 120; python3 "$D"/setres.py 3024 1964 >/dev/null
echo SWEEP_DONE
