# Project log

Everything tried, measured and decided, in order. Numbers come from `docs/BENCHMARKS.md`; per-game procedures from
`docs/GAMES.md`; settings from `docs/CONFIG.md`.

## Test system

| | |
|---|---|
| Mac | MacBook Pro 14", M4 Max (10P + 4E CPU, 32-core GPU), 36 GB |
| macOS | 26.6.2 (26.7.1 and 27.0.1 available, not installed) |
| Display | 3024x1964 Retina, 120 Hz ProMotion; desktop normally "looks like" 1800x1169 |
| Power | AC, High Power mode |
| Steam | Native macOS client, build 1791918634 (updated Oct 20 2026, still matched by signatures) |

## Stack

```
Mac Steam (/Applications/Steam.app)
  + steambridge.dylib        Steam Play for Windows games
  -> compat tool "steambridge" run script (dylib/feats/compat_run.sh)
     -> Sikarugir Wine 11.0 rev1, x86_64 under Rosetta 2, msync
        -> renderer per game: D3DMetal 4.0b2 | DXMT (stock or dxmt-codegen) | DXVK
        -> ntdll detour (assets/ntdll-sikarugir11.json) so Steam DRM sees Valve's steamclient64
     -> per-game profile: steamapps/compatdata/<appid>/steambridge.env
```

Install: `scripts/setup.sh` (build, runner, bridge, Steam.app patch, renderers, helpers), then
`scripts/apply-game-configs.sh` (per-game profiles and in-game settings).

## Timeline

### Phase 1: getting games to run (Oct 8)
- Moved from a Windows Steam client in a Sikarugir wrapper to native Mac Steam + the SteamBridge hook library.
- Needed: runner.env (Sikarugir variables), DYLD library path baked into the launcher (SIP strips it),
  Valve's own steamclient64 kept (DRM error 3:0000065432 otherwise), ntdll steamclient detour rebuilt for Wine 11.
- Dragon Ball: UE launcher stub spins forever; `direct-shipping.sh` launches the Shipping exe directly.
- Sonic: blank dialog text = FreeType not found, fixed by the launcher library path.
- Retina mode default on: games could only see the scaled 1800x1169 before.

### Phase 2: rename (Oct 20)
- Rebuilt as SteamBridge: renamed everywhere, migration script for older installs.

### Phase 3: configuration-level optimization (Oct 20)
Five research agents (CPU, launch path, renderers, upstream, live profiling). Findings and results:

| Finding | Result | Status |
|---|---|---|
| This Wine has no esync; with msync off every wait went through wineserver (32% of a core) | msync on: wineserver 2%, +8-15% avg | Default on (LEGO off: hangs with D3DMetal) |
| DXMT vs D3DMetal for DX11 | Batman +14% avg, +35% min on DXMT; LEGO and Sonic faster on D3DMetal | Per game |
| `ROSETTA_ADVERTISE_AVX=0` | Batman +4% avg | Batman only (Sonic requires AVX) |
| Run script polled `ps` every second and never matched the game | 2.6-4% of a core -> 0% | Replaced with blocking waits |
| `runner.env` overrode launch options; most `WINE*` options never reached the game | | Fixed |
| `D3DM_MTL4` (macOS 27 only), `D3DM_SUPPORT_DXR` (already default) | inert | Removed |
| Forced Game Mode | no gain, slightly lower mins | Opt-in |
| Steam overlay off, `WINEDEBUG=-all` | no change | Unchanged |
| D3DMetal 4.0b3 | Batman slower (60-64 vs 66), DX12 menus equal | Installed, not used |

Old default to tuned (Batman 1800x1169): avg 90 -> 130, min 45 -> 76.

### Phase 4: resolution (Oct 20)
- Mouse offset at 3024x1964: Wine only doubles the desktop mode active at launch; picking another in game switched modes
  mid-session. `STEAMBRIDGE_DESKTOP_MODE=1512x982` switches the desktop before Wine starts and restores it on exit.
- Sweep (2048 to 3600 wide): minimum stops improving below ~2704 wide (CPU-bound dips). 3600x2338 is downscaled waste.
  Native 3024x1964 vs 3600x2338: +39% avg, +53% min. Chosen: native, no quality trades.
- The Metal HUD reports the drawable size, not the game's internal resolution. Sonic was rendering at 1800x1012 and
  upscaling; LEGO at 1800x1169 capped to 60 Hz; Dragon Ball at 3600x2338. All set to native in their own settings files.

