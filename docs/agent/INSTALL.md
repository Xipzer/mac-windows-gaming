# Agent runbook: install on a fresh Mac

Follow the steps in order. Each step has a command, the expected result, and what to do otherwise. Stop and report to the human when a step says so. Do not skip verification.

Rules for the whole runbook:

- Never delete anything under `~/Library/Application Support/Steam/steamapps`.
- Never type or store the human's passwords. When a step needs a password or a click, ask the human to do it.
- Do not launch games yourself unless the human asked you to.

## 0. Preflight

Run each check. All must pass before step 1.

| # | Command | Expected | If not |
|---|---|---|---|
| 0.1 | `uname -m` | `arm64` | Stop. Tell the human: "This Mac is not Apple Silicon; SteamBridge cannot run here." |
| 0.2 | `sw_vers -productVersion` | `26.x` or `27.x` | Below 14: stop, the installer refuses it. 14 or 15: untested, ask the human whether to continue |
| 0.3 | `xcode-select -p` | A path, usually `/Library/Developer/CommandLineTools` | Run `xcode-select --install`. Ask the human: "A dialog asks to install the Command Line Tools. Please click Install and tell me when it finishes." Then re-run 0.3 |
| 0.4 | `arch -x86_64 /usr/bin/true; echo $?` | `0` | Run `softwareupdate --install-rosetta --agree-to-license`. If it fails for permissions, ask the human to run `sudo softwareupdate --install-rosetta --agree-to-license`. Re-run 0.4 |
| 0.5 | `df -g / \| awk 'NR==2{print $4}'` | 3 or more (GB free), plus room for games | Tell the human how much space is free and that about 3 GB plus the games is needed |
| 0.6 | `git --version` | `git version ...` | Comes with 0.3. Re-run 0.3 |
| 0.7 | `test -d /Applications/Steam.app && echo yes` | `yes` | Fine: the installer installs Steam, then stops (see step 1) |
| 0.8 | `ls "$HOME/Library/Application Support/Steam/userdata" 2>/dev/null` | At least one numeric folder | Steam was never logged in. Do 0.9 |
| 0.9 | Human step | | Ask: "Please open Steam, log in to your account, wait until it finishes updating, then quit Steam (Steam menu > Quit Steam). Tell me when done." Re-run 0.8 |
| 0.10 | `pgrep -fl 'wineserver\|wine-preloader'` | No output | A Windows game is running. Ask the human to quit it |
| 0.11 | `command -v brew` | A path | Fine: the installer installs Homebrew. It may ask for the human's password in the terminal; tell the human to expect that |

## 1. Install

Pick one.

From a clone (preferred: the agent can read the scripts):

```sh
git clone https://github.com/Xipzer/mac-windows-gaming.git "$HOME/mac-windows-gaming"
cd "$HOME/mac-windows-gaming"
./install.sh 2>&1 | tee "$TMPDIR/steambridge-install.log"
```

Without a clone (repo goes to `~/Library/Caches/steambridge/repo`):

```sh
curl -fsSL https://raw.githubusercontent.com/Xipzer/mac-windows-gaming/main/install.sh | bash
```

The installer quits Steam on its own. It takes several minutes (build plus about 1 GB of downloads).

Expected, near the end:

```
  ok Built steambridge.dylib (log: .../SteamBridge/setup/build.log)
  ok ntdll patched (runner + bridge)
  ok Steam.app patched and re-signed
  ok Compatibility tool installed
  ok Run script responds
==> Done. Start Steam:  open -a Steam
```

and then the installer's own `Done.` block.

| Result | Do |
|---|---|
| Output ends with `Open Steam once, log in, let it finish updating, quit it, then re-run this installer.` | Steam was just installed. Do step 0.9, then run step 1 again |
| `xx Missing '<tool>'. Run: xcode-select --install` | Step 0.3 |
| `xx A Wine process is running` | Step 0.10 |
| `xx checksum mismatch for <url>` | Network or upstream file changed. Retry once. If it repeats, stop and report the URL |
| Build failure (last 20 lines of `build.log` printed) | Read `~/Library/Application Support/SteamBridge/setup/build.log`. Re-run with `scripts/setup.sh --force` once. If it repeats, stop and report the log tail |
| `xx Valve bridge fetch failed` | Read `~/Library/Application Support/SteamBridge/setup/valve-fetch.log`. Retry once |
| `!! Run script self-test returned ...` | Run `bash scripts/doctor.sh` and fix what it names |

## 2. Human: first launch of each game

The tuned profiles only install into games that have a prefix, and a prefix exists only after the first launch. Ask the human:

