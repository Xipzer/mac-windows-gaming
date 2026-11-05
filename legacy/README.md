# Legacy: Windows Steam in a Sikarugir wrapper

Replaced by SteamBridge. Kept as a fallback for a game that fails under SteamBridge.

- Runs the Windows Steam client inside a Sikarugir wrapper app (`~/Applications/Sikarugir/Steam.app`): a separate Steam install with separate game files.
- Creating the wrapper needs two clicks in Sikarugir Creator (it has no headless create).
- Do not run the wrapper Steam and Mac Steam at the same time. Launch Mac Steam games with `open -b com.valvesoftware.steam "steam://rungameid/<id>"` so the URL cannot reach the wrapper.
- Install: `./install.sh --legacy-wrapper`, or `brew install --cask sikarugir` (tap `Sikarugir-App/sikarugir`) and then `bash legacy/setup-steam.sh`.

## Scripts

| Script | Purpose |
|---|---|
| `setup-steam.sh` | Create or repair the wrapper: latest template, Wine 11 engine, `steam.exe -tcp` launch target, D3DMetal overlay, cache clear |
| `swap-engine.sh <Engine> [Wrapper]` | Change the wrapper's Wine engine. Keeps the old one as `SharedSupport/wine.backup-<ts>` |
| `update-wrapper.sh [Wrapper]` | Update the template. Keeps `SharedSupport` and `Info.plist` settings, backs up the rest to `~/Applications/Sikarugir/.<Name>-wrapper-backup-<ts>/` |
| `update-dxmt.sh [Wrapper]` | Install the latest DXMT release; leaves newer dev builds alone |
| `fetch-d3dmetal.sh [dmg]` | Extract D3DMetal from a GPTk DMG or the gcenx/wine formula into `~/GPTk-D3DMetal` |
| `lib.sh` | Wrapper paths and helpers; sources `../scripts/lib.sh` |

## What `setup-steam.sh` fixes

| Fix | Why |
|---|---|
| Latest wrapper template | Wine 11 engines need template 1.0.16 or newer; older fails with `SikarugirSdk.FileUtilsError error 1` |
| Engine `WS12WineSikarugir11.0_1` (fallback `WS12WineSikarugir10.0_8`) | GPTk 1.1 (Wine 7) cannot run Steam's web UI; it stalls |
| `drive_c/exec*.bat` runs `"C:\Program Files (x86)\Steam\steam.exe" -tcp` | Pointing at `SteamSetup.exe` re-runs the installer forever. `-tcp` fixes `Unexpected Transport Error (0x3008)` |
| D3DMetal from `~/GPTk-D3DMetal/lib/external/` only if newer than the bundled one | Never downgrade |
| Clear `config/htmlcache`, `appcache/httpcache` | Clean first start |

First launch: the web UI takes 30-40 s to rebuild. On a `0x3008` dialog choose "VO: Continue Anyway" once.

## Wrapper layers

| Layer | Update with |
|---|---|
| Template (launcher, libraries, bundled renderers) | `update-wrapper.sh` |
| Wine engine | `swap-engine.sh` |
| Renderer (D3DMetal, DXMT, DXVK) | Configure checkbox, per game |

Recommended (Oct 2026): template 1.0.21, engine `WS12WineSikarugir11.0_1`, D3DMetal 4.0b2 (bundled), DXMT v0.80-244 (bundled).

| Engine | Wine | Use |
|---|---|---|
| `WS12WineSikarugir11.0_1` | 11 | Default. Needs template 1.0.16+ |
| `WS12WineSikarugir10.0_8` | 10 | Fallback if a game regresses on 11 |
| `WS12WineCX24.0.7_7` | 9 | Older fallback (CrossOver 24 source) |
| `WS12WineGPTK1.1_3` | 7 | Avoid: Steam's web UI stalls |

`swap-engine.sh` accepts any engine in the Sikarugir engine list (`SIKARUGIR_ENGINE_LIST` in `lib.sh`):

```sh
bash legacy/swap-engine.sh WS12WineSikarugir11.0_1 Steam
bash legacy/swap-engine.sh WS12WineSikarugir10.0_8 Steam
```

## Paths

```
Wrapper:      ~/Applications/Sikarugir/<Name>.app
Wine engine:  <wrapper>/Contents/SharedSupport/wine            (file: version)
Drive C:      <wrapper>/Contents/SharedSupport/prefix/drive_c
Steam dir:    <drive_c>/Program Files (x86)/Steam
D3DMetal:     <wrapper>/Contents/Frameworks/renderer/d3dmetal/external
DXMT:         <wrapper>/Contents/Frameworks/renderer/dxmt      (file: version)
Engine cache: ~/Library/Application Support/Sikarugir/Engines/*.tar.xz
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Wrapper keeps re-running the Steam installer | Launch target is `SteamSetup.exe` | `bash legacy/setup-steam.sh` |
| `Failed to load steamui.dll` | Self-update blocked (`steam.cfg` with `BootStrapperInhibitAll=enable`) or mismatched client files | `rm -f "<SteamDir>/steam.cfg"`, delete stale client files (keep `steamapps` and `userdata`), relaunch |
| `steamwebhelper is not responding` or `BMainLoop appears to have stalled` | Old Wine cannot run Steam's web UI | `bash legacy/swap-engine.sh WS12WineSikarugir11.0_1 Steam`, then clear `config/htmlcache` and `appcache/httpcache` |
| `SikarugirSdk.FileUtilsError error 1` after an engine swap | Template too old | `bash legacy/update-wrapper.sh Steam` |
| `Unexpected Transport Error (0x3008)` | IPC handshake fails under Wine | `-tcp` (added by `setup-steam.sh`), clear `appcache`, choose "VO: Continue Anyway" once |
| `steam.exe` runs, no login screen | Web helper did not start | Wait 30-40 s on first run; `pgrep -fl steamwebhelper`; otherwise swap the engine |
| Pixelated, not Retina | Retina off in the prefix | `reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /d 'Y'` |
| Steam shows about 200 GB under NON-STEAM | Wine's `C:` maps the whole Mac disk | Nothing to clean |
| Steam and macOS Storage disagree | Lazy caches, or a ghost appmanifest | Trust `diskutil info /`. Uninstall the ghost game in Steam |

Undo an engine swap:

```sh
rm -rf "<wrapper>/Contents/SharedSupport/wine"
mv "<wrapper>/Contents/SharedSupport/wine.backup-<ts>" "<wrapper>/Contents/SharedSupport/wine"
```
