# Benchmarks

Batman: Arkham Knight built-in benchmark, MacBook Pro M4 Max (32-core GPU, 36 GB), macOS 26.6.2, AC power, High Power mode.
Settings: High textures/shadows/LOD, AA on, 16x AF, Enhanced Rain + Light Shafts on, V-Sync off, MaxFPS 1000 (uncapped). Fullscreen.
Each row is 3 runs in one session (shader cache warm). Driven automatically (`tools/bench/`).

## 1800×1169 (CPU-bound scenes dominate)

| Config | Min | Avg | Max | wineserver CPU |
|---|---|---|---|---|
| D3DMetal, msync off (old default) | 40 / 40 / 55 | 93 / 83 / 93 | 141 | 31-33% |
| D3DMetal, msync on | 38-52 | 87-107 | 169 | 2% |
| D3DMetal, msync on, Game Mode off | 53-56 | 105-109 | 169 | 2% |
| **DXMT, msync on** | 65-75 | 117-129 | 209 | 2.6% |
| **DXMT, msync on, AVX off** | **73-77** | **128-131** | 208 | 2.8% |
| + WINEDEBUG=-all | 74-77 | 117-130 | 209 | no change |
| + Steam overlay off | 70-76 | 115-130 | 210 | no change |

Old default to best: **avg 90 -> 130 (+44%), min 45 -> 76 (+69%)**.

## 3600×2338 (GPU-bound, 100% GPU)

| Config | Min | Avg | Max |
|---|---|---|---|
| D3DMetal, msync on, AVX off | 29-32 | 51 | 70-71 |
| **DXMT, msync on, AVX off** | 37-38 | 53-55 | 87-88 |

## What each change does

| Change | Result | Default |
|---|---|---|
| msync on (`WINEMSYNC=1`) | wineserver 32% -> 2% of a core, +8-15% avg | on |
| DXMT for DX11 | +14% avg, +35% min (Arkham Knight) | per game (black screen in Sonic Frontiers) |
| `ROSETTA_ADVERTISE_AVX=0` | +4% avg, higher mins under DXMT | per game |
| Forced Game Mode | no gain (slightly lower mins) | off (`STEAMBRIDGE_GAMEMODE=1`) |
| Steam overlay off | no change | on (`STEAMBRIDGE_OVERLAY=0`) |
| `WINEDEBUG=-all` | no change | unchanged |
| Watchdog removed | run script 2.6-4% of a core -> 0% | done |

## Game status with msync on

| Game | Renderer | Status |
|---|---|---|
| Batman: Arkham Knight | DXMT | Benchmarked above |
| LEGO Star Wars: Skywalker Saga | DXMT | Intro plays; logs harmless 60 s critical-section warnings at boot |
| Sonic Frontiers | D3DMetal | Menu OK. DXMT: black window |
| Dragon Ball Sparking! ZERO | D3DMetal (DX12) | Title screen OK; UE driver warning box needs one click |

## Resolution sweep (DXMT, msync, AVX off; desktop at exactly half the render size, so mouse is exact)

| Render res | Pixels vs native | Min | Avg | Max | GPU busy | Detail vs native |
|---|---|---|---|---|---|---|
| 2048x1330 | 46% | 71 | 109 | 227 | 84% | 75% |
| 2294x1490 | 58% | 65 | 102 | 180 | 85% | 88% |
| 2560x1600 (16:10, letterboxed) | 69% | 65 | 94 | 151 | 90% | 91% |
| 2704x1756 | 80% | 64 | 85 | 131 | 96% | 93% |
| **3024x1964 (native)** | 100% | 55 | 71 | 124 | 94% | 100% |
| 3600x2338 (downscaled) | 142% | 36 | 51 | 88 | 100% | 109% |

- Below ~2704 wide the minimum stops improving (64-71): the dips are CPU-bound, so fewer pixels only raise the average.
- Native vs the old 3600x2338: +39% avg, +53% min, and the panel shows the frame 1:1.
- "Detail" = mean edge gradient of the same benchmark frame scaled to the panel, relative to native.

## Native resolution fix

With Retina mode, Wine only doubles the desktop mode active at launch. Choosing 3024x1964 in game while the desktop
was 1800x1169 made Wine switch modes mid-session, which broke the mouse mapping. `STEAMBRIDGE_DESKTOP_MODE=1512x982`
switches the desktop before Wine starts and restores it on exit; 3024x1964 is then the launch mode and the mouse is exact.

## Thread priority shim (`STEAMBRIDGE_PRIO=1`)

Lifts Windows IDLE/LOWEST threads out of the E-core-only background band. Synthetic test: 2.76x throughput for such a
thread. Arkham Knight at 2048x1330 (CPU-bound): on 118/115/116 avg, off 126/116/116. No measurable gain; stays opt-in.

## DXMT source build (9 patches + LTO): no measurable gain

Patches in `patches/dxmt/` (blocking waits, allocator fast path, compute threadgroup hint, fewer unix calls/refcounts,
optional fast-math and group-scope UAV barriers). Interleaved A/B, same session:

| Case | base | opt |
|---|---|---|
| 2048x1330 (CPU-bound), avg | 118-127 | 119-121 |
| 3024x1964 (GPU-bound), avg (warm) | 67-71 | 71-72 |
| 3024x1964, opt + fast-math + group barriers | | 71-73 |

The render thread's DXMT share is small next to the game's own translated code, and at native the frame is bound by
one heavy compute pass on the GPU. Shipped renderer stays the stock DXMT build.

## D3DMetal 4.0b3 vs 4.0b2: no gain

Batman (D3DMetal, native): b2 avg 66, b3 avg 60-64. Dragon Ball and Sonic menus: identical GPU load. Stays on 4.0b2.

## CPU micro-fixes (Batman, 2048x1330, DXMT, interleaved): no gain

| Fix | Off | On |
|---|---|---|
| Latency-QoS tier 0 for all threads (`STEAMBRIDGE_PRIO_LATENCY=0`) | 115-127 | 112-127 |
| Wine msvcr100 memcpy without string instructions (native override) | 125-127 | 116-125 |
| `D3DM_BOUNDS_CHECK=0` (D3DMetal, native) | 66 | 67-68 |

Each works in isolation (synthetic: 10 ms timer 72 -> 11 ms; small memcpy 2-3x faster) but the game's own translated
code dominates the CPU-bound frame.

## DXMT shader codegen (Oct 21 2026): small, consistent gain, adopted for Batman

`patches/dxmt-codegen`: vectorized raw/structured buffer loads and stores, optional removal of read bounds checks.
Offline: all 616 Batman compute shaders compile; GPU machine code 12-17% smaller (up to 47% on some).
Batman native 3024x1964, interleaved, 3 runs each (warm runs 2-3):

| Config | Min | Avg | Max |
|---|---|---|---|
| Stock DXMT | 40-58 | 71-74 | 118-124 |
| + vectorized loads/stores | 56-57 | 74 | 130-131 |
| **+ no read bounds checks** | 57-58 | **74-75** | **130-132** |

Final benchmark frame vs stock: mean pixel difference 0.74 (stock vs stock: 1.04), so no visible change.

## Sonic Frontiers uncapped (dinput8 proxy), native 3024x1701, gameplay route

| Config | Avg | p10 | GPU |
|---|---|---|---|
| Capped (stock) | 56-57 | 53-56 | 75% |
| **Uncapped, D3DMetal** | **69-82** | 62-69 | 99-100% |
| Uncapped, DXMT + codegen | 52-54 | 42-43 | 70-73% |
