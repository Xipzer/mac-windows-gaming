# Agent runbook: operations

Tasks a human may ask for after the install. Read [AGENTS.md](../../AGENTS.md) rules first. Paths: `$C` means `~/Library/Application Support/Steam/steamapps/compatdata`, `$SB` means `~/Library/Application Support/SteamBridge`.

## Add a game profile

1. Check the game: `bash scripts/check-compat.sh <appid>`. Exit 3 (blocked): stop and tell the human why. Output `RUN NATIVE INSTEAD`: tell the human to use the Mac version.
2. The human installs and launches the game once, so `$C/<appid>` exists.
3. Find the DirectX version (store page, PCGamingWiki, or the run log's DLL loads).
4. Pick settings. Change one thing at a time and keep what the benchmark proves.

| Decision | Rule |
|---|---|
| Renderer, DX12 | D3DMetal (default, nothing to set) |
| Renderer, DX11 | Try `STEAMBRIDGE_RENDERER=dxmt` first. If it shows a black window, crashes, or is slower, use D3DMetal. For DXMT also try `STEAMBRIDGE_DXMT=dxmt-codegen` plus its `DXMT_CONFIG` keys ([CONFIG.md](../CONFIG.md)) |
| Renderer, DX9/10 | DXMT, else `dxvk` |
| Sync | msync is on by default. Set `WINEMSYNC=0` only if the game hangs before its window appears |
| AVX | Leave on. `ROSETTA_ADVERTISE_AVX=0` only if an interleaved benchmark shows a gain, and never for games that need AVX |
| Resolution | Set `STEAMBRIDGE_DESKTOP_MODE` to half the panel size in points (`1512x982` on a 14" MacBook Pro; `"$SB/dispmode" list` on others). Then set the full native size in the game's own settings file, with the game closed |
| fps cap | Keep a game's cap if its speed is tied to frame rate |
| Unreal launcher spins | Launch option `"$HOME/Library/Application Support/SteamBridge/direct-shipping.sh" %command%` (only handles `SparkingZERO.exe` today; extend `assets/direct-shipping.sh` for others) |

5. Write `$C/<appid>/steambridge.env`, one `NAME=value` per line, no quotes.
6. The human launches the game. Check `$C/<appid>/steambridge-run.log` for `video: renderer=<yours>` and `sync: WINEMSYNC=<yours>`.
7. Measure (see [Benchmarks](#run-benchmarks)) if the human wants numbers.
8. Save to the repo: copy the file to `configs/games/<appid>.env`. If you edit in-game settings files, add the same edit to `scripts/apply-game-configs.sh` following the existing blocks. Add the game to `KNOWN` in `scripts/check-compat.sh`, to [GAMES.md](../GAMES.md), and record numbers in [BENCHMARKS.md](../BENCHMARKS.md) and [LOG.md](../LOG.md).
9. Verify: `make scriptcheck`, then `bash scripts/doctor.sh` shows `<appid>: matches repo`.

## After a Steam update

Symptom: Windows games have no Play button or do not start.

1. `bash scripts/doctor.sh`. Look at the Steam.app section.
2. `scripts/setup.sh --skip-build` (quits Steam itself; needs no game running).
3. Ask the human to start Steam. Check hooks: `grep -E 'install_thread: ready, [0-9]+/[0-9]+ hooks installed' "$SB/steambridge.log" | tail -1`.
4. Still `installing nothing`: no signature set matches this Steam build yet. Report the build number from `bash scripts/doctor.sh` (`client build:` line). Do not hand-edit signatures.

## After a macOS update

1. `arch -x86_64 /usr/bin/true; echo $?`. Not `0`: `softwareupdate --install-rosetta --agree-to-license` (major upgrades, such as to 27, remove Rosetta).
2. `bash scripts/doctor.sh`.
3. Do not benchmark for about a day after an upgrade: Spotlight reindexing lowers performance.
4. Tell the human to hold further minor updates until this one is verified.

## Update SteamBridge itself

```sh
git -C <repo> pull --ff-only
<repo>/scripts/setup.sh
```

Use the full build, not `--skip-build`, whenever `dylib/` changed: the dylib embeds `dylib/feats/compat_run.sh` and rewrites the installed `run` from that copy every time Steam starts. Then `scripts/apply-game-configs.sh` if `configs/games` changed.

## Run benchmarks

Only when asked. Full tool list: [tools/bench/README.md](../../tools/bench/README.md).

1. If `~/.hwlock/hw.sh` exists: `~/.hwlock/hw.sh acquire <your-name>`. Do not start until it prints `held by`.
2. Confirm with the human that the screen is unlocked and that nobody will touch keyboard or mouse.
3. `mkdir -p /tmp/steambridge-bench`.
4. Batman built-in benchmark, per configuration:
   ```sh
   cd tools/bench
   ./relaunch_fast.sh "$(cat "$HOME/Library/Application Support/Steam/steamapps/compatdata/208650/steambridge.env")"
   ./bench2.sh <label>
   ```
   Results append to `/tmp/steambridge-bench/RESULTS.txt`.
5. Other games: `./cycle_game.sh <appid> <exe-pattern> ./<game>_enter.sh "<env lines incl. MTL_HUD_ENABLED=1>"`, then `./route.sh <label> <exe-pattern> ./walk_<game>.sh`.
6. Interleave A and B, at least 3 runs each, ignore the first (cold shader cache).
7. Restore profiles: `scripts/apply-game-configs.sh`. Release the lock: `~/.hwlock/hw.sh release <your-name>`.
8. Record results in `docs/BENCHMARKS.md` and `docs/LOG.md` with machine, macOS version, resolution and settings.

## Collect logs for a bug report

```sh
A=<appid>
D="$TMPDIR/steambridge-report"; mkdir -p "$D"
bash scripts/doctor.sh > "$D/doctor.txt" 2>&1
cp "$HOME/Library/Application Support/SteamBridge/steambridge.log" "$D/" 2>/dev/null
cp "$HOME/Library/Application Support/SteamBridge/setup/build.log" "$D/" 2>/dev/null
cp "$HOME/Library/Application Support/Steam/steamapps/compatdata/$A/steambridge-run.log" "$D/" 2>/dev/null
cp "$HOME/Library/Application Support/Steam/steamapps/compatdata/$A/steambridge.env" "$D/" 2>/dev/null
cp "$HOME/Library/Application Support/SteamBridge/launchers/$A/steambridge-wine.log" "$D/" 2>/dev/null
sw_vers > "$D/system.txt"; uname -m >> "$D/system.txt"
ls "$D"
```

Logs contain the macOS user name and paths. Show the human the folder and let them decide what to share. Never include files from `userdata` or `config/` (account data).

## Uninstall

1. Confirm with the human. Games and saves are kept either way.
2. `scripts/setup.sh --uninstall`. Expected: `ok Restored stock Steam.app from ...` and `ok Removed the compatibility tool`.
3. Only if the human wants everything gone: `rm -rf "$HOME/Library/Application Support/SteamBridge" "$HOME/Library/Caches/steambridge"`. This deletes the runner and launchers, not the prefixes (those are in `steamapps/compatdata`, leave them).
4. Heroic, if unwanted: `brew uninstall --cask heroic`.
