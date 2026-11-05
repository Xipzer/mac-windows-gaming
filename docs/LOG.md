# Project log

What was tried, measured and decided, in order. Numbers: [BENCHMARKS.md](BENCHMARKS.md). Per-game details: [GAMES.md](GAMES.md). Settings: [CONFIG.md](CONFIG.md).

## Test system

| | |
|---|---|
| Mac | MacBook Pro 14", M4 Max (10P + 4E CPU, 32-core GPU), 36 GB |
| macOS | 26.6.2 for every measurement below. Later tested on 27.0.1 |
| Display | 3024x1964 Retina, 120 Hz; desktop normally "looks like" 1800x1169 |
| Power | AC, High Power mode |
| Steam | Native macOS client, build 1791918634 (Oct 20 2026) |

## Stack

```
Mac Steam (/Applications/Steam.app) + steambridge.dylib: enables Steam Play for Windows games
  -> compatibility tool "steambridge" (dylib/feats/compat_run.sh)
     -> Sikarugir Wine 11, x86_64 under Rosetta 2, msync
        -> renderer per game: D3DMetal 4.0b2 | DXMT (stock or codegen) | DXVK
        -> patched ntdll: Valve's steamclient64 is rerouted to lsteamclient
     -> per-game profile: steamapps/compatdata/<appid>/steambridge.env
```

## Timeline

### 1. Getting games to run (Oct 8)

- Moved from Windows Steam in a Sikarugir wrapper to native Mac Steam plus the hook library.
- Needed: `runner.env` with Sikarugir variables; the library path baked into the launcher (SIP strips `DYLD_*` from `/bin/sh`); Valve's own `steamclient64.dll` kept (DRM error `3:0000065432` otherwise); the ntdll detour rebuilt for Wine 11.
- Dragon Ball: the Unreal launcher stub spins forever, so `direct-shipping.sh` starts the Shipping exe directly.
- Sonic: blank dialog text was FreeType not found; fixed by the launcher library path.
- Retina mode on by default. Before, games only saw the scaled 1800x1169.

### 2. Rename (Oct 20)

Renamed to SteamBridge everywhere. `scripts/setup.sh` migrates older installs.

### 3. Configuration tuning (Oct 20)

| Finding | Result | Decision |
|---|---|---|
| This Wine has no esync; with msync off every wait went through wineserver (32% of a core) | msync on: wineserver 2%, +8-15% avg | On by default. LEGO off (hangs with D3DMetal) |
| DXMT vs D3DMetal on DX11 | Batman +14% avg, +35% min on DXMT; LEGO and Sonic faster on D3DMetal | Per game |
| `ROSETTA_ADVERTISE_AVX=0` | Batman +4% avg | Batman only (Sonic needs AVX) |
| Run script polled `ps` every second and never matched the game | 2.6-4% of a core, now 0% | Replaced with blocking waits |
| `runner.env` overrode launch options, so most `WINE*` options never reached the game | | Fixed |
| `D3DM_MTL4` (macOS 27 only), `D3DM_SUPPORT_DXR` (already default) | No effect | Removed |
| Forced Game Mode | No gain, slightly lower mins | Opt-in |
| Overlay off, `WINEDEBUG=-all` | No change | Unchanged |
| D3DMetal 4.0b3 | Batman slower (60-64 vs 66), DX12 menus equal | Installed, not used |

Batman at 1800x1169, old default to tuned: avg 90 to 130, min 45 to 76.

### 4. Resolution (Oct 20)

- Mouse offset at 3024x1964: Wine only doubles the desktop mode active at launch, and picking another in game switched modes mid-session. `STEAMBRIDGE_DESKTOP_MODE=1512x982` switches the desktop before Wine starts and restores it on exit.
- Sweep from 2048 to 3600 wide: below about 2704 wide the minimum stops improving (CPU-bound dips). 3600x2338 is downscaled waste. Native 3024x1964 vs 3600x2338: +39% avg, +53% min. Chosen: native.
- The Metal HUD shows the drawable size, not the game's internal resolution. Sonic rendered at 1800x1012 and upscaled; LEGO ran 1800x1169 capped at 60 Hz; Dragon Ball ran 3600x2338. All set to native in their own settings files.

