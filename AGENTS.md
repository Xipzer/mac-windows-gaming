# AGENTS.md — driving this repo as an AI agent

This file tells an autonomous agent how to set up / repair a free Windows-gaming
environment on Apple Silicon macOS using this repo. It encodes the decision points
and invariants learned from a real end-to-end session.

## Prime directives (never violate)

1. **Never delete `steamapps/` or any `steamapps/common/<game>` folder.** Those are the
   user's (large) game installs. Cache dirs (`htmlcache`, `appcache/httpcache`, `dumps`)
   are fine to clear.
2. **Never redistribute Apple's D3DMetal.** Always obtain it on the user's machine via
   `scripts/fetch-d3dmetal.sh`. Do not commit or upload any Apple binary.
3. **Prefer native macOS ports over the Wine/D3DMetal route.** If a game has an Apple
   Silicon or 64-bit Metal native build, recommend that instead (`check-compat.sh`
   knows several). Native usually wins even through Rosetta 2.
4. **EA App games are a hard stop for the free route.** Jedi Survivor, NFS Heat, etc.
   require the EA App, which fails under free Wine (`INST-14-1627`). Only paid CrossOver
   works. Tell the user; do not burn time trying to fix it.
5. **Kernel anti-cheat = won't run.** VAC-heavy titles (CS2), EAC, BattlEye. Don't try.

## Standard workflow (default: native Steam + free NotProton)

```
1. gather state   -> bash scripts/doctor.sh                 (read-only)
2. install        -> ./install.sh                           (prereqs, Steam, Heroic, then step 3)
3. Steam stack    -> bash scripts/setup-notproton.sh        (idempotent; quits Steam first)
4. per game       -> bash scripts/check-compat.sh <appid>   BEFORE installing
5. Steam updated, games won't launch -> bash scripts/setup-notproton.sh --skip-build
```

Invariants for the NotProton route:
- **Steam must be quit** before editing `config.vdf` / `localconfig.vdf`; Steam rewrites them on exit.
- **Launch options go after `%command%`** (`%command% NOTPROTON_RETINA=0`). `VAR=1 %command%`
  fails on macOS Steam with `OS Error 260`.
- **Never replace `bridge/steamclient64.dll` with lsteamclient.** Steam DRM needs Valve's file;
  the ntdll detour does the rerouting. `.valve` copies sit beside them.
- **Don't run the old wrapper Steam alongside Mac Steam.** Launch games with
  `open -b com.valvesoftware.steam "steam://rungameid/<id>"` so the URL can't reach the wrapper.
- Steam's EULA / "Play" interstitial dialogs can be invisible to screenshots; ask the user to click.
- Logs: `steamapps/compatdata/<appid>/notproton-run.log`, `notproton/launchers/<appid>/notproton-wine.log`,
  `notproton/notproton.log`.

## Decision tree for "will this game work?"

```
has native macOS port? ──yes──> recommend NATIVE (stop)
        │no
EA-published? ──yes──> BLOCKED (free). Suggest CrossOver trial. (stop)
        │no
kernel anti-cheat (VAC/EAC/BattlEye)? ──yes──> BLOCKED. (stop)
        │no
DirectX 12? ──> use D3DMetal renderer
DirectX 10/11? ──> D3DMetal first; DXMT if glitchy; DXVK as fallback
        │
online-only? ──> warn: online often broken under Wine even if game runs
```

`scripts/check-compat.sh <appid>` returns: exit 0 works, 2 caveats, 3 blocked, 1 unknown.

## Legacy: Steam wrapper fixes (only for `install.sh --legacy-wrapper`; setup-steam.sh does it)

0. **Wrapper template** = latest (`scripts/update-wrapper.sh`). Wine 11 engines need template
   1.0.16+; on older templates they fail with `SikarugirSdk.FileUtilsError error 1`.
1. **Engine** = `WS12WineSikarugir11.0_1` (Wine 11). Fallback `WS12WineSikarugir10.0_8`.
   GPTk 1.1 (Wine 7) CANNOT run the modern Steam CEF webhelper — it stalls.
