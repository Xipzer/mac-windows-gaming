#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
O=${BENCH_OUT:-/tmp/steambridge-bench}
C="$HOME/Library/Application Support/Steam/steamapps/compatdata/208650"
k() { python3 "$D"/hold.py "$@"; }
focus() { P=$(pgrep -f 'Z:.*BatmanAK.exe'|head -1); osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $P) to true" >/dev/null 2>&1; sleep 1; }
pkill -f 'Z:.*BatmanAK.exe'; for _ in $(seq 1 40); do pgrep -f 'compatibilitytools.d/steambridge/./run' >/dev/null || break; sleep 1; done
printf '%b\n' "$1" > "$C/steambridge.env"
open -b com.valvesoftware.steam "steam://rungameid/208650"
for _ in $(seq 1 60); do pgrep -f 'Z:.*BatmanAK.exe' >/dev/null && break; sleep 2; done
sleep 30; osascript -e 'tell application "System Events" to set visible of process "steam_osx" to false' >/dev/null 2>&1
usecomputer click -x 900 -y 600 >/dev/null 2>&1
for _ in $(seq 1 40); do
  s=$("$D"/state.sh)
  case "$s" in
    options) echo "ready: $(grep -E 'launch_env|sync:' "$C/steambridge-run.log" | tail -2 | tr '\n' ' ')"; exit 0 ;;
    title) if [ "${tt:-0}" -lt 2 ]; then usecomputer press return >/dev/null 2>&1; else focus; k return; fi; tt=$(( ${tt:-0} + 1 )); sleep 12 ;;
    saves) focus; k return; sleep 15 ;;
    main) h=$(python3 "$D"/hl.py "$O/st.png")
          if [ "$h" = OPTIONS ]; then k return; sleep 6; else k down; sleep 3; fi ;;
    exitdlg|synopsis) k escape; sleep 5 ;;
    *) usecomputer press escape >/dev/null 2>&1; sleep 4 ;;
  esac
done
echo "relaunch nav failed ($s)"; exit 1
