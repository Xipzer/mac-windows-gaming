# Native ports vs Wine

**If a game has a real macOS build, run that.** Even through Rosetta 2 it usually beats the Wine route.
Use SteamBridge (Wine + D3DMetal/DXMT) for Windows-only titles.

## Why native wins

- A native Metal port talks to the GPU directly; the Wine route adds Windows -> Wine -> D3DMetal translation.
- Rosetta 2 (x86 -> arm64) overhead is small on M-series chips, especially Pro/Max.
- Some titles are unplayable through Wine (Shadow of Mordor).

## "Native" is not always Apple Silicon native

- Most older ports (2012-2016) are Intel x86_64 and run via Rosetta 2.
- A few (Valheim) have true arm64 builds.
- macOS 10.15+ can't run 32-bit code. Some old ports, or their launchers, are 32-bit and broken.

## Verified (up to macOS 26)

| Game | Bitness | Arch on M-series | API | Verdict |
|---|---|---|---|---|
| Valheim | 64-bit | arm64 native | Metal | NATIVE (official Steam build) |
| Batman: Arkham City GOTY | 64-bit (default branch) | Rosetta 2 | Metal | NATIVE, beats D3DMetal. Avoid the 32-bit `mac_retail_11` beta branch |
| Middle-earth: Shadow of Mordor | 64-bit | Rosetta 2 | Metal | NATIVE; Wine route unplayable |
| Tomb Raider (2013) | 64-bit game, 32-bit launcher | Rosetta 2 | Metal | NATIVE with launch option `-nolauncher`; then locked 60 fps |

## How to run native

- Install it in Mac Steam as usual. SteamBridge only applies to Windows builds.
- If Steam offers both, make sure the game's Properties > Compatibility does not force SteamBridge.
- Tomb Raider (2013): Properties > Launch Options > `-nolauncher`.

## New game

```bash
bash scripts/check-compat.sh --name "Game Name"
```

Known native ports print `RUN NATIVE INSTEAD`. Otherwise check AppleGamingWiki.

## Hardware note

Most published benchmarks are from M1/M1 Pro/Max. An M4 Max has far more headroom; settings above the quoted ones are realistic.
