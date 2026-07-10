# Wine engines & renderers

The single most important concept: **the Wine engine and the graphics renderer are
two independent choices.** In Sikarugir, the engine is the whole Wine bundle; the
renderer (D3DMetal / DXMT / DXVK) is a checkbox in Configure. You mix them freely.

## The engines (Sikarugir)

| Engine | Wine base | Built by | Best for | Avoid for |
|---|---|---|---|---|
| **WS12WineSikarugir10.0_6** | **Wine 10** | Gcenx | ★ Everything. Newest Wine, most stable modern Steam webhelper. **Default.** | — |
| WS12WineCX24.0.7_7 | Wine 9 | CodeWeavers/Gcenx | Mature fallback, general apps | — |
| WS12WineGPTK1.1_3 | Wine 7 (2023) | Apple/Gcenx | D3DMetal specialist only | **Modern Steam client — its CEF webhelper STALLS** |

**Why Sikarugir 10 wins:** newer Wine = newer bundled Chromium/CEF and wineserver fixes,
which is exactly what the modern Steam client's `steamwebhelper` needs. GPTk 1.1's
Wine 7 base cannot drive it (you get `CSteamEngine::BMainLoop appears to have stalled`).

There is **no Wine 11 Sikarugir engine** as of July 2026 — Sikarugir 10 is the newest.

Swap engines from the CLI:
```bash
bash scripts/swap-engine.sh WS12WineSikarugir10.0_6 Steam
```
(Engines must be downloaded once via Sikarugir's GUI so they're cached in
`~/Library/Application Support/Sikarugir/Engines/`.)

## The renderers

| Renderer | Translates | Notes |
|---|---|---|
| **D3DMetal** (Apple GPTk) | DirectX **11 & 12** → Metal | Closed-source, free, Apple Silicon only. Best for DX12. MetalFX/DLSS-translation. |
| **DXMT** (3Shain) | DirectX **10 & 11** → Metal | Best free open layer for DX10/11. Update via `scripts/update-dxmt.sh`. |
| **DXVK** | DirectX 10/11 → Vulkan (MoltenVK) | Fallback; the only option on Intel Macs. |

Pick per game:
```
DirectX 12    -> D3DMetal
DirectX 11    -> D3DMetal (try DXMT if glitchy)
DirectX 10/9  -> DXMT or DXVK
Old / 2D      -> WineD3D (default), or run native
```

## D3DMetal versions (don't conflate the two lineages)

- **Apple GPTk track** (developer.apple.com / Gcenx): GPTk **4.0 beta 1** (1 Jun 2026)
  is the newest Apple beta. Stable line is 3.0-3.
- **CrossOver's D3DMetal**: the 3.x line, which Sikarugir bundles as `D3DMetal/3.0/`.

This repo overlays the freshest **Apple GPTk** D3DMetal you provide over Sikarugir's
bundled 3.0. If you ever hit a regression, the stock `D3DMetal/3.0` is the tested-stable
fallback (a `.bak-*` copy is made automatically).

## Current recommended config (July 2026)

```
Engine:    WS12WineSikarugir10.0_6  (Wine 10)
Renderer:  D3DMetal (Apple GPTk 4.0 beta1)  for DX11/12
DXMT:      v0.80                             for DX10/11 when D3DMetal misbehaves
```
