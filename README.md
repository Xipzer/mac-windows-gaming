# mac-windows-gaming

**Run Windows games on Apple Silicon macOS, for free, no CrossOver.**
A one-command installer plus the knowledge base behind it: Windows games get a normal
**Play button in the native Mac Steam app**, rendered through Apple's **D3DMetal**.

> Verified on **macOS 26.6.2, Apple M4 Max**, October 2026
> (Sikarugir Wine 11, D3DMetal 4.0b2, free NotProton fork).
> Every fix here was found by hitting the wall first.

---

## TL;DR: one command

```bash
curl -fsSL https://raw.githubusercontent.com/Xipzer/mac-windows-gaming/main/install.sh | bash
```

It installs Rosetta 2, Homebrew, cmake, Steam (if missing) and Heroic. Then it builds a
**free fork of [NotProton](https://github.com/NotProtonNot/NotProton)** and injects it into
Mac Steam, running on Sikarugir's free Wine 11. No GUI steps, no Windows Steam client.
Stock `Steam.app` is backed up first; undo with `scripts/setup-notproton.sh --uninstall`.

---

## What you get

| Store | Route | Notes |
|---|---|---|
| **Steam** | Native Mac Steam + free NotProton (Wine 11 + D3DMetal) | One Steam app for Mac *and* Windows games |
| **Epic / GOG / Amazon** | Heroic (native) | Games run via its GPTk runner |
| **EA / Origin** | ❌ not free | EA App doesn't work under free Wine |

**Hard limits (any tool, free or paid):**
- **Kernel anti-cheat** (CS2 VAC, EAC, BattlEye) won't run.
- **EA App games** (Jedi Survivor, NFS Heat, ...) have no free route.
- **Online multiplayer** is often broken under Wine even when the game runs.

### Tested

| Game | Result (M4 Max) |
|---|---|
| Batman: Arkham Knight | High: 1800×1169 avg **92 fps**, native 3024×1964 avg **65 fps** |
| LEGO Star Wars: The Skywalker Saga | Plays |
| Sonic Frontiers | Plays |
| Dragon Ball Sparking! ZERO | Runs (launch option, see [docs/NOTPROTON.md](docs/NOTPROTON.md)) |

---

## The stack

```
Mac Steam (/Applications/Steam.app)
  └─ notproton.dylib        free NotProton fork: turns on Steam Play for Windows games
      └─ run script          builds a Wine prefix per game, stages the Steam bridge
          └─ Sikarugir Wine 11 runner  (+ ntdll detour so Steam DRM passes)
              └─ D3DMetal 4.0b2 (DX11/12) · DXMT · MoltenVK   from Sikarugir template 1.0.21
```

How it works, what the fork changes and why: **[docs/NOTPROTON.md](docs/NOTPROTON.md)**.
Engine choices: **[docs/ENGINES.md](docs/ENGINES.md)**.

---

## Scripts

| Script | Purpose |
|---|---|
| `install.sh` | One-shot: prerequisites + Steam + Heroic + `setup-notproton.sh`. Idempotent. |
| `scripts/setup-notproton.sh` | Build/install the free NotProton stack. `--skip-build` after a Steam update, `--force` to rebuild, `--uninstall` to restore stock Steam. |
| `scripts/doctor.sh` | Read-only system report. |
| `scripts/check-compat.sh` | Will this game run? Encodes the decision tree. |
| `notproton/` | The fork patch, ntdll detour, runner env (GPL-3.0, see `notproton/README.md`). |
| *Legacy wrapper route* | `install.sh --legacy-wrapper`, `setup-steam.sh`, `swap-engine.sh`, `update-wrapper.sh`, `update-dxmt.sh`, `fetch-d3dmetal.sh`: Windows Steam inside a Sikarugir wrapper. Superseded, kept as a fallback. |

```bash
bash scripts/check-compat.sh 1790600      # Dragon Ball Sparking! ZERO -> LIKELY WORKS
bash scripts/check-compat.sh 1774580      # Jedi Survivor -> BLOCKED (EA App)
bash scripts/setup-notproton.sh --skip-build   # games stopped launching after a Steam update
```

---

## Resolution: use Retina

Wine normally shows games your **scaled** display size (e.g. "looks like 1800×1169"), so every
game was capped there. The fork turns Wine's Retina mode on by default, so games can pick the
panel's real resolution (3024×1964 on a 14" MacBook Pro). Opt a game out with the launch option
`%command% NOTPROTON_RETINA=0`.

## Native ports beat translation; check first

| Game | Run as | Note |
|---|---|---|
| Valheim | **Native** | Apple Silicon build |
| Batman: Arkham City | **Native** | 64-bit Metal |
| Shadow of Mordor | **Native** | Wine route is unplayable |
| Tomb Raider (2013) | **Native** | Launch option `-nolauncher` |

Details: **[docs/NATIVE-VS-WRAPPER.md](docs/NATIVE-VS-WRAPPER.md)**.

---

## Troubleshooting

Full list: **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**.

| Symptom | Fix |
|---|---|
| Games stop launching after a Steam update | `scripts/setup-notproton.sh --skip-build` (pulls new signatures) |
| `Application load error 3:0000065432` | Steam DRM: re-run `setup-notproton.sh` (restores Valve's `steamclient64.dll` + ntdll detour) |
| A game's dialog is blank (no text) | Old run script: re-run `setup-notproton.sh` (FreeType path fix) |
| Launch option ignored / `OS Error 260` | Put options **after** `%command%`: `%command% VAR=1` |
| Game capped at 1800×1169 | Retina mode; on by default now, check you didn't pass `NOTPROTON_RETINA=0` |
| Launch seems stuck | A Steam EULA/"Play" dialog is hidden; bring Steam to the front |
| `steam://` links open the wrong Steam | `open -b com.valvesoftware.steam "steam://rungameid/<id>"` |

---

## For AI agents

See **[AGENTS.md](AGENTS.md)**: workflow, decision tree, invariants (never delete
`steamapps/`, prefer native ports, EA App is a hard stop).

## Requirements

- Apple Silicon (M-series). macOS 14+ (tested on 26). Xcode Command Line Tools.
- ~2 GB for the runner and build, plus your games. You must **own** the games.

## Heads-up: Rosetta 2

macOS 27 is the last version with full Rosetta 2. This Wine runs through Rosetta, so macOS 28+
may need ARM64 Wine builds. See [docs/SOURCES.md](docs/SOURCES.md).

## Legal / licensing

- Repo scripts and docs: MIT (`LICENSE`). `notproton/` contains a patch to and bytes derived
  from GPL-3.0 NotProton; it's GPL-3.0 (see `notproton/README.md`).
- No Apple binaries are committed. D3DMetal comes from Sikarugir's published template at
  install time; the legacy route fetches your own copy (`fetch-d3dmetal.sh`).
- Valve's DLLs are downloaded from Valve's CDN on your machine and hash-checked.

## Credits

**NotProtonNot** (NotProton), **Maxyme** (standalone fork), **Sikarugir** (Wine engines and
templates), **Gcenx**, **3Shain/DXMT**, **Valve** (Proton's lsteamclient), **Apple** (GPTk),
**Heroic**, and the **r/macgaming** / **AppleGamingWiki** communities.
Links and version snapshot: **[docs/SOURCES.md](docs/SOURCES.md)**.