### 5. Code-level optimization (Oct 20-21)

Profiling (xctrace, Metal System Trace): at native every game is GPU-bound (94-100%). In CPU-bound frames, 72% is the game's own Rosetta-translated code. DX11 frames present Direct (no compositing).

| Attempt | Evidence | Result |
|---|---|---|
| DXMT rebuild, 9 patches plus LTO | Removes measured CPU hot spots | No measurable gain |
| DXMT fast-math, group-scope UAV barriers | | No gain |
| Priority shim for E-core threads | Synthetic 2.76x for IDLE threads | No gain in Batman |
| Latency QoS tier 0 for all threads | Synthetic 10 ms timer 72 to 11 ms | No gain |
| Wine `msvcr100` memcpy without string instructions | Synthetic small copies 2-3x faster | No gain |
| `D3DM_BOUNDS_CHECK=0` | | Within noise |
| DXMT codegen: vectorized buffer loads and stores, no read bounds checks | GPU code 12-17% smaller | Batman +4% avg, +6% max, identical frame. Adopted |
| Dragon Ball `-dx11` on D3DMetal / DXMT | | 19 / 40 vs 41 on DX12. Stays DX12 |

### 6. Saves, caps, entry scripts (Oct 20-21)

- Cloud saves: Steam syncs to `C:\users\steamuser`, Wine names the profile after the Mac user. The run script now merges that profile into `steamuser` and links it. Sonic and LEGO saves load again.
- Sonic 60 fps cap removed in memory by a dinput8 proxy (`games/sonicfrontiers`, same patches as Hedge Mod Manager's "Disable FPS Limit"). Uncapped native: avg 69-82.
- LEGO forced 60 Hz and V-Sync in `PCCONFIG.TXT`; now 120 Hz, V-Sync off.
- Sonic black screen on DXMT: fixed with borderless plus `d3d11.ignoreMapFlagNoWait=True`, still slower than D3DMetal.
- Scripted entry to gameplay for each game (`tools/bench`).

### 7. macOS 27 (Nov 2026)

- Tested on 27.0.1.
- The upgrade removes Rosetta 2. Reinstall with `softwareupdate --install-rosetta --agree-to-license`.
- Spotlight reindexes after the upgrade and lowers performance for about a day.
- Minor updates are held until verified.

## Final profiles (`configs/games/<appid>.env`)

| Game | Renderer | Sync | Other | Resolution | Result |
|---|---|---|---|---|---|
| Batman: Arkham Knight (208650) | DXMT codegen | msync | AVX off, uncapped | 3024x1964 | avg 74-75, max 132 |
| Sonic Frontiers (1237320) | D3DMetal | msync | cap removed, borderless | 3024x1701 | avg 69-82 |
| LEGO Star Wars TSS (920210) | D3DMetal | msync off | 120 Hz, V-Sync off | 3024x1964 | avg 72-78 |
| Dragon Ball: Sparking! ZERO (1790600) | D3DMetal DX12 | msync | 60 cap kept (speed tied to fps) | 3024x1964 | title 41 |

## Dead ends (do not retry without new evidence)

- Rosetta has no performance knobs besides `ROSETTA_ADVERTISE_AVX`. TSO cannot be turned off.
- High Power mode and fans do not raise clocks; they only delay throttling.
- D3DMetal's Metal 4 path is DX12 and macOS 27 only.
- MetalFX frame interpolation cannot be injected (needs game motion vectors).
- CrossOver 26.3 modules are not ABI-compatible with Sikarugir Wine (protocol 1809 vs 931).
- ARM64/FEX Wine: paid CrossOver Preview only, DX11 only, mixed results.
- macOS 27 for speed: no measured gain.

## Open items

- Dragon Ball gameplay route not scripted (needs a match set up through menus).
- LEGO with D3DMetal and msync deadlocks (`RtlpWaitForCriticalSection`); root cause unknown.
- Batman texture pooling mod (Arkham Quixote) untested; it targets stutter, not average fps.
- The heaviest Batman compute pass is texture work; speeding it up needs D3DMetal or DXMT texture-path work.

Reproduce a benchmark: [tools/bench/README.md](../tools/bench/README.md#examples).
