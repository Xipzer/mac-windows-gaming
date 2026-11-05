# Per-game settings

## Where settings go

| Place | Format | Notes |
|---|---|---|
| `~/Library/Application Support/Steam/steamapps/compatdata/<appid>/steambridge.env` | One `NAME=value` per line, `#` starts a comment line | Preferred. Read at every launch, no Steam restart |
| Steam > game > Properties > Launch Options | `%command% NAME=value NAME2=value` | Must come after `%command%`. `NAME=value %command%` fails with `OS Error 260` |
| `configs/games/<appid>.env` in this repo | Same as `steambridge.env` | Tuned copies. `scripts/apply-game-configs.sh` installs them |

Rules (from `dylib/feats/compat_run.sh`):

- Only names starting with `STEAMBRIDGE_`, `WINE`, `D3DM_`, `DXMT_`, `DXVK_`, `MTL_`, `ROSETTA_` or `CX_GRAPHICS` are read. Other lines are ignored.
- A launch option beats the same name in `steambridge.env`.
- Values are taken literally. Do not quote them.
- Your `WINEDLLOVERRIDES` is appended after the run script's own overrides.

## Variables

| Variable | Default | Effect |
|---|---|---|
| `STEAMBRIDGE_RENDERER` | `d3dmetal` | `dxmt` or `dxvk` |
| `STEAMBRIDGE_D3DMETAL` | `d3dmetal` | `d3dmetal-4.0b3` for the newer D3DMetal build |
| `STEAMBRIDGE_DXMT` | `dxmt` | `dxmt-codegen` for the build with faster buffer access. Turn its features on with `DXMT_CONFIG=d3d11.shaderVectorizeBufferLoads=True;d3d11.shaderVectorizeBufferStores=True;d3d11.shaderNoBufferBoundsCheck=True` |
| `DXMT_CONFIG` | unset | DXMT options, `;` separated |
| `WINEMSYNC` | `1` | `0` uses wineserver sync (slower). Forced to `0` for 32-bit games |
| `ROSETTA_ADVERTISE_AVX` | `1` | `0` hides AVX from the game. Some games need AVX (Sonic Frontiers) |
| `STEAMBRIDGE_RETINA` | `1` | `0` limits games to the scaled desktop resolution |
| `STEAMBRIDGE_DESKTOP_MODE` | unset | `WxH` in points. Switches the desktop to that @2x mode for the session and restores it on exit |
| `STEAMBRIDGE_GAMEMODE` | `0` | `1` forces macOS Game Mode (needs `gamepolicyctl` from Xcode) |
| `STEAMBRIDGE_OVERLAY` | `1` | `0` skips the Steam overlay |
| `STEAMBRIDGE_ARGS` | unset | Extra game arguments, for example `-dx11` |
| `STEAMBRIDGE_HIDE_LAUNCHER_TILE` | `0` | `1` hides the per-game launcher icon in the Dock |
| `STEAMBRIDGE_PRIO` | `0` | `1` starts wineserver with the thread priority shim |
| `STEAMBRIDGE_PRIO_MODE` | `mr` | With the shim: `mr`, `floorN` or `off` |
| `STEAMBRIDGE_PRIO_LATENCY` | unset | With the shim: `0` or `1` sets every Windows thread to that latency QoS tier |
| `STEAMBRIDGE_PRIO_THROUGHPUT` | unset | With the shim: `0` sets throughput QoS tier 0 |
| `MTL_HUD_ENABLED` | unset | `1` shows the Metal performance HUD |
| `D3DM_ENABLE_METALFX` | `1` | D3DMetal MetalFX support |
| `WINEDEBUG` | `err+all,fixme-all` | Wine log channels |

The priority shim settings gave no measurable gain ([BENCHMARKS.md](BENCHMARKS.md#thread-priority-shim-steambridge_prio1)).

## Choosing a renderer

| Renderer | Translates | Use |
|---|---|---|
| D3DMetal (Apple) | DX11, DX12 to Metal | Default. Best for DX12 |
| DXMT | DX10, DX11 to Metal | Often faster for DX11 (Arkham Knight +14% avg) |
| DXVK | DX10, DX11 to Vulkan (MoltenVK) | Fallback |

DX12: D3DMetal. DX11: benchmark DXMT and D3DMetal. DX9/10: DXMT or DXVK.

## Native resolution

With Retina mode, Wine only doubles the desktop mode that is active when the game starts. Picking a different resolution in game makes Wine switch modes mid-session and the mouse goes off. Set `STEAMBRIDGE_DESKTOP_MODE` to half the panel size, then set the same full size in the game's settings.

| Desktop mode (points) | Game resolution |
|---|---|
| 1024x665 | 2048x1330 |
| 1147x745 | 2294x1490 |
| 1352x878 | 2704x1756 |
| 1512x982 | 3024x1964 (14" MacBook Pro native) |

List the modes your display offers: `"$HOME/Library/Application Support/SteamBridge/dispmode" list` (columns: points W, points H, pixels W, pixels H, Hz).
