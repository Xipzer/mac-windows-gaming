# Sources and versions

## Version snapshot (Oct 2026)

| Component | Version | Notes |
|---|---|---|
| macOS | 26.6.2 | Test system. macOS 27 released 14 Sep 2026 |
| Steam for macOS | build 1791918634 | Signatures in `signatures/macos.arm64` + fetched by `scripts/setup.sh` |
| Wine engine | WS12WineSikarugir11.0_1 (Wine 11) | Pinned in `scripts/setup.sh` |
| Wrapper template | 1.0.21 (libraries), 1.0.24 (D3DMetal 4.0b3) | Pinned in `scripts/setup.sh` |
| D3DMetal | 4.0b2 default, 4.0b3 optional | |
| DXMT | v0.80-244 bundled; dxmt-codegen build in `assets/renderers` | v0.80 release 23 Apr 2026 |
| Dobby | `5dfc8546954ce3b3198132ab13fddb89ee92cdd7` | Hook library, built by `make dobby` |
| Heroic | 2.22.3 | Self-updates |
| Sikarugir Creator | 1.0.2 | Legacy route only (Homebrew cask) |
| CrossOver | 26.3.0 | Paid; only needed for the EA App |

### Earlier snapshots (legacy wrapper)

| Date | Engine | Template | D3DMetal | DXMT |
|---|---|---|---|---|
| Jun 2026 | Sikarugir 10.0_6 | 1.0.11 | 4.0b1 | v0.74 |
| Jul 2026 | Sikarugir 10.0_6 | 1.0.11 | 4.0b1 | v0.80 |
| Oct 2026 | Sikarugir 11.0_1 | 1.0.21 | 4.0b2 | v0.80-244 |

## Rosetta 2 risk

- macOS 27 is the last version with full Rosetta 2.
- The Wine engine is x86_64 under Rosetta, so macOS 28 (late 2027) may break this approach.
- Watch for ARM64 Wine with D3DMetal (CrossOver Preview has FEX-based ARM64 builds, no D3DMetal yet).

## Links

| What | URL |
|---|---|
| Sikarugir | https://github.com/Sikarugir-App/Sikarugir |
| Sikarugir engines | https://github.com/Sikarugir-App/Engines |
| Sikarugir wrapper templates | https://github.com/Sikarugir-App/Wrapper |
| Engine list | https://raw.githubusercontent.com/Sikarugir-App/Engines/main/EngineList.txt |
| DXMT | https://github.com/3Shain/dxmt |
| Dobby | https://github.com/jmpews/Dobby |
| Gcenx Wine/GPTk builds | https://github.com/Gcenx |
| Apple Game Porting Toolkit | https://developer.apple.com/games/game-porting-toolkit/ |
| Heroic | https://heroicgameslauncher.com |
| Heroic: EA games on Mac | https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/wiki/EA-Games-on-Mac |

Compatibility databases: [COMPATIBILITY.md](COMPATIBILITY.md#where-to-verify).

## History

- Whisky archived May 2025; don't use it.
- The Origin-based EA App workaround died when EA shut Origin down (Apr 2025).
