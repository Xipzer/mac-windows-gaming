#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
t0=$(date +%s)
for _ in $(seq 1 120); do
  P=$(pgrep -f 'Z:.*SparkingZERO-Win64'|head -1)
  w=$(python3 -c "
import Quartz
for w in Quartz.CGWindowListCopyWindowInfo(0,0):
  if w.get('kCGWindowOwnerPID')==int('${P:-0}') and w.get('kCGWindowIsOnscreen'):
    b=w['kCGWindowBounds']; print(int(b['Width']),int(b['Height']),int(b['X']),int(b['Y'])); break")
  set -- $w
  if [ -n "$1" ] && [ "$1" -lt 600 ]; then
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $P) to true" >/dev/null 2>&1
    sleep 0.5
    usecomputer click -x $(( $3 + $1*62/100 )) -y $(( $4 + $2*90/100 )) >/dev/null 2>&1; sleep 3; continue
  fi
  if [ -n "$1" ] && [ "$1" -gt 1000 ]; then
    osascript -e 'tell application "System Events" to set visible of process "steam_osx" to false' >/dev/null 2>&1
    f=$("$D"/shot.sh dz); o=$(python3 "$D"/ocr.py "$f")
    if echo "$o" | grep -qiE "press any|press.*button|Start Game"; then echo "title after $(( $(date +%s)-t0 ))s"; exit 0; fi
  fi
  sleep 2
done
echo "dbz_title timeout"; exit 1
