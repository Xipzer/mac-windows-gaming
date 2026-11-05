#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
k() { python3 "$D"/hold.py "$@"; }
t0=$(date +%s)
for _ in $(seq 1 80); do
  f=$("$D"/shot.sh le); t=$(python3 "$D"/ocr.py "$f" | cut -d' ' -f3- | tr '\n' '|')
  case "$t" in
    *"Seizure Warning"*) k space ;;
    *"Press any key"*) k space ;;
    *"CONTINUE GAME"*) k space ;;
    *"Confirm Load"*|*"Autosave"*) k space ;;
    *"Paused"*) k escape; sleep 1; echo "in game after $(( $(date +%s)-t0 ))s"; exit 0 ;;
    *"Find the"*|*"Taxi Rank"*) echo "in game after $(( $(date +%s)-t0 ))s"; exit 0 ;;
    *) u=$((${u:-0}+1)); [ $u -ge 3 ] && { k escape; u=0; } ;;
  esac
  sleep 1
done
echo "lego_enter failed"; exit 1
