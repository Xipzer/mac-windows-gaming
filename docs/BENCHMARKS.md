# Benchmarks

## Test system

| | |
|---|---|
| Mac | MacBook Pro 14", Apple M4 Max, 36 GB |
| macOS | 26.6.2 |
| Display | 3024×1964 Retina, 120 Hz, scaled to "looks like" 1800×1169 |
| Stack | Native Mac Steam + free NotProton, Sikarugir Wine 11, D3DMetal 4.0b2 |
| Power | Plugged in |

## Batman: Arkham Knight (built-in benchmark)

Settings: Fullscreen, V-Sync off, Texture/Shadows/Level of Detail High, Anti-Aliasing on,
16x anisotropic, Motion Blur/Chromatic Aberration/Film Grain off, Enhanced Rain and Light
Shafts on. Interactive Smoke/Fog and Paper Debris are NVIDIA-only (greyed out on Mac).

| Resolution | Max FPS cap | Min | Avg | Max |
|---|---|---|---|---|
| 1800×1169, V-Sync on | - | 55 | 87 | V-Sync |
| 1800×1169, run 1 | 90 | 46 | 92 | 138 |
| 1800×1169, run 3 | 90 | 54 | 93 | 134 |
| 1800×1169 | 120 | 50 | 91 | 118 |
| **3024×1964 (native)** | 120 | 39 | **65** | 84 |
| 3600×2338 (supersampled) | 120 | 30 | 51 | 70 |

- **Shader cache:** min rose 46 → 54 from run 1 to run 3. First runs stutter more.
- **Native vs scaled:** 2.6× the pixels costs ~30% fps. GPU-bound, not memory: 4.4 GB of the 28.7 GB GPU budget used.
- **Caps:** 90 fps wasn't enforced (max 138); 120 is (max 118).
- **Resolutions above 1800×1169** only appear with Retina mode on (default in this repo).
- **Config file:** `steamapps/common/Batman Arkham Knight/BMGame/Config/BmSystemSettings.ini` (`MaxFPS`, `ResX`, `ResY`); the in-game menu works once Retina is on.

### Vs published results

| Setup | Settings | Avg FPS | Source |
|---|---|---|---|
| M1 Pro, paid CrossOver 25 | Ultra, 1080p | ~50 | [MacGamingDB](https://macgamingdb.app/games/208650) |
| M4 Max, this repo (free) | High, 1800×1169 (≈1080p pixels) | 92 | above |

~1.8× the M1 Pro figure at a similar pixel count, in line with the GPU generation gap. No sign the
free stack is slower than CrossOver. AppleGamingWiki rates the game "Perfect" under GPTk
([list](https://www.applegamingwiki.com/wiki/Game_Porting_Toolkit)).

## Other games

| Game | Result |
|---|---|
| LEGO Star Wars: The Skywalker Saga | Menus in ~30 s, plays |
| Sonic Frontiers | Plays (needed fork change 2, see [NOTPROTON.md](NOTPROTON.md#what-the-fork-changes)) |
| Dragon Ball Sparking! ZERO | Title screen; needs `direct-shipping.sh` launch option |

## Run your own

1. Plug in; set Energy Mode to High Power if available.
2. Run the benchmark 3 times; report run 3 (shader cache warm).
3. Record resolution, cap, V-Sync and quality settings with the numbers.
