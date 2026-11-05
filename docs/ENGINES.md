# Engines, templates and renderers

## SteamBridge runner

`scripts/setup.sh` assembles one runner from pinned, checksummed Sikarugir parts. Nothing to pick.

| Layer | Version | Source |
|---|---|---|
| Wine engine | `WS12WineSikarugir11.0_1` (Wine 11) | Sikarugir engines |
| Libraries + renderers | Template 1.0.21 `Frameworks`: D3DMetal 4.0b2, DXMT v0.80-244, DXVK, MoltenVK, GStreamer | Sikarugir wrapper template |
| Extra renderers | `d3dmetal-4.0b3` (Template 1.0.24), `dxmt-codegen` (`assets/renderers`, `patches/dxmt-codegen`) | side by side, per game |

Installed at `~/Library/Application Support/SteamBridge/runners/sikarugir-11` (`current` symlink).
Pins and checksums: top of `scripts/setup.sh`.

## Renderers

| Renderer | Translates | Pick with | Notes |
|---|---|---|---|
| D3DMetal (Apple GPTk) | DX11, DX12 -> Metal | default | Best for DX12. Apple Silicon only |
| DXMT | DX10, DX11 -> Metal | `STEAMBRIDGE_RENDERER=dxmt` | Often faster on DX11 (Arkham Knight +14% avg) |
| DXVK | DX10, DX11 -> Vulkan (MoltenVK) | `STEAMBRIDGE_RENDERER=dxvk` | Fallback |

```
DirectX 12    -> D3DMetal
DirectX 11    -> D3DMetal or DXMT (benchmark both)
DirectX 10/9  -> DXMT or DXVK
```

Build variants: `STEAMBRIDGE_D3DMETAL=d3dmetal-4.0b3`, `STEAMBRIDGE_DXMT=dxmt-codegen`. All variables: [CONFIG.md](CONFIG.md).

## Legacy: Sikarugir Windows-Steam wrapper

Only for `install.sh --legacy-wrapper` / `legacy/`. A wrapper has three layers, each updated separately:

```
Wrapper template   launcher + libraries + bundled renderers   legacy/update-wrapper.sh
Wine engine        the Wine build that runs Windows programs  legacy/swap-engine.sh
Renderer           D3DMetal / DXMT / DXVK (Configure checkbox) per game
```

### Recommended wrapper config (Oct 2026)

```
Template:  1.0.21
Engine:    WS12WineSikarugir11.0_1   (Wine 11)
D3DMetal:  4.0b2   (bundled with the template)
DXMT:      v0.80-244 dev build (bundled), or v0.80 release
```

### Engines

| Engine | Wine | Use | Notes |
|---|---|---|---|
| WS12WineSikarugir11.0_1 | 11 | Default | Needs template 1.0.16+ |
| WS12WineSikarugir10.0_8 | 10 | Fallback if a game regresses on 11 | Works on older templates |
| WS12WineCX24.0.7_7 | 9 | Older fallback | CrossOver 24 source Wine |
| WS12WineGPTK1.1_3 | 7 | Avoid | Can't run the modern Steam webhelper (stalls) |

`swap-engine.sh` downloads any engine in `SIKARUGIR_ENGINE_LIST` (`legacy/lib.sh`).

```bash
bash legacy/swap-engine.sh WS12WineSikarugir11.0_1 Steam   # also updates the template if needed
bash legacy/swap-engine.sh WS12WineSikarugir10.0_8 Steam   # roll back to Wine 10
```

Each swap keeps the previous engine as `SharedSupport/wine.backup-<timestamp>`.

### Templates

- Wine 11 engines need template 1.0.16+. On 1.0.11 they die with `SikarugirSdk.FileUtilsError error 1`.
- Newer templates bundle newer renderers. 1.0.21 ships D3DMetal 4.0b2 and DXMT v0.80-244.
- `bash legacy/update-wrapper.sh Steam`: replaces `Contents/{MacOS,Frameworks,Resources,Configure.app}`,
  keeps `SharedSupport` and `Info.plist` settings, backs up to `~/Applications/Sikarugir/.Steam-wrapper-backup-<ts>/`.

### Renderer updates

- D3DMetal: bundled in recent templates. `legacy/fetch-d3dmetal.sh` is only for a newer Apple build;
  `setup-steam.sh` overlays it only if newer (never downgrades).
- DXMT: `legacy/update-dxmt.sh` installs the latest release, leaves newer dev builds alone.
