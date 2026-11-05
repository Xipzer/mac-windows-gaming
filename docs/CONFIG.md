# Per-game settings

Put `NAME=value` lines in `~/Library/Application Support/Steam/steamapps/compatdata/<appid>/steambridge.env`
(comments with `#`). Same variables also work as Steam launch options after `%command%`; launch options win.
No Steam restart needed.

| Variable | Default | Effect |
|---|---|---|
| `STEAMBRIDGE_RENDERER` | `d3dmetal` | `dxmt` (often faster on DX11), `dxvk` |
| `STEAMBRIDGE_DXMT` | `dxmt` | `dxmt-codegen`: vectorized buffer access; enable with `DXMT_CONFIG` keys `d3d11.shaderVectorizeBufferLoads`, `d3d11.shaderVectorizeBufferStores`, `d3d11.shaderNoBufferBoundsCheck` |
| `STEAMBRIDGE_D3DMETAL` | `d3dmetal` | `d3dmetal-4.0b3` for the newer D3DMetal build |
| `WINEMSYNC` | `1` | `0` falls back to wineserver sync (slower) |
| `ROSETTA_ADVERTISE_AVX` | `1` | `0` can be faster on some games |
| `STEAMBRIDGE_RETINA` | `1` | `0` limits games to the scaled resolution |
| `STEAMBRIDGE_GAMEMODE` | `0` | `1` forces macOS Game Mode for the session |
| `STEAMBRIDGE_OVERLAY` | `1` | `0` skips Steam overlay injection |
| `STEAMBRIDGE_DESKTOP_MODE` | unset | `WxH` points: switch the Mac desktop to that @2x mode for the session (game runs at 2W x 2H with exact mouse) |
| `STEAMBRIDGE_PRIO` | `0` | `1` starts wineserver with the priority shim (`STEAMBRIDGE_PRIO_MODE=mr|floorN|off`) |
| `STEAMBRIDGE_PRIO_LATENCY` | `keep` | with the shim: `0`/`1` forces every Windows thread to Mach latency QoS tier 0/1 (less timer slack) |
| `STEAMBRIDGE_PRIO_THROUGHPUT` | `keep` | with the shim: `0` forces throughput QoS tier 0 |
| `STEAMBRIDGE_ARGS` | unset | Extra game arguments, e.g. `-dx11` |
| `MTL_HUD_ENABLED` | unset | `1` shows the Metal performance HUD |

Tuned profiles live in `configs/games/<appid>.env` (installed by `scripts/apply-game-configs.sh`).

Mouse-exact render sizes (desktop mode -> render): 1024x665 -> 2048x1330, 1147x745 -> 2294x1490, 1352x878 -> 2704x1756, 1512x982 -> 3024x1964.
