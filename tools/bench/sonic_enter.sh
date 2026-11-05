#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
k() { python3 "$D"/hold.py "$@"; }
t0=$(date +%s)
for _ in $(seq 1 60); do
  f=$("$D"/shot.sh se); t=$(python3 "$D"/ocr.py "$f" | cut -d' ' -f3- | tr '\n' '|')
  case "$t" in
    *"Load data"*) k space; sleep 4 ;;
    *"|Continue|"*|*"Continue|New Game"*) k space; sleep 4 ;;
    *"Lv.1/99"*|*"Lv. 1/99"*) echo "in game after $(( $(date +%s)-t0 ))s"; exit 0 ;;
    *) sleep 1 ;;
  esac
done
echo "sonic_enter failed"; exit 1
