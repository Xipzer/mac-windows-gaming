# Arkham Knight benchmark automation

1. `relaunch.sh "<env lines>"`: restarts the game with that per-game env and stops at Options.
2. `bench2.sh <label>`: runs the PC Performance Test, logs GPU/CPU/wineserver load, OCRs min/max/avg into `$BENCH_OUT/RESULTS.txt`.
3. `setres.py W H`: sets the game resolution (game must be closed).

Input notes: the game polls keys per frame, so `hold.py` sends real key down/up with a hold. Never raise the window
with AppleScript while in menus (it bounces the game to save select). Menu selection is verified by OCR (`ocr.py`) and
the cyan highlight bar (`hl.py`), never by blind key counts.
