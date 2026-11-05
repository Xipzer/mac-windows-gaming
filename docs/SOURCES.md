# Sources and versions

## Runner

`scripts/setup.sh` builds one runner from pinned, checksummed parts. Pins and SHA-256 sums are at the top of that script.

| Layer | Version | From |
|---|---|---|
| Wine | `WS12WineSikarugir11.0_1` (Wine 11) | Sikarugir engines |
| Libraries and renderers | Template 1.0.21 `Frameworks`: D3DMetal 4.0b2, DXMT v0.80-244, DXVK, MoltenVK, GStreamer | Sikarugir wrapper template |
| D3DMetal 4.0b3 | Template 1.0.24 | Sikarugir wrapper template, side by side |
| DXMT codegen build | `assets/renderers/dxmt-codegen.tar.xz` | This repo, `patches/dxmt-codegen` |
| Steam bridge | NotProton v1.0.1 release payload (lsteamclient, steam.exe) plus Valve DLLs from `valve-packages.manifest` | Pinned in `scripts/setup.sh` and `app/Sources/SteamBridgeApp/Resources/valve-packages.manifest` |
| Hook library | Dobby `5dfc8546954ce3b3198132ab13fddb89ee92cdd7` | Built by `make dobby` |

Installed at `~/Library/Application Support/SteamBridge/runners/sikarugir-11` (`runners/current` links to it).

## Snapshot (Oct 2026)

| Component | Version | Notes |
|---|---|---|
| macOS | 26.6.2 for all benchmarks; now tested on 27.0.1 | |
| Steam for macOS | build 1791918634 | Signatures in `signatures/macos.arm64`, more fetched by `scripts/setup.sh` |
| D3DMetal | 4.0b2 default, 4.0b3 optional | 4.0b3 measured slower |
| DXMT | v0.80-244 bundled, codegen build in `assets/renderers` | v0.80 release: 23 Apr 2026 |
| Heroic | 2.22.3 | Updates itself |
| Sikarugir Creator | 1.0.2 | Legacy route only |
| CrossOver | 26.3.0 | Paid. Only needed for the EA App |

Legacy wrapper versions over time:

| Date | Engine | Template | D3DMetal | DXMT |
|---|---|---|---|---|
| Jun 2026 | Sikarugir 10.0_6 | 1.0.11 | 4.0b1 | v0.74 |
| Jul 2026 | Sikarugir 10.0_6 | 1.0.11 | 4.0b1 | v0.80 |
| Oct 2026 | Sikarugir 11.0_1 | 1.0.21 | 4.0b2 | v0.80-244 |

## Rosetta 2 risk

- Wine here is x86_64 and runs under Rosetta 2. macOS 27 is the last version with full Rosetta 2, so macOS 28 may break this route.
- Watch for ARM64 Wine with D3DMetal. CrossOver Preview has FEX-based ARM64 builds, without D3DMetal so far.

## Links

| What | URL |
|---|---|
| Sikarugir | https://github.com/Sikarugir-App/Sikarugir |
| Sikarugir engines | https://github.com/Sikarugir-App/Engines |
| Sikarugir wrapper templates | https://github.com/Sikarugir-App/Wrapper |
| Engine list | https://raw.githubusercontent.com/Sikarugir-App/Engines/main/EngineList.txt |
| NotProton (bridge payload, signatures) | https://github.com/NotProtonNot/NotProton |
| DXMT | https://github.com/3Shain/dxmt |
| Dobby | https://github.com/jmpews/Dobby |
| Gcenx Wine and GPTk builds | https://github.com/Gcenx |
| Apple Game Porting Toolkit | https://developer.apple.com/games/game-porting-toolkit/ |
| Heroic | https://heroicgameslauncher.com |
| Heroic: EA games on Mac | https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/wiki/EA-Games-on-Mac |

## History

- Whisky was archived in May 2025. Do not use it.
- The Origin-based EA App workaround ended when EA shut Origin down in April 2025.