2. **Launch target** = `steam.exe`, not `SteamSetup.exe`. The wrapper's
   `drive_c/exec*.bat` files must contain `"C:\Program Files (x86)\Steam\steam.exe" -tcp`.
   Wrong target = it re-runs the installer forever.
3. **`-tcp` flag** fixes `Unexpected Transport Error (0x3008)`.
4. **D3DMetal** = templates bundle it (1.0.21 has 4.0b2). Only overlay
   `~/GPTk-D3DMetal/lib/external/` if it is NEWER (setup-steam.sh checks; never downgrade).
5. **Clear caches** (`config/htmlcache`, `appcache/httpcache`) before first launch.
6. First launch: webhelper rebuild ~30-40s. If `0x3008` dialog: choose "VO: Continue Anyway".

## Key paths, legacy wrapper (computed, never hardcode the username)

```
Wrapper:      ~/Applications/Sikarugir/<Name>.app
Wine engine:  <wrapper>/Contents/SharedSupport/wine            (file: version)
Drive C:      <wrapper>/Contents/SharedSupport/prefix/drive_c
Steam dir:    <drive_c>/Program Files (x86)/Steam
Launch bats:  <drive_c>/exec*.bat
D3DMetal:     <wrapper>/Contents/Frameworks/renderer/d3dmetal/external
DXMT:         <wrapper>/Contents/Frameworks/renderer/dxmt        (file: version)
Engine cache: ~/Library/Application Support/Sikarugir/Engines/*.tar.xz
Extracted D3DMetal: ~/GPTk-D3DMetal/lib/external
```

`scripts/lib.sh` exposes helpers: `find_wrapper`, `wrapper_wine_dir`, `wrapper_steamdir`,
`wrapper_d3dmetal_external`, `wrapper_dxmt_dir`, `kill_wine`, `gh_latest_tag`, `gh_asset_url`.

## Engine vs renderer (do not conflate)

- **Engine** (Wine): handles Windows/process/CEF. Sikarugir 11 > Sikarugir 10 > CX24 > GPTk 1.1
  for the Steam client. Swap with `scripts/swap-engine.sh` (auto-downloads engines).
- **Renderer** (graphics): D3DMetal / DXMT / DXVK. Chosen by a Configure checkbox,
  **independent** of the engine. DX12 → D3DMetal. DX10/11 → D3DMetal or DXMT.

## Updating

- NotProton stack: `scripts/setup-notproton.sh --skip-build` (new Steam signatures, re-staged bridge);
  `--force` rebuilds fork + runner. Bump pins (fork commit, engine, template, checksums) at the top of the script.

- Wrapper template: `scripts/update-wrapper.sh` (backs up, keeps SharedSupport).
- DXMT: `scripts/update-dxmt.sh` (latest release; leaves newer dev builds alone).
- D3DMetal: re-run `scripts/fetch-d3dmetal.sh` with a newer GPTk DMG, then re-overlay via
  `setup-steam.sh`.
- Launchers: `brew upgrade --cask heroic sikarugir` (Heroic also self-updates).

## NotProton (the default Steam route)

Free fork = Maxyme/NotProton `5b8d186` + `notproton/notproton-free.patch`, on Sikarugir Wine 11
with the ntdll detour from `notproton/ntdll-sikarugir11.json`. Details: docs/NOTPROTON.md.
Paths: runner `~/Library/Application Support/notproton/runners/sikarugir-11` (`current` symlink),
bridge `.../notproton/bridge`, build tree `~/Library/Caches/notproton-free/src` (no spaces: the
fork's Makefile can't handle them), Steam.app backup `.../notproton-free/backup-*/`.
Upstream NotProton (CrossOver-only): never strip its licence check while using CrossOver.

## What NOT to automate

- (Legacy route only) Sikarugir wrapper *creation* has no headless API: a GUI step.
- Logging into Steam/Epic/etc. — user credentials; never handle these.
