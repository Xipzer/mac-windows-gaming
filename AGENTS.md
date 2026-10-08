# AGENTS.md - driving this repo as an AI agent

How to set up or repair free Windows gaming on Apple Silicon macOS with this repo.

## Prime directives

1. **Never delete `steamapps/` or any `steamapps/common/<game>`.** Those are the user's game installs. Cache dirs (`htmlcache`, `appcache/httpcache`, `dumps`) are fine to clear.
2. **Never redistribute Apple's D3DMetal.** Obtain it on the user's machine (legacy route: `scripts/fetch-d3dmetal.sh`). Never commit or upload any Apple binary.
3. **Prefer native macOS ports.** Apple Silicon or 64-bit Metal builds usually win, even through Rosetta 2 (`check-compat.sh` knows several).
4. **EA App games are a hard stop.** Jedi Survivor, NFS Heat, etc. fail under free Wine (`INST-14-1627`). Only paid CrossOver works. Tell the user; don't try to fix it.
5. **Kernel anti-cheat won't run.** VAC-heavy titles (CS2), EAC, BattlEye. Don't try.

## Workflow (default: native Steam + free NotProton)

```
1. gather state   -> bash scripts/doctor.sh                 (read-only)
2. install        -> ./install.sh                           (prereqs, Steam, Heroic, then step 3)
3. Steam stack    -> bash scripts/setup-notproton.sh        (idempotent; quits Steam first)
4. per game       -> bash scripts/check-compat.sh <appid>   BEFORE installing
5. Steam updated, games won't launch -> bash scripts/setup-notproton.sh --skip-build
```

## NotProton invariants

- **Quit Steam** before editing `config.vdf` / `localconfig.vdf`; Steam rewrites them on exit.
- **Launch options go after `%command%`** (`%command% NOTPROTON_RETINA=0`). `VAR=1 %command%` fails with `OS Error 260`.
- **Never replace `bridge/steamclient64.dll` with lsteamclient.** Steam DRM needs Valve's file; the ntdll detour does the rerouting. `.valve` copies sit beside them.
- **Don't run the old wrapper Steam alongside Mac Steam.** Launch with `open -b com.valvesoftware.steam "steam://rungameid/<id>"` so the URL can't reach the wrapper.
- Steam's EULA / "Play" dialogs can be invisible to screenshots; ask the user to click.
- Upstream NotProton (CrossOver-only): never strip its licence check while using CrossOver.

## NotProton paths

| What | Path |
|---|---|
| Fork | Maxyme/NotProton `5b8d186` + `notproton/notproton-free.patch` ([docs/NOTPROTON.md](docs/NOTPROTON.md)) |
| ntdll detour | `notproton/ntdll-sikarugir11.json` |
| Runner | `~/Library/Application Support/notproton/runners/sikarugir-11` (`current` symlink) |
| Bridge | `~/Library/Application Support/notproton/bridge` |
| Build tree | `~/Library/Caches/notproton-free/src` (no spaces: the fork's Makefile can't handle them) |
| Steam.app backup | `~/Library/Application Support/notproton-free/backup-*/` |
| Logs | `steamapps/compatdata/<appid>/notproton-run.log`, `notproton/launchers/<appid>/notproton-wine.log`, `notproton/notproton.log` |

## Will this game work?

Run `scripts/check-compat.sh <appid>` (exit 0 works, 2 caveats, 3 blocked, 1 unknown).
Decision tree and verified games: [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## Updating

- NotProton stack: `scripts/setup-notproton.sh --skip-build` (new Steam signatures, re-staged bridge); `--force` rebuilds fork + runner. Pins (fork commit, engine, template, checksums) are at the top of the script.
- Launchers: `brew upgrade --cask heroic sikarugir` (Heroic also self-updates).

## Do not automate

- Logging into Steam/Epic/etc. User credentials; never handle them.
- (Legacy) Sikarugir wrapper *creation*: no headless API, it's a GUI step.

## Legacy: Windows Steam wrapper (`install.sh --legacy-wrapper`)

`setup-steam.sh` applies these fixes:

| # | Fix | Why |
|---|---|---|
| 0 | Latest wrapper template (`scripts/update-wrapper.sh`) | Wine 11 engines need template 1.0.16+; older fails with `SikarugirSdk.FileUtilsError error 1` |
| 1 | Engine `WS12WineSikarugir11.0_1` (Wine 11), fallback `WS12WineSikarugir10.0_8` | GPTk 1.1 (Wine 7) CANNOT run the modern Steam CEF webhelper; it stalls |
| 2 | Launch target `steam.exe`, not `SteamSetup.exe`: `drive_c/exec*.bat` must contain `"C:\Program Files (x86)\Steam\steam.exe" -tcp` | Wrong target re-runs the installer forever |
| 3 | `-tcp` flag | Fixes `Unexpected Transport Error (0x3008)` |
| 4 | D3DMetal: templates bundle it (1.0.21 has 4.0b2); overlay `~/GPTk-D3DMetal/lib/external/` only if NEWER | Never downgrade (setup-steam.sh checks) |
| 5 | Clear `config/htmlcache`, `appcache/httpcache` before first launch | |
| 6 | First launch: webhelper rebuild ~30-40s; on `0x3008` dialog choose "VO: Continue Anyway" | |

Paths (computed, never hardcode the username):

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

`scripts/lib.sh` helpers: `find_wrapper`, `wrapper_wine_dir`, `wrapper_steamdir`, `wrapper_d3dmetal_external`, `wrapper_dxmt_dir`, `kill_wine`, `gh_latest_tag`, `gh_asset_url`.

Engine vs renderer (don't conflate):
- **Engine** (Wine): Windows/process/CEF. For the Steam client: Sikarugir 11 > Sikarugir 10 > CX24 > GPTk 1.1. Swap with `scripts/swap-engine.sh` (auto-downloads engines).
- **Renderer**: D3DMetal / DXMT / DXVK, a Configure checkbox, **independent** of the engine. DX12 → D3DMetal. DX10/11 → D3DMetal or DXMT.

Updating:
- Template: `scripts/update-wrapper.sh` (backs up, keeps SharedSupport).
- DXMT: `scripts/update-dxmt.sh` (latest release; leaves newer dev builds alone).
- D3DMetal: re-run `scripts/fetch-d3dmetal.sh` with a newer GPTk DMG, then re-overlay via `setup-steam.sh`.
