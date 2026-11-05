# Legacy: Windows Steam in a Sikarugir wrapper

Superseded by SteamBridge (native Mac Steam). Kept as a fallback for a game that fails under SteamBridge.

- Runs the Windows Steam client inside a Sikarugir wrapper app (`~/Applications/Sikarugir/Steam.app`).
- Separate Steam install, separate game files. Native ports stay in Mac Steam.
- Needs 2 GUI clicks once: Sikarugir Creator has no headless wrapper-create API.
- Don't run the wrapper Steam and Mac Steam at the same time. Launch Mac Steam games with
  `open -b com.valvesoftware.steam "steam://rungameid/<id>"` so the URL can't reach the wrapper.

## Scripts

| Script | Purpose |
|---|---|
| `setup-steam.sh` | Create/repair the wrapper: latest template, Wine 11 engine, `steam.exe -tcp` launch target, D3DMetal overlay, cache clear |
| `swap-engine.sh <Engine> [Wrapper]` | Change the wrapper's Wine engine (downloads it, keeps `wine.backup-<ts>`) |
| `update-wrapper.sh [Wrapper]` | Update the wrapper template (keeps `SharedSupport`, backs up the rest) |
| `update-dxmt.sh [Wrapper]` | Latest DXMT release; leaves newer dev builds alone |
| `fetch-d3dmetal.sh [dmg]` | Extract D3DMetal from a GPTk DMG or the gcenx/wine formula into `~/GPTk-D3DMetal` |
| `lib.sh` | Wrapper paths and helpers; sources `../scripts/lib.sh` |

Run from anywhere: `bash legacy/setup-steam.sh`. Prereqs: `brew install --cask sikarugir` (tap `Sikarugir-App/sikarugir`).

## Fixes `setup-steam.sh` applies

| # | Fix | Why |
|---|---|---|
| 0 | Latest wrapper template | Wine 11 engines need template 1.0.16+; older fails with `SikarugirSdk.FileUtilsError error 1` |
| 1 | Engine `WS12WineSikarugir11.0_1` (fallback `WS12WineSikarugir10.0_8`) | GPTk 1.1 (Wine 7) can't run the modern Steam CEF webhelper; it stalls |
| 2 | `drive_c/exec*.bat` = `"C:\Program Files (x86)\Steam\steam.exe" -tcp` | Pointing at `SteamSetup.exe` re-runs the installer forever |
| 3 | `-tcp` | Fixes `Unexpected Transport Error (0x3008)` |
| 4 | Overlay `~/GPTk-D3DMetal/lib/external/` only if newer than the bundled D3DMetal | Never downgrade |
| 5 | Clear `config/htmlcache`, `appcache/httpcache` | Clean first start |

First launch: webhelper rebuild takes 30-40 s. On a `0x3008` dialog pick "VO: Continue Anyway" once.

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

Engines, templates and renderers: [../docs/ENGINES.md](../docs/ENGINES.md). Fixes: [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md#legacy-wrapper-route).
