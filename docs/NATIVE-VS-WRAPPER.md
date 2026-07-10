# Native macOS ports vs Windows-via-D3DMetal

**Rule of thumb: if a game has a real native macOS build, run that — even through
Rosetta 2 it usually beats the Windows/Wine route.** Reserve D3DMetal/Wine for
Windows-exclusive titles.

## Why native often wins

- A native Metal port talks to the GPU directly; the Wine route adds a Windows→Wine→
  D3DMetal translation stack on top.
- Rosetta 2 (x86→arm64 CPU translation) overhead is small on modern M-series chips,
  especially an M-Pro/Max.
- The Windows route can be *unplayable* for some titles (e.g. Shadow of Mordor via Wine).

## The catch: "native" ≠ "Apple Silicon native"

Most older ports (Feral Interactive, Aspyr, ~2012–2016) are **Intel x86_64** apps that
run via **Rosetta 2**. A few (like Valheim) have true **arm64** builds. And beware
**32-bit** ports: macOS Catalina (10.15)+ **cannot run 32-bit code at all** — some old
ports (or their launchers) are 32-bit and broken on modern macOS.

## Verified verdicts (mid-2026, tested up to macOS 26 Tahoe)

| Game | Bitness | Arch on M-series | API | Runs on macOS 26? | Verdict |
|---|---|---|---|---|---|
| **Valheim** | 64-bit | **arm64 native** | Metal | ✅ | **NATIVE** (official Steam build) |
| **Batman: Arkham City GOTY** | 64-bit (default branch) | Rosetta 2 | Metal | ✅ | **NATIVE** — "Perfect", beats D3DMetal. Don't use the `mac_retail_11` (32-bit) beta branch. |
| **Middle-earth: Shadow of Mordor** | 64-bit | Rosetta 2 | Metal | ✅ | **NATIVE** — Wine route rated *unplayable* |
| **Tomb Raider (2013)** | 64-bit game / **32-bit launcher** | Rosetta 2 | Metal | ✅ (with fix) | **NATIVE** — add Steam launch option `-nolauncher` to skip the broken 32-bit launcher; then locked 60 fps |

## How to run native (not through the wrapper)

Use the **native macOS Steam client** (`/Applications/Steam.app`), *not* the Sikarugir
Windows-Steam wrapper. They're separate installs. The wrapper is only for Windows-only
games; native ports belong in native Steam.

### Tomb Raider (2013) launcher fix
Steam → right-click the game → **Properties → Launch Options** → enter:
```
-nolauncher
```

## Deciding for a new game

```bash
bash scripts/check-compat.sh --name "Game Name"
```
If it's a known native port, the script says **RUN NATIVE INSTEAD**. Otherwise look it up
on AppleGamingWiki — it lists native-port status and ratings.

## Note on your hardware

Benchmarks in the wild are mostly from M1/M1 Pro/Max. On an **M4 Max** everything here has
far more headroom — native ports that were "low performance on M1" run comfortably, and
you can push higher settings than the quoted figures.
