# NotProton, free (default Steam route)

[NotProton](https://github.com/NotProtonNot/NotProton) (Sept 2026) turns on Steam Play inside **native macOS Steam**, like Proton on Linux.

- Upstream only runs on paid CrossOver Preview builds; the maintainer declined free-Wine support ([PR #18](https://github.com/NotProtonNot/NotProton/pull/18)).
- NotProton is GPL-3.0, so this repo runs a **free fork** on Sikarugir's free Wine 11, built and installed by `scripts/setup-notproton.sh`.

```
Old route:  Mac -> Sikarugir wrapper -> Windows Steam client (CEF, -tcp, ...) -> game
This route: Mac -> native Mac Steam (+ notproton.dylib) -> Sikarugir Wine 11 + D3DMetal -> game
```

No Windows Steam client, so no webhelper stalls, installer loop or `0x3008`. Games, cloud saves,
achievements and the overlay all go through the one Mac Steam.

## What gets installed

| Piece | Source | Where |
|---|---|---|
| `notproton.dylib` | [Maxyme/NotProton `standalone-steam-gptk4`](https://github.com/Maxyme/NotProton/tree/standalone-steam-gptk4) @ `5b8d186` + [`notproton/notproton-free.patch`](../notproton/notproton-free.patch) | injected into `/Applications/Steam.app` |
| Wine 11 runner | Sikarugir engine `WS12WineSikarugir11.0_1` + Template 1.0.21 `Frameworks` (D3DMetal 4.0b2, DXMT, MoltenVK, GStreamer) | `~/Library/Application Support/notproton/runners/sikarugir-11` |
| Runner environment | [`notproton/runner.env`](../notproton/runner.env) (mirrors Sikarugir's launcher) | `<runner>/runner.env` |
| Steam bridge | `lsteamclient` + `steam.exe` from the NotProton v1.0.1 release; Valve's `steamclient`/`tier0`/`vstdlib` from Valve's CDN (hash-checked) | `~/Library/Application Support/notproton/bridge` |
| ntdll detour | [`notproton/ntdll-sikarugir11.json`](../notproton/ntdll-sikarugir11.json) applied by `apply-ntdll.py` | runner + bridge `ntdll.dll` |
| Compat tool | "NotProton (free, Wine 11)", default for all Windows games | `~/Library/Application Support/Steam/compatibilitytools.d/notproton` |

- Every download is pinned by SHA-256.
- Stock `Steam.app` is backed up to `~/Library/Application Support/notproton-free/backup-*/` before the first patch.
- Undo: `scripts/setup-notproton.sh --uninstall`.

## What the fork changes

All in `notproton-free.patch`, applied to the fork's `dylib/feats/compat_run.sh`:

| # | Change | Why |
|---|---|---|
| 1 | Sources `runner.env` | Sikarugir Wine needs the D3DMetal/DXMT/GStreamer paths its own launcher normally sets |
| 2 | Writes `DYLD_FALLBACK_LIBRARY_PATH` into the per-game launcher script | macOS (SIP) strips `DYLD_*` whenever `/bin/sh` runs, so Wine can't find FreeType, GnuTLS or Vulkan. Symptom: a game's own Win32 dialog is **blank with no text** (Sonic Frontiers) |
| 3 | Forwards Sikarugir's variables (`CX_D3DMETAL*`, `WINEDLLPATH_*`, `VK_DRIVER_FILES`, ...) through `open` | - |
| 4 | `WINEMSYNC=0` by default | msync hung Unreal games on this engine; esync stays on |
| 5 | Retina on by default (`NOTPROTON_RETINA=1`) | Otherwise games only see the scaled "looks like" size (e.g. 1800×1169), not the panel's real 3024×1964 |
| 6 | Keeps Valve's real `steamclient64.dll` instead of lsteamclient | Steam DRM (SteamStub) checks that DLL; replacing it gave `Application load error 3:0000065432` |

### The ntdll detour

- **Problem:** games call Valve's `steamclient64.dll`, which must reach Mac Steam through `lsteamclient`.
- **Upstream fix:** a detour in Wine's `build_module` loads `lsteamclient` whenever `steamclient64.dll` loads. Shipped only for exact CrossOver builds.
- **Ours:** built for Sikarugir Wine 11's `ntdll.dll` with upstream's `ntdll-patch/resolve.py`, using `NP_FORCE_LOAD_PATH=0x58` (that build keeps `load_path` at `rsp+0x58`).
- **Result:** 4 byte ranges (870 bytes) stored as JSON; hook at `0x34fc2`, payload at RVA `0x704a0`.
- **Safety:** `apply-ntdll.py` refuses any `ntdll.dll` whose hash doesn't match, so it can't patch a different engine.

## DirectX redistributables

Steam's DirectX install step never runs under NotProton. Scribblenauts Unlimited crashes on Wine's own `d3dx9` effects and plays with the real DLLs.

- On launch, `runner.env` unpacks the native `d3dx9_*` and `d3dcompiler_*` DLLs from the game's own redist `.cab` files into its prefix, and prefers them (`n,b`).
- Only Wine's built-in copies are replaced; the originals stay beside them as `*.notproton-orig`.
- It runs once per prefix and records the DLLs in `compatdata/<appid>/notproton-directx`. Delete that file to redo it.
- The prefix has to exist first, so a game without a Steam install script gets them on its second launch.

## Per-game launch options

Options go **after** `%command%`. `VAR=1 %command%` fails on macOS Steam with `OS Error 260`.

| Option | Effect |
|---|---|
| `%command% NOTPROTON_RETINA=0` | Disable Retina for this game (e.g. a tiny windowed launcher) |
| `%command% NOTPROTON_RETINA=1` | Force Retina when the main screen is 1x (it is off there by default) |
| `%command% WINEMSYNC=1` | Try msync |
| `%command% MTL_HUD_ENABLED=1` | Metal performance HUD |
| `%command% NOTPROTON_MIN_FREE_GB=5` | Warn before launch below 5 GB free instead of 10; `0` turns the warning off |
| `"<repo>/notproton/direct-shipping.sh" %command%` | Dragon Ball Sparking! ZERO: skip the UE launcher stub that spins at 200% CPU |

Tested results (M4 Max, macOS 26.6.2, Oct 2026): [BENCHMARKS.md](BENCHMARKS.md).

## Limits

- **Steam client updates can break it.** The dylib matches Steam builds by signature. Re-run `scripts/setup-notproton.sh --skip-build` to pull the newest signatures. Steam → Settings → "Block Steam client updates" avoids surprises.
- **32-bit games:** untested. The i386 `ntdll.dll` isn't patched (`resolve.py` finds no gate).
- **Kernel anti-cheat and EA App games** still don't work ([COMPATIBILITY.md](COMPATIBILITY.md)).
- First launch of a game builds its prefix (~30 s). Steam's EULA and "Play" dialogs can hide behind other windows; click Steam if a launch seems stuck.

## Logs

```
~/Library/Application Support/Steam/steamapps/compatdata/<appid>/notproton-run.log   run script
~/Library/Application Support/notproton/launchers/<appid>/notproton-wine.log         game's Wine output
~/Library/Application Support/notproton/notproton.log                                dylib (Steam side)
```