"Please open Steam, install the Windows games you want, and start each one once until its menu appears, then quit it. Tell me which games you launched."

Tuned App IDs: 208650 (Batman: Arkham Knight), 920210 (LEGO Star Wars: The Skywalker Saga), 1237320 (Sonic Frontiers), 1790600 (Dragon Ball: Sparking! ZERO). For Dragon Ball, first tell the human to set this launch option (Steam > game > Properties > Launch Options):

```
"$HOME/Library/Application Support/SteamBridge/direct-shipping.sh" %command%
```

Check the prefixes exist:

```sh
ls "$HOME/Library/Application Support/Steam/steamapps/compatdata"
```

Expected: a folder named after each launched App ID.

## 3. Apply tuned profiles

Steam may stay open. The games must be closed.

```sh
scripts/apply-game-configs.sh
```

Expected: `ok profile <appid>` for each launched tuned game and `-- profile <appid> (game not installed or never launched)` for the rest, plus `ok` lines for in-game settings that were found.

The in-game resolutions it writes (3024x1964, 3024x1701) and `STEAMBRIDGE_DESKTOP_MODE=1512x982` fit a 14" MacBook Pro. On another Mac, run `"$HOME/Library/Application Support/SteamBridge/dispmode" list`, tell the human the panel's native mode, and ask before changing profiles (see [OPERATIONS.md](OPERATIONS.md#add-a-game-profile)).

## 4. Verify

| # | Command | Expected | If not |
|---|---|---|---|
| 4.1 | `bash scripts/doctor.sh; echo "exit $?"` | `ok No issues found`, `exit 0` | Each `!!` line names a fix command. Run it, then repeat 4.1 |
| 4.2 | Ask the human to open Steam (`open -a Steam`), wait 30 s | | |
| 4.3 | `grep -E 'install_thread: ready, [0-9]+/[0-9]+ hooks installed' "$HOME/Library/Application Support/SteamBridge/steambridge.log" \| tail -1` | `ready, N/N hooks installed` with both numbers equal and above 0 | `installing nothing` or no line: quit Steam, `scripts/setup.sh --skip-build`, repeat 4.2 and 4.3. Still failing: no signatures for this Steam build yet; stop and report the `sb_init` and `install_thread` lines |
| 4.4 | After the human starts a game: `tail -n 30 "$HOME/Library/Application Support/Steam/steamapps/compatdata/<appid>/steambridge-run.log"` | `video: renderer=...`, `=== bridge staged into ...`, `=== launching (waitforexitandrun): ...` | See the failure table |
| 4.5 | After the game quits | `=== game exited status=0, killing wine prefix ===` | Non-zero status: read `~/Library/Application Support/SteamBridge/launchers/<appid>/steambridge-wine.log` |

Tell the human what works and give them: `bash scripts/doctor.sh` for health, `scripts/setup.sh --skip-build` after Steam updates.

## Failure table

| Symptom | Diagnose | Fix |
|---|---|---|
| No Play button on Windows games | `grep -c steambridge.dylib /Applications/Steam.app/Contents/Info.plist`; step 4.3 | Quit Steam, `scripts/setup.sh --skip-build` |
| Game never starts, no run log | `ls "$HOME/Library/Application Support/Steam/compatibilitytools.d/steambridge"` | Missing `run`: `scripts/setup.sh --skip-build`. Present: ask the human to check Properties > Compatibility uses SteamBridge |
| Run log ends with `=== aborted during <step> ...` | Read the lines above it | Most often a runner or bridge file is missing: `scripts/setup.sh --skip-build` |
| `Application load error 3:0000065432` | `bash scripts/doctor.sh` (Steam bridge section) | `scripts/setup.sh --skip-build` |
| Run log: `runner x86_64-windows ntdll is not the patched copy` | `bash scripts/doctor.sh` (Runner section) | `scripts/setup.sh --skip-build` |
| Game hangs before its window | `grep 'sync:' <run log>` | Add `WINEMSYNC=0` to `compatdata/<appid>/steambridge.env` |
| Black window with DXMT | `grep renderer= <run log>` | Remove `STEAMBRIDGE_RENDERER=dxmt` (back to D3DMetal) |
| Nothing x86 runs after a macOS upgrade | `arch -x86_64 /usr/bin/true; echo $?` | `softwareupdate --install-rosetta --agree-to-license` |
| Prefix rebuild dialog | `grep 'prefix ntdll is' <run log>` | Ask the human before moving `pfx` aside ([TROUBLESHOOTING.md](../TROUBLESHOOTING.md)) |
| Anything else | `bash scripts/doctor.sh` | [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) |
