#!/bin/sh
C="$HOME/Library/Application Support/Steam/steamapps/compatdata/$1"
pkill -f "Z:.*$2"; for _ in $(seq 1 40); do pgrep -f 'compatibilitytools.d/steambridge/./run' >/dev/null || break; sleep 1; done
printf '%b\n' "$4" > "$C/steambridge.env"
open -b com.valvesoftware.steam "steam://rungameid/$1"
for _ in $(seq 1 60); do pgrep -f "Z:.*$2" >/dev/null && break; sleep 2; done
sleep 20; osascript -e 'tell application "System Events" to set visible of process "steam_osx" to false' >/dev/null 2>&1
usecomputer click -x 900 -y 600 >/dev/null 2>&1
sh "$3"
