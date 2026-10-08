# Native ports vs Wine/D3DMetal

**If a game has a real native macOS build, run that.** Even through Rosetta 2 it usually beats
the Windows/Wine route. Use NotProton (Wine + D3DMetal) for Windows-only titles.

## Why native wins

- A native Metal port talks to the GPU directly; the Wine route adds a Windows → Wine → D3DMetal translation stack.
- Rosetta 2 (x86 → arm64 CPU translation) overhead is small on modern M-series chips, especially Pro/Max.
- Some titles are *unplayable* through Wine (e.g. Shadow of Mordor).

## "Native" is not always Apple Silicon native

- Most older ports (Feral Interactive, Aspyr, ~2012-2016) are **Intel x86_64** and run via **Rosetta 2**.
- A few (like Valheim) have true **arm64** builds.
- macOS Catalina (10.15)+ **cannot run 32-bit code**. Some old ports, or their launchers, are 32-bit and broken.

## Verified (mid-2026, up to macOS 26 Tahoe)

| Game | Bitness | Arch on M-series | API | Runs on macOS 26? | Verdict |
|---|---|---|---|---|---|
| **Valheim** | 64-bit | **arm64 native** | Metal | ✅ | **NATIVE** (official Steam build) |
| **Batman: Arkham City GOTY** | 64-bit (default branch) | Rosetta 2 | Metal | ✅ | **NATIVE**, "Perfect", beats D3DMetal. Avoid the `mac_retail_11` (32-bit) beta branch. |
| **Middle-earth: Shadow of Mordor** | 64-bit | Rosetta 2 | Metal | ✅ | **NATIVE**; Wine route rated *unplayable* |
| **Tomb Raider (2013)** | 64-bit game / **32-bit launcher** | Rosetta 2 | Metal | ✅ (with fix) | **NATIVE** with launch option `-nolauncher` (skips the broken 32-bit launcher); then locked 60 fps |

## How to run native

- Install native ports in Mac Steam (`/Applications/Steam.app`). NotProton is the default only for Windows games.
- Tomb Raider (2013): Steam → right-click the game → **Properties → Launch Options** → `-nolauncher`.
- Legacy wrapper users: native ports belong in Mac Steam, not the Sikarugir Windows-Steam wrapper (separate installs).

## New game

```bash
bash scripts/check-compat.sh --name "Game Name"
```

Known native ports print **RUN NATIVE INSTEAD**. Otherwise check AppleGamingWiki for native-port status and ratings.

## Hardware note

Most published benchmarks are from M1/M1 Pro/Max. An **M4 Max** has far more headroom: ports rated
"low performance on M1" run comfortably, and higher settings than quoted are realistic.