### Phase 5: code-level optimization (Oct 20-21)
Deep profile (xctrace, Metal System Trace): at native every game is GPU-bound (94-100%); CPU-bound frames are 72% the
game's own Rosetta-translated code. Frames present Direct (no compositing) for DX11 games.

| Attempt | Evidence | Result |
|---|---|---|
| DXMT rebuild, 9 patches (blocking waits, allocator fast path, threadgroup hint, fewer unix calls/refcounts, LTO) | removes measured CPU hot spots | no measurable gain |
| DXMT fast-math, group-scope UAV barriers | | no gain |
| E-core priority shim (wineserver `thread_policy_set` interposer) | synthetic 2.76x for IDLE threads | no gain in Batman |
| Latency QoS tier 0 for all threads | synthetic 10 ms timer 72 -> 11 ms | no gain |
| Wine `msvcr100` memcpy without string instructions | synthetic small copies 2-3x faster | no gain |
| `D3DM_BOUNDS_CHECK=0` | | within noise |
| **DXMT codegen: vectorized buffer loads/stores, no read bounds checks** | GPU code 12-17% smaller | **Batman +4% avg, +6% max, identical frame. Adopted.** |
| Dragon Ball `-dx11` (D3DMetal / DXMT) | | 19 / 40 vs DX12 41. Stays DX12 |

### Phase 6: saves, caps, entry scripts (Oct 20-21)
- Cloud saves: Steam syncs to `C:\users\steamuser`; Wine's profile is named after the Mac user. The run script now merges
  that profile into steamuser and links it. Sonic and LEGO saves load again.
- Sonic 60 fps cap: in-memory patch via a dinput8.dll proxy (`games/sonicfrontiers`, same 4 patches as Hedge Mod
  Manager's "Disable FPS Limit"). Uncapped native: avg 69-82.
- LEGO: game forced 60 Hz + V-Sync in PCCONFIG.TXT; set to 120 Hz, V-Sync off.
- Sonic black screen on DXMT: fixed with borderless + `d3d11.ignoreMapFlagNoWait=True` (still slower than D3DMetal).
- Automated entry to gameplay for every game (OCR-driven, `tools/bench`), see `docs/GAMES.md`.

## Final per-game profiles (`configs/games/<appid>.env`)

| Game | Renderer | Sync | Other | Native res | Result |
|---|---|---|---|---|---|
| Batman: Arkham Knight (208650) | DXMT codegen | msync | AVX off, uncapped | 3024x1964 | avg 74-75, max 132 |
| Sonic Frontiers (1237320) | D3DMetal | msync | cap removed (dinput8), borderless | 3024x1701 | avg 69-82 |
| LEGO Star Wars TSS (920210) | D3DMetal | msync off | 120 Hz, V-Sync off | 3024x1964 | avg 72-78 |
| Dragon Ball Sparking! ZERO (1790600) | D3DMetal DX12 | msync | 60 cap kept (game speed tied to fps) | 3024x1964 | title 41 |

## Dead ends (do not retry without new evidence)
- Rosetta has no performance knobs (only `ADVERTISE_AVX`; others are diagnostics). TSO cannot be turned off.
- High Power mode and fans do not raise clocks, only delay throttling.
- Metal 4 path in D3DMetal is DX12 and macOS 27 only.
- MetalFX frame interpolation cannot be injected (needs game motion vectors).
- CrossOver 26.3 modules are not ABI-compatible with Sikarugir Wine (protocol 1809 vs 931).
- ARM64/FEX Wine: paid CrossOver Preview only, DX11 only, mixed results.
- macOS 27: no measured gain, removes Rosetta on upgrade.

## Open items
- Dragon Ball gameplay route not scripted (needs a match through menus).
- LEGO + D3DMetal + msync deadlock root cause (RtlpWaitForCriticalSection) not found.
- Batman texture pooling mod (Arkham Quixote) untested; targets stutter, not average fps.
- The dominant Batman compute pass is texture work; making it faster needs D3DMetal/DXMT texture-path work.

## Reproduce a benchmark
```sh
cd tools/bench
./relaunch_fast.sh "$(cat ~/Library/Application\ Support/Steam/steamapps/compatdata/208650/steambridge.env)"
./bench2.sh mylabel          # runs Options > PC Performance Test, OCRs min/max/avg into $BENCH_OUT/RESULTS.txt
./cycle_game.sh 920210 LEGOSTARWARS ./lego_enter.sh "MTL_HUD_ENABLED=1"; ./route.sh lego LEGOSTARWARS ./walk_lego.sh
```
Screen must be unlocked. Don't touch keyboard or mouse during runs.
