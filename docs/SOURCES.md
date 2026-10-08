# Sources & version snapshot

## Version snapshot (8 October 2026)

| Component | Version | Date | Notes |
|---|---|---|---|
| macOS | 26.6.2 (Tahoe) | — | Tested on Apple M4 Max. macOS 27 released 14 Sep 2026 |
| Heroic Games Launcher | 2.22.3 | 16 Sep 2026 | self-updates |
| Sikarugir Creator | 1.0.2 | — | Homebrew cask |
| Sikarugir wrapper template | 1.0.21 | 1 Oct 2026 | bundles D3DMetal 4.0b2, DXMT v0.80-244 |
| Sikarugir Wine engine | WS12WineSikarugir11.0_1 (Wine 11) | 1 Oct 2026 | needs template 1.0.16+ |
| Previous engine line | WS12WineSikarugir10.0_8 (Wine 10) | 1 Oct 2026 | fallback |
| D3DMetal (Apple GPTk) | 4.0 beta 2 | — | bundled in template 1.0.21 |
| DXMT | v0.80 release (23 Apr 2026); dev builds past it | — | v0.81 / v1.0 not released yet |
| Gcenx macOS Wine builds | 11.18 | 25 Sep 2026 | standalone; not used directly here |
| CrossOver | 26.3.0 stable; Preview 20261006 | 21 Jul / 6 Oct 2026 | paid; only needed for the EA App (upstream NotProton) |
| NotProton | 1.0.3 upstream (CrossOver-only); free fork Maxyme `5b8d186` + our patch | 6 Oct 2026 | default Steam route here; see NOTPROTON.md |

### Rosetta 2 warning

Apple has said **macOS 27 is the last version with full Rosetta 2**. These Wine engines are
x86_64 and run through Rosetta, so this whole approach may be affected from macOS 28
(expected late 2027). Watch for ARM64 Wine builds: CrossOver Preview already has FEX-based
ARM64 builds, but D3DMetal isn't available on them yet.

## Primary tools

- Heroic Games Launcher — https://heroicgameslauncher.com · https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher
  - EA on Mac ("CrossOver is the only known working solution") — https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/wiki/EA-Games-on-Mac
- Sikarugir — https://github.com/Sikarugir-App/Sikarugir
  - Engines (list + downloads) — https://github.com/Sikarugir-App/Engines
  - Wrapper templates — https://github.com/Sikarugir-App/Wrapper
- Gcenx (Wine / GPTk builds) — https://github.com/Gcenx
- DXMT — https://github.com/3Shain/dxmt
- Apple Game Porting Toolkit — https://developer.apple.com/games/game-porting-toolkit/
- NotProton — https://github.com/NotProtonNot/NotProton
- Free NotProton fork (standalone-steam-gptk4) — https://github.com/Maxyme/NotProton/tree/standalone-steam-gptk4
- Dobby (hook library) — https://github.com/jmpews/Dobby

## Compatibility databases

- AppleGamingWiki — https://www.applegamingwiki.com/wiki/Game_Porting_Toolkit
- ProtonDB — https://www.protondb.com
- AreWeAntiCheatYet — https://areweanticheatyet.com
- CrossOver compatibility — https://www.codeweavers.com/compatibility
- MacGamingDB — https://macgamingdb.app

## History

- Whisky was archived in May 2025; don't use it — https://docs.getwhisky.app/maintenance-notice
- The Origin-based EA App workaround stopped working when EA shut Origin down (April 2025) —
  https://github.com/p0358/Fuck_off_EA_App
- CrossOver ↔ Wine version map — https://en.wikipedia.org/wiki/CrossOver_(software)

## Earlier snapshots

| Date | Engine | Template | D3DMetal | DXMT |
|---|---|---|---|---|
| Jun 2026 | Sikarugir 10.0_6 (Wine 10) | 1.0.11 | 4.0b1 (Apple DMG) | v0.74 |
| Jul 2026 | Sikarugir 10.0_6 | 1.0.11 | 4.0b1 | v0.80 |
| **Oct 2026** | **Sikarugir 11.0_1 (Wine 11)** | **1.0.21** | **4.0b2** | **v0.80-244** |
