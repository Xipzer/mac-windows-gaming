# Engines, templates and renderers

## Default route: NotProton runner

`scripts/setup-notproton.sh` builds one runner from pinned Sikarugir parts. No wrapper, nothing to pick.

| Layer | Version | Source |
|---|---|---|
| Wine engine | `WS12WineSikarugir11.0_1` (Wine 11) | Sikarugir engines |
| Libraries + renderers | Template 1.0.21 `Frameworks`: D3DMetal 4.0b2, DXMT v0.80-244, MoltenVK, GStreamer | Sikarugir wrapper template |

Installed at `~/Library/Application Support/notproton/runners/sikarugir-11`. Details: [NOTPROTON.md](NOTPROTON.md).

## Renderers

| Renderer | Translates | Notes |
|---|---|---|
| **D3DMetal** (Apple GPTk) | DirectX 11 & 12 → Metal | Best for DX12. MetalFX upscaling. Apple Silicon only. |
| **DXMT** (3Shain) | DirectX 10 & 11 → Metal | Best open-source option for DX10/11 |
| **DXVK** | DirectX 10/11 → Vulkan (MoltenVK) | Fallback |

```
DirectX 12    -> D3DMetal
DirectX 11    -> D3DMetal (try DXMT if glitchy)
DirectX 10/9  -> DXMT or DXVK
```

## Legacy: Sikarugir Windows-Steam wrapper

Only for `install.sh --legacy-wrapper`. A wrapper has three layers, each updated separately:

```
Wrapper template   launcher + libraries + bundled renderers   scripts/update-wrapper.sh
Wine engine        the Wine build that runs Windows programs  scripts/swap-engine.sh
Renderer           D3DMetal / DXMT / DXVK (Configure checkbox) per game
```

### Recommended wrapper config (October 2026)

```
Template:  1.0.21
Engine:    WS12WineSikarugir11.0_1   (Wine 11)
D3DMetal:  4.0b2   (bundled with the template)
DXMT:      v0.80-244 dev build (bundled), or v0.80 release
```

Tested on macOS 26.6.2, Apple M4 Max: Steam starts, the webhelper runs and the account logs in.

### Engines

| Engine | Wine | Use | Notes |
|---|---|---|---|
| **WS12WineSikarugir11.0_1** | **Wine 11** | ★ **Default.** Steam client and games | Needs template **1.0.16+** |
| WS12WineSikarugir10.0_8 | Wine 10 | Fallback if a game regresses on 11 | Works on older templates |
| WS12WineCX24.0.7_7 | Wine 9 | Older fallback | CrossOver 24's open-source Wine |
| WS12WineGPTK1.1_3 | Wine 7 | Avoid | Can't run the modern Steam webhelper (it stalls) |

Full list: https://raw.githubusercontent.com/Sikarugir-App/Engines/main/EngineList.txt. `swap-engine.sh` downloads any engine from it.

```bash
bash scripts/swap-engine.sh WS12WineSikarugir11.0_1 Steam   # also updates the template if needed
bash scripts/swap-engine.sh WS12WineSikarugir10.0_8 Steam   # roll back to Wine 10
```

Each swap keeps the previous engine as `SharedSupport/wine.backup-<timestamp>`.

### Templates

- **Wine 11 engines need template 1.0.16+.** On 1.0.11 they die at launch with `ERROR: The operation couldn't be completed. (SikarugirSdk.FileUtilsError error 1.)`
- **Newer templates bundle newer renderers.** 1.0.21 (1 Oct 2026) ships D3DMetal 4.0b2 and DXMT v0.80-244 (a dev build newer than the v0.80 release).

```bash
bash scripts/update-wrapper.sh Steam
```

- Replaces `Contents/{MacOS,Frameworks,Resources,Configure.app}`.
- Keeps `SharedSupport` (engine, prefix, games) and your `Info.plist` settings.
- Backs up old parts to `~/Applications/Sikarugir/.Steam-wrapper-backup-<timestamp>/`.
- Same as Configure → Tools → Update Wrapper.

### Renderer updates

- **D3DMetal:** bundled in recent templates, so Apple's DMG is rarely needed. `fetch-d3dmetal.sh` is for a newer Apple build; `setup-steam.sh` only overlays it if **newer** than the wrapper's (never downgrades).
- **DXMT:** `update-dxmt.sh` installs the latest release but leaves newer dev builds (like `v0.80-244-g7c8dee1`) alone.
