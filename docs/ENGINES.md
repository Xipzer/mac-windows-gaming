# Wine engines, wrapper templates & renderers

A Sikarugir wrapper is three separate layers. You can update each one on its own:

```
Wrapper template   launcher + libraries + bundled renderers   scripts/update-wrapper.sh
Wine engine        the Wine build that runs Windows programs  scripts/swap-engine.sh
Renderer           D3DMetal / DXMT / DXVK (Configure checkbox) per game
```

## Wine engines (Sikarugir)

| Engine | Wine | Use it for | Notes |
|---|---|---|---|
| **WS12WineSikarugir11.0_1** | **Wine 11** | ★ **Default.** Steam client and games | Needs wrapper template **1.0.16+** |
| WS12WineSikarugir10.0_8 | Wine 10 | Fallback if a game regresses on 11 | Works on older templates |
| WS12WineCX24.0.7_7 | Wine 9 | Older fallback | CrossOver 24's open-source Wine |
| WS12WineGPTK1.1_3 | Wine 7 | Avoid | Can't run the modern Steam webhelper (it stalls) |

The full list Sikarugir offers is at
https://raw.githubusercontent.com/Sikarugir-App/Engines/main/EngineList.txt.
`swap-engine.sh` downloads any engine from that list automatically.

```bash
bash scripts/swap-engine.sh WS12WineSikarugir11.0_1 Steam   # also updates the template if needed
bash scripts/swap-engine.sh WS12WineSikarugir10.0_8 Steam   # roll back to Wine 10
```

Each swap keeps the previous engine as `SharedSupport/wine.backup-<timestamp>`.

## Wrapper templates

The template is the wrapper's launcher plus its bundled libraries and renderers. Newer
templates matter for two reasons:

1. **Wine 11 engines need template 1.0.16 or newer.** On template 1.0.11, a Wine 11
   engine dies at launch with
   `ERROR: The operation couldn't be completed. (SikarugirSdk.FileUtilsError error 1.)`
2. **Newer templates bundle newer renderers.** Template 1.0.21 (1 Oct 2026) ships
   **D3DMetal 4.0b2** and DXMT **v0.80-244** (a development build newer than the v0.80
   release).

```bash
bash scripts/update-wrapper.sh Steam
```

This replaces `Contents/{MacOS,Frameworks,Resources,Configure.app}`, keeps
`SharedSupport` (engine, prefix, games) and your `Info.plist` settings, and backs up the
old parts to `~/Applications/Sikarugir/.Steam-wrapper-backup-<timestamp>/`. It's the same
as Configure → Tools → Update Wrapper.

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

### D3DMetal versions

- Recent templates already include D3DMetal (template 1.0.21 has **4.0b2**), so most
  people no longer need to download Apple's DMG.
- `fetch-d3dmetal.sh` is still there if you have a newer Apple build. `setup-steam.sh`
  only overlays your copy when it's **newer** than the wrapper's, so it never downgrades.

### DXMT versions

`update-dxmt.sh` installs the latest DXMT release, but it leaves newer development builds
(like `v0.80-244-g7c8dee1`) alone.

## Recommended config (October 2026)

```
Template:  1.0.21
Engine:    WS12WineSikarugir11.0_1   (Wine 11)
D3DMetal:  4.0b2   (bundled with the template)
DXMT:      v0.80-244 dev build (bundled), or v0.80 release
```

Tested on macOS 26.6.2, Apple M4 Max: Steam starts, the webhelper runs and the account logs in.
