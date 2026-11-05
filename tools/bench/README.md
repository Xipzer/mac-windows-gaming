# Benchmark and input automation

Scripts that launch a game, drive its menus by OCR and synthetic input, and record fps, GPU and CPU load. Results go to `$BENCH_OUT` (default `/tmp/steambridge-bench`).

## Before a run

- Acquire the shared lock if it exists: `~/.hwlock/hw.sh acquire <owner>`; release with `~/.hwlock/hw.sh release <owner>`.
- The screen must be unlocked and awake. Screenshots, OCR and synthetic input fail on a locked screen.
- Nobody may touch the keyboard or mouse during a run.
- `mkdir -p "${BENCH_OUT:-/tmp/steambridge-bench}"`. The scripts do not create it.
- Needs: `usecomputer` CLI (screenshots, clicks), Python 3 with PyObjC (`Quartz`, `Vision`, `Foundation`) and Pillow, and Screen Recording plus Accessibility permission for the terminal.
- The launch scripts (`relaunch.sh`, `relaunch_fast.sh`, `cycle_game.sh`) overwrite `compatdata/<appid>/steambridge.env`. Run `scripts/apply-game-configs.sh` afterwards to restore the tuned profiles.

## Rules

- Never raise a game window with AppleScript while it is in menus. It bounces the game (Arkham Knight returns to save select).
- Games poll keys once per frame. Send real key down and up with a hold (`hold.py`, `keyhold.py`), not instant key presses.
- Check where you are by OCR (`ocr.py`) or highlight detection (`hl.py`), never by counting key presses.
- fps comes from the Metal HUD (`MTL_HUD_ENABLED=1`), read by `hudfps.py`. The HUD shows the drawable size, not the game's internal resolution.
- Interleave A and B configurations in one session with a warm shader cache, at least 3 runs each. Record results in `docs/BENCHMARKS.md` and `docs/LOG.md`.

## Scripts

`"<env lines>"` is the full new `steambridge.env`, lines separated by `\n` (written with `printf '%b'`).

| Script | Usage | Does |
|---|---|---|
| `relaunch.sh` | `relaunch.sh "<env lines>"` | Arkham Knight: write env, restart the game, stop at Options |
| `relaunch_fast.sh` | `relaunch_fast.sh "<env lines>"` | Same, faster, OCR state machine |
| `bench2.sh` | `bench2.sh <label>` | Arkham Knight: run PC Performance Test, log GPU, game and wineserver CPU, OCR min/max/avg into `$BENCH_OUT/RESULTS.txt` |
| `setres.py` | `setres.py W H` | Arkham Knight: set resolution in both settings files (game closed) |
| `sweep.sh` | `sweep.sh` | Arkham Knight resolution sweep. Needs a `dispmode` binary in this folder (copy `~/Library/Application Support/SteamBridge/dispmode`) |
| `cycle_game.sh` | `cycle_game.sh <appid> <exe-pattern> <enter-script> "<env lines>"` | Restart any game with a given env and run its entry script |
| `route.sh` | `route.sh <label> <exe-pattern> <walk-script>` | Run a walk script while sampling HUD fps; prints avg, p10, min, GPU %, game CPU % |
| `idle_hud.sh` | `idle_hud.sh <label> <exe-pattern> <seconds>` | Same as `route.sh` without moving |
| `state.sh` | `state.sh` | Screenshot plus OCR, prints the Arkham Knight menu state |
| `shot.sh` | `shot.sh [name]` | Screenshot into `$BENCH_OUT`, prints the path |
| `ocr.py` | `ocr.py <png>` | Vision OCR, prints `x y text` per line (x, y scaled to 1000 wide) |
| `hl.py`, `resocr.py`, `hudfps.py` | `<png>` | Highlighted menu item, benchmark result numbers, HUD fps and GPU time |
| `hold.py` | `hold.py <key> [count]` | Key press with a 0.12 s hold |
| `keyhold.py` | `keyhold.py <keys...> <seconds>` | Hold keys for a duration (walking) |
| `click.py`, `click2.py`, `hover.py` | `<x> <y>` | Mouse input in 1000-wide coordinates |
| `thprio.c` | `thprio PID` | Print thread priorities and CPU time of a process |

## Per-game entry and routes

| Game | Exe pattern | Entry | Route | Confirm key |
|---|---|---|---|---|
| Batman: Arkham Knight | `BatmanAK.exe` | `relaunch_fast.sh` | `bench2.sh` (built-in benchmark) | Enter |
| LEGO Star Wars TSS | `LEGOSTARWARS` | `lego_enter.sh` (loads the cloud save into Mos Eisley, about 90 s) | `walk_lego.sh` (48 s loop) | Space |
| Sonic Frontiers | `SonicFrontiers` | `sonic_enter.sh` (Continue, AUTO save, Kronos Island, about 40 s) | `walk_sonic.sh` | Space |
| Dragon Ball: Sparking! ZERO | `SparkingZERO-Win64` | `dbz_title.sh` (clicks "No" on the driver warning, waits for "Start Game", about 45 s) | not scripted | |

## Examples

```sh
cd tools/bench
./relaunch_fast.sh "$(cat ~/Library/Application\ Support/Steam/steamapps/compatdata/208650/steambridge.env)"
./bench2.sh mylabel
./cycle_game.sh 920210 LEGOSTARWARS ./lego_enter.sh "MTL_HUD_ENABLED=1"
./route.sh lego LEGOSTARWARS ./walk_lego.sh
```
