# mac-windows-gaming

Free Windows gaming on Apple Silicon Macs, no CrossOver. Windows games get a normal
**Play button in native Mac Steam**, rendered through Apple's **D3DMetal**.

Verified on macOS 26.6.2, Apple M4 Max, October 2026 (Sikarugir Wine 11, D3DMetal 4.0b2, free NotProton fork).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Xipzer/mac-windows-gaming/main/install.sh | bash
```

- Installs Rosetta 2, Homebrew, cmake, Steam (if missing) and Heroic.
- Builds a free fork of [NotProton](https://github.com/NotProtonNot/NotProton) and injects it into Mac Steam, on Sikarugir's free Wine 11.
- No GUI steps, no Windows Steam client.
- Stock `Steam.app` is backed up first. Undo: `scripts/setup-notproton.sh --uninstall`.

## What runs

| Store | Route | Notes |
|---|---|---|
| **Steam** | Native Mac Steam + free NotProton (Wine 11 + D3DMetal) | One Steam app for Mac *and* Windows games |
| **Epic / GOG / Amazon** | Heroic (native) | Games run via its GPTk runner |
| **EA / Origin** | ❌ not free | EA App doesn't work under free Wine |

Never works (any tool, free or paid): kernel anti-cheat (CS2 VAC, EAC, BattlEye) and EA App games
(Jedi Survivor, NFS Heat, ...). Online multiplayer is often broken even when the game runs.
Details: [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

| Game (M4 Max) | Result |
|---|---|
| Batman: Arkham Knight | High: 1800×1169 avg **92 fps**, native 3024×1964 avg **65 fps** |
| LEGO Star Wars: The Skywalker Saga | Plays |
| Sonic Frontiers | Plays |
| Dragon Ball Sparking! ZERO | Runs (launch option, see [docs/NOTPROTON.md](docs/NOTPROTON.md)) |

Full numbers and settings: [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

**Check for a native port first.** Valheim, Batman: Arkham City, Shadow of Mordor and Tomb Raider (2013)
run better native than translated. See [docs/NATIVE-VS-WRAPPER.md](docs/NATIVE-VS-WRAPPER.md).

## Stack

```
Mac Steam (/Applications/Steam.app)
  └─ notproton.dylib        free NotProton fork: turns on Steam Play for Windows games
      └─ run script          builds a Wine prefix per game, stages the Steam bridge
          └─ Sikarugir Wine 11 runner  (+ ntdll detour so Steam DRM passes)
              └─ D3DMetal 4.0b2 (DX11/12) · DXMT · MoltenVK   from Sikarugir template 1.0.21
```

- Retina is on by default, so games can use the panel's real resolution (3024×1964 on a 14" MacBook Pro), not the scaled 1800×1169.
- How it works and what the fork changes: [docs/NOTPROTON.md](docs/NOTPROTON.md). Engines and renderers: [docs/ENGINES.md](docs/ENGINES.md).

## Scripts

| Script | Purpose |
|---|---|
| `install.sh` | Prerequisites + Steam + Heroic + `setup-notproton.sh`. Idempotent. |
| `scripts/setup-notproton.sh` | Build/install the NotProton stack. `--skip-build` after a Steam update, `--force` to rebuild, `--uninstall` to restore stock Steam. |
| `scripts/doctor.sh` | Read-only system report. |
| `scripts/check-compat.sh` | Will this game run? Encodes the decision tree. |
| `notproton/` | Fork patch, ntdll detour, runner env (GPL-3.0, see [notproton/README.md](notproton/README.md)). |
| *Legacy wrapper* | `install.sh --legacy-wrapper`, `setup-steam.sh`, `swap-engine.sh`, `update-wrapper.sh`, `update-dxmt.sh`, `fetch-d3dmetal.sh`: Windows Steam inside a Sikarugir wrapper. Superseded, kept as a fallback. |

```bash
bash scripts/check-compat.sh 1790600      # Dragon Ball Sparking! ZERO -> LIKELY WORKS
bash scripts/check-compat.sh 1774580      # Jedi Survivor -> BLOCKED (EA App)
bash scripts/setup-notproton.sh --skip-build   # games stopped launching after a Steam update
```

## Troubleshooting

Most common: games stop launching after a Steam update. Fix: `scripts/setup-notproton.sh --skip-build`.
Everything else: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

AI agents: read [AGENTS.md](AGENTS.md) first.

## Requirements

- Apple Silicon (M-series), macOS 14+ (tested on 26), Xcode Command Line Tools.
- ~2 GB for the runner and build, plus your games. You must **own** the games.
- Rosetta 2. macOS 27 is the last version with full Rosetta 2; macOS 28+ may need ARM64 Wine builds ([docs/SOURCES.md](docs/SOURCES.md)).

## Licensing

- Scripts and docs: MIT (`LICENSE`). `notproton/` is GPL-3.0 (patch to and bytes derived from NotProton).
- No Apple binaries are committed. D3DMetal comes from Sikarugir's published template at install time; the legacy route fetches your own copy (`fetch-d3dmetal.sh`).
- Valve's DLLs are downloaded from Valve's CDN on your machine and hash-checked.

## Credits

**NotProtonNot** (NotProton), **Maxyme** (standalone fork), **Sikarugir** (Wine engines and
templates), **Gcenx**, **3Shain/DXMT**, **Valve** (Proton's lsteamclient), **Apple** (GPTk),
**Heroic**, and the **r/macgaming** / **AppleGamingWiki** communities.
Links and version snapshot: [docs/SOURCES.md](docs/SOURCES.md).
