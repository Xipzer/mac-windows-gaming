#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
O=${BENCH_OUT:-/tmp/steambridge-bench}
C="$HOME/Library/Application Support/Steam/steamapps/compatdata/208650"
k() { python3 "$D"/hold.py "$@"; }
t0=$(date +%s)
pkill -f 'Z:.*BatmanAK.exe'; for _ in $(seq 1 60); do pgrep -f 'compatibilitytools.d/steambridge/./run' >/dev/null || break; sleep 0.5; done
printf '%b\n' "$1" > "$C/steambridge.env"
open -b com.valvesoftware.steam "steam://rungameid/208650"
for _ in $(seq 1 120); do pgrep -f 'Z:.*BatmanAK.exe' >/dev/null && break; sleep 0.5; done
osascript -e 'tell application "System Events" to set visible of process "steam_osx" to false' >/dev/null 2>&1
clicked=0; focused=0
for _ in $(seq 1 150); do
  s=$("$D"/state.sh)
  case "$s" in
    options) echo "ready in $(( $(date +%s)-t0 ))s"; exit 0 ;;
    title) P=$(pgrep -f 'Z:.*BatmanAK.exe'|head -1)
           if ! lsappinfo info -only pid "$(lsappinfo front)" | grep -q "=$P\$"; then
             osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $P) to true" >/dev/null 2>&1; sleep 0.5
             usecomputer click -x 900 -y 600 >/dev/null 2>&1; clicked=1; sleep 1
           fi
           usecomputer press return >/dev/null 2>&1; sleep 2 ;;
    saves) if [ $focused = 0 ]; then P=$(pgrep -f 'Z:.*BatmanAK.exe'|head -1); osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $P) to true" >/dev/null 2>&1; focused=1; sleep 0.5; fi
           k return; sleep 3 ;;
    main) h=$(python3 "$D"/hl.py $O/st.png)
          if [ "$h" = OPTIONS ]; then k return; sleep 1; else k down; fi ;;
    exitdlg|synopsis) k escape ;;
    *)
       if [ $clicked = 0 ] && python3 -c "
import Quartz,sys
p=int('$(pgrep -f 'Z:.*BatmanAK.exe'|head -1)')
sys.exit(0 if any(w.get('kCGWindowOwnerPID')==p and w['kCGWindowBounds']['Width']>1000 for w in Quartz.CGWindowListCopyWindowInfo(0,0)) else 1)"; then
         usecomputer click -x 900 -y 600 >/dev/null 2>&1; clicked=1
       fi
       [ $clicked = 1 ] && usecomputer press escape >/dev/null 2>&1 ;;
  esac
done
echo "relaunch_fast failed ($s)"; exit 1
