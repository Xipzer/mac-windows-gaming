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

## Standard workflow

```
1. gather state   -> bash scripts/doctor.sh          (read-only; parse output)
2. prerequisites  -> install.sh handles Rosetta/brew/casks (idempotent)
3. D3DMetal       -> bash scripts/fetch-d3dmetal.sh  (needs GPTK_DMG or brew fallback)
4. Steam wrapper  -> bash scripts/setup-steam.sh     (may require 1 GUI step, then re-run)
5. per game       -> bash scripts/check-compat.sh <appid>   BEFORE installing
```

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

## The Steam wrapper fixes (apply in this order; setup-steam.sh does it)

1. **Engine** = `WS12WineSikarugir10.0_6` (Wine 10). GPTk 1.1 (Wine 7) CANNOT run the
   modern Steam CEF webhelper — it stalls ("BMainLoop appears to have stalled").
2. **Launch target** = `steam.exe`, not `SteamSetup.exe`. The wrapper's
   `drive_c/exec*.bat` files must contain `"C:\Program Files (x86)\Steam\steam.exe" -tcp`.
   Wrong target = it re-runs the installer forever.
3. **`-tcp` flag** fixes `Unexpected Transport Error (0x3008)`.
4. **D3DMetal overlay** = copy `~/GPTk-D3DMetal/lib/external/` into
   `<wrapper>/Contents/Frameworks/renderer/d3dmetal/external/`.
5. **Clear caches** (`config/htmlcache`, `appcache/httpcache`) before first launch.
6. First launch: webhelper rebuild ~30-40s. If `0x3008` dialog: choose "VO: Continue Anyway".

## Key paths (computed, never hardcode the username)

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

- **Engine** (Wine): handles Windows/process/CEF. Sikarugir 10 > CX24 > GPTk 1.1 for the
  Steam client. Swap with `scripts/swap-engine.sh`.
- **Renderer** (graphics): D3DMetal / DXMT / DXVK. Chosen by a Configure checkbox,
  **independent** of the engine. DX12 → D3DMetal. DX10/11 → D3DMetal or DXMT.

## Updating

- DXMT: `scripts/update-dxmt.sh` (pulls latest builtin from 3Shain/dxmt).
- D3DMetal: re-run `scripts/fetch-d3dmetal.sh` with a newer GPTk DMG, then re-overlay via
  `setup-steam.sh`.
- Launchers: `brew upgrade --cask heroic sikarugir` (Heroic also self-updates).

## What NOT to automate

- Sikarugir wrapper *creation* (no headless API) — must be a GUI step. Detect its absence
  and instruct the user with exact clicks, then continue automatically.
- Logging into Steam/Epic/etc. — user credentials; never handle these.
