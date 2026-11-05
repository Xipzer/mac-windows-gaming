#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
f=$("$D"/shot.sh st); t=$(python3 "$D"/ocr.py "$f")
echo "$t" > "$D"/state.txt
case "$t" in
  *"SYNOPSIS"*) echo synopsis ;;
  *"exit to desktop"*|*"wish to exit"*) echo exitdlg ;;
  *"Benchmark complete"*) echo results ;;
  *"PC PERFORMANCE TEST"*) echo options ;;
  *"CONTINUE STORY"*) echo main ;;
  *"SAVED GAME"*|*"SAVED"*"GAME"*) echo saves ;;
  *"LICK HERE"*|*"lick here"*) echo title ;;
  *) echo other ;;
esac
