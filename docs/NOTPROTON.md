# NotProton, free (the default Steam route)

[NotProton](https://github.com/NotProtonNot/NotProton) (Sept 2026) turns on Steam Play inside
the **native macOS Steam client**, like Proton on Linux. Upstream only runs on paid CrossOver
Preview builds and the maintainer declined free-Wine support
([PR #18](https://github.com/NotProtonNot/NotProton/pull/18)). NotProton is GPL-3.0, so this
repo runs a **free fork** of it on Sikarugir's free Wine 11. `scripts/setup-notproton.sh`
builds and installs it.

```
Old route:  Mac -> Sikarugir wrapper -> Windows Steam client (CEF, -tcp, ...) -> game
This route: Mac -> native Mac Steam (+ notproton.dylib) -> Sikarugir Wine 11 + D3DMetal -> game
```

No Windows Steam client means none of its problems: no webhelper stalls, installer loop or
`0x3008`. Games, cloud saves, achievements and the overlay all go through the one Mac Steam.

## What gets installed

| Piece | Source | Where |
|---|---|---|
| `notproton.dylib` | [Maxyme/NotProton `standalone-steam-gptk4`](https://github.com/Maxyme/NotProton/tree/standalone-steam-gptk4) @ `5b8d186` + [`notproton/notproton-free.patch`](../notproton/notproton-free.patch) | injected into `/Applications/Steam.app` |
| Wine 11 runner | Sikarugir engine `WS12WineSikarugir11.0_1` + Template 1.0.21 `Frameworks` (D3DMetal 4.0b2, DXMT, MoltenVK, GStreamer) | `~/Library/Application Support/notproton/runners/sikarugir-11` |
| Runner environment | [`notproton/runner.env`](../notproton/runner.env) (mirrors Sikarugir's launcher) | `<runner>/runner.env` |
| Steam bridge | `lsteamclient` + `steam.exe` from the NotProton v1.0.1 release; Valve's `steamclient`/`tier0`/`vstdlib` from Valve's CDN (hash-checked) | `~/Library/Application Support/notproton/bridge` |
| ntdll detour | [`notproton/ntdll-sikarugir11.json`](../notproton/ntdll-sikarugir11.json) applied by `apply-ntdll.py` | runner + bridge `ntdll.dll` |
| Compat tool | "NotProton (free, Wine 11)", made the default for all Windows games | `~/Library/Application Support/Steam/compatibilitytools.d/notproton` |

Every download is pinned by SHA-256. Stock `Steam.app` is backed up to
`~/Library/Application Support/notproton-free/backup-*/` before the first patch.
Undo with `scripts/setup-notproton.sh --uninstall`.

## What the fork changes and why

All of these are in `notproton-free.patch` (applied to the fork's `dylib/feats/compat_run.sh`):

1. **Sources `runner.env`.** Sikarugir Wine needs the D3DMetal/DXMT/GStreamer paths its own
   launcher normally sets.
2. **Library path reaches the game.** macOS (SIP) strips `DYLD_*` variables whenever `/bin/sh`
   runs, so the per-game launcher script now has `DYLD_FALLBACK_LIBRARY_PATH` written into it.
   Without this, Wine can't find FreeType, GnuTLS or Vulkan. Symptom: a game's own Win32 dialog
   shows up **blank with no text** (Sonic Frontiers).
3. **Forwards Sikarugir's variables** (`CX_D3DMETAL*`, `WINEDLLPATH_*`, `VK_DRIVER_FILES`, ...)
   through `open`.
4. **`WINEMSYNC=0` by default.** msync hung Unreal games on this engine; esync stays on.
5. **Retina on by default** (`NOTPROTON_RETINA=1`). Otherwise games only see the scaled "looks
   like" size (e.g. 1800×1169) and can't pick the panel's real 3024×1964. Opt a game out with
   `%command% NOTPROTON_RETINA=0`.
6. **Keeps Valve's real `steamclient64.dll`** instead of replacing it with lsteamclient. Steam's
   DRM (SteamStub) checks that DLL. With lsteamclient in its place games failed with
   `Application load error 3:0000065432`.

### The ntdll detour

Games call Valve's `steamclient64.dll`, but it has to talk to the Mac Steam client through
`lsteamclient`. Upstream does this with a small detour in Wine's `build_module`: when Wine loads
`steamclient64.dll`, it loads `lsteamclient` too. Upstream only ships it for exact CrossOver
builds. We built it for Sikarugir Wine 11's `ntdll.dll` with upstream's
`ntdll-patch/resolve.py`, which needed `NP_FORCE_LOAD_PATH=0x58` because that build keeps
`load_path` at `rsp+0x58`. The result is 4 byte ranges (870 bytes), stored as JSON:
hook at `0x34fc2`, payload at RVA `0x704a0`. `apply-ntdll.py` refuses any `ntdll.dll` whose
hash doesn't match, so it can never patch a different engine by mistake.

## Per-game launch options

Options go **after** `%command%`. macOS Steam can't take `VAR=1 %command%`; that fails with
`OS Error 260`.

| Option | Effect |
|---|---|
| `%command% NOTPROTON_RETINA=0` | Disable Retina for this game (e.g. a tiny windowed launcher) |
| `%command% WINEMSYNC=1` | Try msync |
| `%command% MTL_HUD_ENABLED=1` | Metal performance HUD |
| `"<repo>/notproton/direct-shipping.sh" %command%` | Dragon Ball Sparking! ZERO: skip the UE launcher stub that spins at 200% CPU |

## Tested (M4 Max, macOS 26.6.2, Oct 2026)

| Game | Result |
|---|---|
| Batman: Arkham Knight | High, AA on: 1800×1169 avg 91–93 fps; native 3024×1964 avg 65; 3600×2338 avg 51 |
| LEGO Star Wars: The Skywalker Saga | Plays |
| Sonic Frontiers | Plays (needed fix 2 above) |
| Dragon Ball Sparking! ZERO | Title screen; use `direct-shipping.sh` |

## Limits

- **Steam client updates can break it.** The dylib matches Steam builds by signature. If games
  stop launching after a Steam update, re-run `scripts/setup-notproton.sh --skip-build`. That
  pulls the newest signatures from upstream. Steam → Settings → "Block Steam client updates"
  avoids surprises.
- **32-bit games:** untested. The i386 `ntdll.dll` isn't patched (`resolve.py` finds no gate).
- **Kernel anti-cheat** (CS2 VAC, EAC, BattlEye) and **EA App** games still don't work.
- First launch of a game builds its prefix (~30 s). Steam's EULA and "Play" dialogs can be
  hidden behind other windows; click Steam if a launch seems stuck.

## Logs

```
~/Library/Application Support/Steam/steamapps/compatdata/<appid>/notproton-run.log   run script
~/Library/Application Support/notproton/launchers/<appid>/notproton-wine.log         game's Wine output
~/Library/Application Support/notproton/notproton.log                                dylib (Steam side)
```
