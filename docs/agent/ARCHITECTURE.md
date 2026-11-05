# Architecture

How a Windows game starts from Mac Steam. Every fact here comes from the files named; read them before changing behavior.

## Paths

| Name | Path |
|---|---|
| `$SB` | `~/Library/Application Support/SteamBridge` |
| Steam data | `~/Library/Application Support/Steam` |
| Compat tool | `~/Library/Application Support/Steam/compatibilitytools.d/steambridge/` |
| Runner | `$SB/runners/sikarugir-11`, linked as `$SB/runners/current` |
| Bridge | `$SB/bridge` |
| Prefix | `steamapps/compatdata/<appid>/pfx` |
| Per-game launcher bundle | `$SB/launchers/<appid>/<Game name>.app` |
| Installer state, Steam.app backup | `$SB/setup/`, `$SB/setup/backup-<timestamp>/Steam.app` |
| Download cache | `~/Library/Caches/steambridge/downloads` |
| Build copy (repo path with spaces) | `~/Library/Caches/steambridge/build/src` |

## 1. Install (`scripts/setup.sh`)

In order:

1. Checks arm64 and macOS 14+. `--uninstall` stops here: restores the backed-up Steam.app (or removes the injection) and deletes the compat tool dir.
2. Migrates an older `notproton` install to the SteamBridge names (`--migrate` stops after this).
3. Rosetta 2, build tools, cmake. Quits Steam (`steam_osx`).
4. Build, unless `--skip-build`: clones Dobby at the pinned commit into `vendor/dobby`, `make dobby`, then `make all helpers-install sigdb-install`. Output `out/steambridge.dylib`; `iconmaker`, `appinfo` and `signatures/macos.arm64/*.json` go to `$SB`. Log: `$SB/setup/build.log`.
5. Builds `helpers/dispmode.c` to `$SB/dispmode` and `helpers/prio_shim.c` to `$SB/prio-shim.dylib`.
6. Downloads extra signature sets from the NotProton repo into `$SB/signatures/macos.arm64`.
7. Runner, only if missing or `--force`: Wine engine tarball plus the template's `Frameworks` (renderers, GStreamer, MoltenVK) and the Vulkan driver manifests in `Resources/vulkan` (their `library_path` of `../../../Frameworks` only resolves from there; an older runner's top-level `vulkan` dir is moved there on every run). Adds `Frameworks/renderer/d3dmetal-4.0b3` (template 1.0.24) and `Frameworks/renderer/dxmt-codegen` (`assets/renderers/dxmt-codegen.tar.xz`). Always copies `assets/runner.env` to `$RUNNER/runner.env`, and `assets/direct-shipping.sh` to `$SB`.
8. Bridge: unpacks the pinned NotProton release (`steam.exe`, lsteamclient DLLs and `.so`) into `$SB/bridge` and into the runner's `lib/wine/*`. Runs `bridge/fetch-valve.sh --install` to download Valve's Windows DLLs listed in `app/Sources/SteamBridgeApp/Resources/valve-packages.manifest`, then keeps `steamclient64.dll.valve` and `steamclient.dll.valve` copies.
9. ntdll, for `x86_64-windows` and `i386-windows`: saves `lib/wine/<arch>/ntdll.dll` as `ntdll.dll.steambridge-orig`, applies `assets/ntdll-sikarugir11.json` (64-bit) or `assets/ntdll-sikarugir11-i386.json` (32-bit) with `assets/apply-ntdll.py` (SHA-256 checked before and after; an unknown file stops setup), copies the result to `$SB/bridge/wine/<arch>/ntdll.dll`.
10. Steam.app: one-time backup, copies the dylib to `Contents/MacOS/steambridge.dylib`, sets `LSEnvironment:DYLD_INSERT_LIBRARIES` in `Contents/Info.plist`, ad-hoc re-signs, re-registers with LaunchServices.
11. Compat tool: writes `compatibilitytool.vdf` (name `steambridge`, windows to macos), `toolmanifest.vdf` (`/run %verb%`) and `run` (a copy of `dylib/feats/compat_run.sh`).
12. Unless `--no-default`: backs up `config/config.vdf` and sets `CompatToolMapping` entry `"0"` to `steambridge`, making it the default for all Windows games.
13. Self-test: `run getcompatpath` must echo `STEAM_COMPAT_DATA_PATH`.

`scripts/apply-game-configs.sh` then copies `configs/games/<appid>.env` to `compatdata/<appid>/steambridge.env` (old file kept as `.bak`) for games that have a compatdata dir, writes in-game resolution files, and copies the Sonic `dinput8.dll`.

## 2. Inside Steam (`dylib/`)

`dylib/core/loader.c`, constructor `sb_init`, runs only in `steam_osx`:

1. Opens `$SB/steambridge.log`.
2. Sets `STEAM_EXTRA_COMPAT_TOOLS_PATHS` to `compatibilitytools.d`.
3. `hooks/hook_spawn.c`: interposes `execve`/`posix_spawn` so child processes do not inherit `DYLD_INSERT_LIBRARIES` (except `steam_osx` and `Steam Helper`).
4. A thread waits for `steamclient.dylib`, loads the newest signature JSON from `$SB/signatures/macos.arm64` (or `$STEAMBRIDGE_SIG`), and resolves every signature. If any is missing it logs `installing nothing` and stops.
5. `feats/compat.c` rewrites the compat tool files. `run` is the copy of `compat_run.sh` embedded at build time (`dylib/embed_script.py` to `out/generated/compat_run.h`). So a changed `compat_run.sh` only sticks after a full rebuild and reinstall.
6. Installs hooks (`hooks/hook_compat.c`): `CCompatManager::Init`, `BIsCompatibilityToolEnabled`, `FindToolForTargetApp`, `InternalSpecifyCompatTool`, the OS-list gate, the resolver redirect, `CAppManager::TerminateProcessByPid`. Logs `install_thread: ready, N/M hooks installed`.
7. `steamui.dylib` hooks: `hook_webui.c` registers `CompatManager.*` service routes (`feats/compatsvc.c`), `hook_webpatch.c` patches Steam's UI JavaScript as it is read so the Compatibility options show, `hook_shortcut.c` lets Steam accept a Windows `.exe` where it expects a Mac `.app` for shortcuts, and `hook_icon.c` renders the exe's icon.

Signatures are per Steam build. A Steam update with no matching set means no hooks: `scripts/setup.sh --skip-build` fetches newer sets.

## 3. Game launch (`dylib/feats/compat_run.sh`)

Steam calls `compatibilitytools.d/steambridge/run <verb> <exe> [args]` with `STEAM_COMPAT_DATA_PATH`, `STEAM_COMPAT_INSTALL_PATH` and `STEAM_COMPAT_APP_ID` set.

Environment, in load order (first set wins unless noted):

1. Launch-option words after `%command%` that look like `NAME=value` with an allowed prefix (`STEAMBRIDGE_`, `WINE`, `D3DM_`, `DXMT_`, `DXVK_`, `MTL_`, `ROSETTA_`, `CX_GRAPHICS`) are exported and removed from the arguments.
2. `compatdata/<appid>/steambridge.env`: same prefixes, only names not already set, `#` lines skipped.
3. `STEAMBRIDGE_ARGS` is appended to the game arguments (verb `waitforexitandrun` only).
4. Run script defaults: `D3DM_ENABLE_METALFX=1`, `ROSETTA_ADVERTISE_AVX=1`, `STEAMBRIDGE_RENDERER=d3dmetal`; `CX_ROOT=$SB/runners/current`; Wine loader, server and DLL paths.
5. `$CX_ROOT/runner.env` (from `assets/runner.env`) is sourced. It sets library paths and `VK_DRIVER_FILES` (`Resources/vulkan/icd.d/kosmickrisp_mesa_icd.json`), picks the D3DMetal build from `STEAMBRIDGE_D3DMETAL`, and selects the renderer:
   - `dxmt`: `WINEDLLPATH_DXMT=Frameworks/renderer/${STEAMBRIDGE_DXMT:-dxmt}/wine`
   - `dxvk`: `WINEDLLPATH_DXVK=Frameworks/renderer/dxvk/wine`, `DXVK_ASYNC=1`
   - otherwise: `WINEDLLPATH_D3DMETAL` and `WINEDLLPATH_PREPEND` to the D3DMetal `wine` dir

   Then, in this order:
   - Direct3D 8 and 9, next to any renderer: `WINEDLLPATH_D9VK=Frameworks/renderer/d9vk/wine` when the `VK_DRIVER_FILES` manifest exists and `STEAMBRIDGE_D9VK` is not `0`. Without it Direct3D 8 and 9 use wined3d over OpenGL
   - DirectX redist: Steam's DirectX installscript never runs (`iscriptevaluator.exe` is skipped). Once per prefix, after Wine has built `syswow64`, unpacks the native DLLs from `*_d3dx9_*.cab` and `*_d3dcompiler_*.cab` in the game folder (depth 4) with `tar`: `_x86` cabs to `syswow64`, `_x64` cabs to `system32`. Replaces only Wine builtins or placeholders (kept as `*.steambridge-orig`), lists the DLLs in `compatdata/<appid>/steambridge-directx`, and prepends `<dll>=n,b` for each to `WINEDLLOVERRIDES`. A first launch without a prefix gets them on the next launch
   - Retina: if `STEAMBRIDGE_RETINA` is unset and the main screen's `backingScaleFactor` (`osascript -l JavaScript`) is 1, sets `STEAMBRIDGE_RETINA=0`. Wine applies one scale factor to every screen
6. `WINEMSYNC` defaults to 1, forced to 0 for 32-bit (PE32) exes. `MTL_HUD_ENABLED` may come from `compatdata/<appid>/steambridge-hud` (written by `scripts/launch-game.sh --hud`).
7. `WINEDLLOVERRIDES`: the script's Steam and D3DX overrides, then the user's value. `WINEDEBUG` defaults to `err+all,fixme-all`.

Then, with `WINEPREFIX=compatdata/<appid>/pfx`:

1. Refuses a prefix whose `ntdll.dll` machine type does not match the runner: logs it, shows a dialog (except for verb `run`), exits 1.
2. `wineserver -k`. If `STEAMBRIDGE_DESKTOP_MODE=WxH`: `$SB/dispmode set W H`, the previous mode saved to `$SB/desktop-home`. If `STEAMBRIDGE_PRIO=1`: starts wineserver with `$SB/prio-shim.dylib` injected.
3. Profile layout for cloud saves: creates `drive_c/users/steamuser`, merges the Mac-user profile into it, moves the original to `compatdata/<appid>/steambridge-profile-backup-<user>`, and links `users/<mac user>` to `steamuser`.
4. `wineboot --init`; registry: no crash dialogs, `RetinaMode` (from `STEAMBRIDGE_RETINA`, default 1 unless `runner.env` set 0), `steam://` handler.
5. Bridge staging: copies the bridge files (Valve `steamclient64.dll`, `steamclient.dll`, tier0/vstdlib, lsteamclient, `steam.exe`) into `pfx/drive_c/Program Files (x86)/Steam`, removes stale DLLs there, checks that the runner ntdll matches the bridge copy, installs lsteamclient triggers in `system32`/`syswow64`.
6. Targets outside the game folder (installers, redists) run directly on the Wine loader. `iscriptevaluator.exe` is skipped.
7. The game: builds `$SB/launchers/<appid>/<Game>.app` (name and icon from Steam's `appinfo.vdf` via `$SB/appinfo` and `$SB/iconmaker`). Its `launcher` script sets the library path, injects `$SB/overlay-shim.dylib` (if present) and Steam's overlay, logs to `steambridge-wine.log`, and runs `wine "C:\Program Files (x86)\Steam\steam.exe" <game exe> <args>`. The bundle is started with `open -n -W -a` and every relevant variable passed with `--env`. A bundle gives the game its own Dock icon and allows Game Mode.
8. On exit or signal: Game Mode back to auto, `wineserver -k` and `-w`, desktop mode restored, leftover prefix processes killed. Run log: `compatdata/<appid>/steambridge-run.log`.

## 4. Steam API bridge and the ntdll detour

- Games load `steamclient64.dll`. It must stay Valve's file: Steam DRM checks it (`3:0000065432` otherwise).
- The patched Wine `ntdll.dll` (source `ntdll-patch/`, applied from `assets/ntdll-sikarugir11.json`) hooks module loading. When `steamclient64.dll` loads, `detour_build_module` in `ntdll-patch/detour.c` points each of its exports and its entry point at the same export in lsteamclient, and skips its `DllMain`.
- 32-bit games get the same detour for `steamclient.dll` from `ntdll-patch/detour32.c`, applied from `assets/ntdll-sikarugir11-i386.json`. Wine 11's i386 `build_module` gates on `DONT_RESOLVE_DLL_REFERENCES` (`0x1`), so `build32.sh` builds with that bit when `resolve.py` reports `SB_GATE_BIT=0x1`. The payload does not fit in the `.text` padding, so `resolve.py` picks the largest read-only section tail (`.rsrc`) and `apply.py` marks it executable. `ntdll-patch/build-sikarugir11-i386.sh <clean i386 ntdll.dll>` rebuilds the JSON byte for byte (needs `brew install mingw-w64`; `mkpatch.py` writes the ranges).
- Wine 11 loads the 32-bit ntdll from the runner, not from a prefix's `syswow64`, so existing prefixes need no change.
- lsteamclient (`lsteamclient/`) is a Wine DLL with a Unix side that calls the native Mac Steam client. `steam.exe` (`steam-shim/`) is the small Windows Steam stand-in that starts the game.
- Sources for rebuilding the bridge: `make bridge` (needs a Wine source tree, see `bridge/setup-wine-tree.sh`). Normal installs use the pinned release instead.

## 5. Other parts

| Path | Role |
|---|---|
| `overlay-shim/` | Hooks Metal encoders, queues and drawables so the Steam overlay draws correctly on the game's swapchain format. Loaded into the game only if `$SB/overlay-shim.dylib` exists (`make overlay-shim-install`; `scripts/setup.sh` does not install it) |
| `helpers/dispmode.c` | `dispmode get`, `list`, `set PTW PTH [HZ]` |
| `helpers/prio_shim.c` | wineserver interposer for `thread_policy_set` (opt-in) |
| `helpers/appinfo.swift`, `helpers/iconmaker.swift` | Read game name and icon ids from `appinfo.vdf`; build `.icns` for launcher bundles |
| `helpers/icon.swift` | Draws the SteamBridge app icon (`make icon`) |
| `app/` | Optional SwiftUI manager (prefix rebuild, runner install, uninstall). `make app`. Not used by `scripts/setup.sh` |
| `games/sonicfrontiers/` | dinput8 proxy that removes Sonic Frontiers' fps cap |
| `patches/dxmt`, `patches/dxmt-codegen` | DXMT patches. Only the codegen build ships |
| `legacy/` | Old Windows-Steam-in-a-wrapper route |
