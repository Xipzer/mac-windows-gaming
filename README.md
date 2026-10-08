# mac-windows-gaming

**Run Windows games on Apple Silicon macOS — for free, no CrossOver.**
A one-shot installer plus the hard-won knowledge base to get a working gaming
environment (Steam / Epic / GOG / Amazon) using Apple's **Game Porting Toolkit
(D3DMetal)** and free, open-source launchers.

> Verified on **macOS 26.6.2 (Tahoe), Apple M4 Max**, October 2026
> (Wine 11 engine, wrapper template 1.0.21, D3DMetal 4.0b2).
> Built from a real, end-to-end troubleshooting session — every fix here was
> discovered by hitting the wall first.

---

## TL;DR — one command

```bash
curl -fsSL https://raw.githubusercontent.com/Xipzer/mac-windows-gaming/main/install.sh | bash
```

This installs Rosetta 2, Homebrew, Heroic, Sikarugir, fetches **your own** copy of
Apple's D3DMetal locally, and sets up a Steam-for-Windows wrapper with every fix
pre-applied. There are exactly **two unavoidable GUI clicks** in Sikarugir (it has no
headless wrapper-create API); the script tells you precisely what to click, then
automates the rest.

---

## What you get

| Store | Route | Notes |
|---|---|---|
| **Steam** | Sikarugir wrapper (Wine 10 + D3DMetal) | Windows Steam client; works for non-anti-cheat games |
| **Epic / GOG / Amazon** | Heroic (native) | Native logins; games run via GPTk runner |
| **EA / Origin** | ❌ not free | EA App doesn't work under free Wine — needs paid CrossOver |

**Hard limits (any tool, free or paid):**
- **Kernel anti-cheat** (VAC-heavy, EAC, BattlEye) → won't run.
- **EA App games** (Jedi Survivor, NFS Heat, the EA catalog) → no free route.
- **Online multiplayer** is often broken under Wine even when the game runs offline.

---

## The stack (and why)

```
Launcher     Heroic (Epic/GOG/Amazon)   +   Sikarugir (Steam)
Wine engine  Sikarugir 11  (Wine 11)  ← best: newest Wine, stable Steam webhelper
Template     Sikarugir wrapper 1.0.21 ← bundles D3DMetal 4.0b2 + recent DXMT
Renderer     D3DMetal (DX11/12)  ·  DXMT (DX10/11)  ·  DXVK (DX10/11 via Vulkan)
             ^ chosen per-game, INDEPENDENT of the Wine engine (a checkbox)
D3DMetal     Apple GPTk (bundled with the template, or your own newer copy)
```

Full rationale in **[docs/ENGINES.md](docs/ENGINES.md)**.

---

## Scripts (run any individually)

| Script | Purpose |
|---|---|
| `install.sh` | One-shot: everything below in order. Idempotent. |
| `scripts/doctor.sh` | Read-only: report system + what's installed/current. Start here. |
| `scripts/fetch-d3dmetal.sh` | Fetch **your** Apple D3DMetal locally (DMG or Gcenx brew). |
| `scripts/setup-steam.sh` | Build/repair the Steam wrapper with all fixes. |
| `scripts/swap-engine.sh` | Change a wrapper's Wine engine (downloads it if needed). |
| `scripts/update-wrapper.sh` | Update the wrapper template (launcher + bundled renderers). |
| `scripts/update-dxmt.sh` | Update the DXMT (DX10/11→Metal) layer to latest. |
| `scripts/check-compat.sh` | Will this game run? Encodes the decision tree. |

```bash
# examples
bash scripts/doctor.sh
bash scripts/check-compat.sh 1790600            # Dragon Ball Sparking! ZERO -> LIKELY WORKS
bash scripts/check-compat.sh 1774580            # Jedi Survivor -> BLOCKED (EA App)
bash scripts/update-wrapper.sh Steam
bash scripts/swap-engine.sh WS12WineSikarugir11.0_1 Steam
```

---

## Native ports beat translation — check first

Several games have **official native macOS builds** that outperform the Windows-via-Wine
route on Apple Silicon. Don't run these through the wrapper:

| Game | Run as | Note |
|---|---|---|
| Valheim | **Native** | Apple Silicon build; no Rosetta/Wine |
| Batman: Arkham City | **Native** | 64-bit Metal (via Rosetta) |
| Shadow of Mordor | **Native** | 64-bit Metal; Wine route is unplayable |
| Tomb Raider (2013) | **Native** | Add Steam launch option `-nolauncher` (32-bit launcher is broken) |

Rule of thumb: **native (even via Rosetta) usually wins**; use Wine/D3DMetal only for
Windows-exclusive titles. Details in **[docs/NATIVE-VS-WRAPPER.md](docs/NATIVE-VS-WRAPPER.md)**.

---

## Troubleshooting

Every error we hit and its fix is in **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**.
Highlights:

| Symptom | Fix |
|---|---|
| Wrapper keeps re-running the installer | Launch target must be `steam.exe`, not `SteamSetup.exe` (auto-fixed by `setup-steam.sh`) |
| `Failed to load steamui.dll` | Let Steam self-update; don't block it with `steam.cfg` |
| `steamwebhelper is not responding` / BMainLoop stalled | Use the **Sikarugir 11 (Wine 11)** engine, not GPTk 1.1 |
| `SikarugirSdk.FileUtilsError error 1` at launch | Wrapper template too old for the engine: `scripts/update-wrapper.sh` |
| `Unexpected Transport Error (0x3008)` | Add `-tcp` launch flag; "VO: Continue Anyway" |
| EA App `INST-14-1627` | No free fix — EA App needs paid CrossOver |

---

## NotProton (Steam Play for Mac)

[NotProton](https://github.com/NotProtonNot/NotProton) (Sep 2026) lets native Mac Steam run
Windows games directly, like Proton on Linux. It's open source but **only works with paid
CrossOver**, so it isn't part of this free stack. An unproven free fork exists. See
**[docs/NOTPROTON.md](docs/NOTPROTON.md)**.

## Heads-up: Rosetta 2

macOS 27 is the last version with full Rosetta 2. These Wine engines run through Rosetta,
so this setup may need ARM64 Wine builds from macOS 28 onward.
See [docs/SOURCES.md](docs/SOURCES.md).

---

## For AI agents

This repo is designed to be agent-drivable. See **[AGENTS.md](AGENTS.md)** for a
structured workflow, decision points, exit codes, and the invariants you must respect
(e.g. never delete `steamapps/`, always prefer native ports, EA App is a hard stop).

---

## Requirements

- Apple Silicon (M-series). Intel Macs **cannot** use D3DMetal.
- macOS 14 (Sonoma)+. macOS 15+ for AVX games; 26 (Tahoe) for MetalFX.
- You must **own** the games. This project is about *tooling*, not piracy.
- ~free disk space for games (they're large).

---

## Legal / licensing

- This repo ships **no Apple binaries**. Apple's D3DMetal is free to download but its
  EULA forbids redistribution, so each user fetches their own copy locally at install
  time (`scripts/fetch-d3dmetal.sh`).
- Repo code is MIT (see `LICENSE`). Wine, DXMT, Heroic, Sikarugir, Gcenx builds are the
  property of their respective projects.

---

## Credits / sources

Built on the work of: **Gcenx** (Wine/GPTk/DXMT macOS builds), **Sikarugir** (Wineskin
successor), **Heroic Games Launcher**, **3Shain/DXMT**, **Apple** (Game Porting Toolkit),
and the **r/macgaming** / **AppleGamingWiki** communities.

See **[docs/SOURCES.md](docs/SOURCES.md)** for the full link list and version snapshot.
