# SteamBridge

Play Windows games from the native macOS Steam client on Apple Silicon. A hook library injected into Steam.app turns on Steam Play, and each Windows game runs through Wine 11 (Sikarugir) with D3DMetal or DXMT.

## Requirements

| Item | Detail |
|---|---|
| Mac | Apple Silicon (arm64). Intel is not supported |
| macOS | 26 or 27. Tested on 27.0.1; benchmarks in [docs/BENCHMARKS.md](docs/BENCHMARKS.md) were taken on 26.6.2 |
| Xcode Command Line Tools | `xcode-select --install` |
| Rosetta 2 | Wine runs as x86_64. The installer adds it if missing |
| Disk | About 3 GB free for the runner and build, plus the games |
| Steam for macOS | In `/Applications/Steam.app`, logged in once |
| git | Comes with the Command Line Tools |

The installer also installs Homebrew, cmake and Heroic if they are missing.

## Install

One command:

    curl -fsSL https://raw.githubusercontent.com/Xipzer/mac-windows-gaming/main/install.sh | bash

This clones the repo to `~/Library/Caches/steambridge/repo`. From your own clone:

    git clone https://github.com/Xipzer/mac-windows-gaming.git
    cd mac-windows-gaming
    ./install.sh

What it does: checks the Mac, installs Rosetta 2, Homebrew, cmake, Steam (if missing) and Heroic, then runs `scripts/setup.sh`. That script quits Steam, builds the hook library, downloads and assembles the Wine runner, patches Steam.app (a stock copy is backed up first) and makes SteamBridge the default tool for Windows games.

If Steam was not installed, the installer stops after installing it. Open Steam, log in, let it update, quit it, and run the installer again.

After the first launch of each tuned game (see below), install its settings:

    scripts/apply-game-configs.sh

Flags for `install.sh`: `--no-heroic`, `--no-steam`, `--legacy-wrapper` (old route, with optional `--gptk-dmg <path>`). Anything else is passed to `scripts/setup.sh`.

Check a game before buying or installing it: `bash scripts/check-compat.sh <appid>`. Check the install: `bash scripts/doctor.sh` (read only, exit 0 means healthy).

## macOS 27 notes

- The upgrade to 27 removes Rosetta 2. Reinstall it: `softwareupdate --install-rosetta --agree-to-license`.
- Check Rosetta: `arch -x86_64 /usr/bin/true` exits 0 when it works.
- Spotlight reindexes the disk after an upgrade. Performance is lower for about a day; do not benchmark until it finishes.
- Hold minor macOS updates until someone has verified them with this setup.

## Games

Tested on a MacBook Pro M4 Max (32-core GPU) at native panel resolution. Profiles live in `configs/games/<appid>.env`.

| Game | App ID | Renderer | Result |
|---|---|---|---|
| Batman: Arkham Knight | 208650 | DXMT (codegen build), AVX off | Benchmark avg 74-75, max 132 at 3024x1964 |
| LEGO Star Wars: The Skywalker Saga | 920210 | D3DMetal, msync off | avg 72-78 at 3024x1964 |
| Sonic Frontiers | 1237320 | D3DMetal, 60 fps cap removed | avg 69-82 at 3024x1701 |
| Dragon Ball: Sparking! ZERO | 1790600 | D3DMetal (DX12) | 41 on the title screen at 3024x1964; keep the 60 fps cap (game speed follows fps) |

Does not work:

- EA App games (Star Wars Jedi: Survivor, Need for Speed, Battlefield, The Sims 4). The EA App fails under free Wine (`INST-14-1627`).
- Kernel or Wine-hostile anti-cheat (Counter-Strike 2, Valorant, Fortnite, EAC and BattlEye games).

Use the Mac version when one exists (Valheim, Batman: Arkham City, Shadow of Mordor, Tomb Raider 2013). Epic, GOG and Amazon games run through Heroic with its Game-Porting-Toolkit runner. Details: [docs/GAMES.md](docs/GAMES.md). All numbers: [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

## Per-game settings

Each game reads `~/Library/Application Support/Steam/steamapps/compatdata/<appid>/steambridge.env`, one `NAME=value` per line. No Steam restart needed.

| Setting | Use |
|---|---|
| `STEAMBRIDGE_RENDERER=dxmt` | DXMT instead of D3DMetal. Often faster for DX11 |
| `WINEMSYNC=0` | Turn off msync if a game hangs before its window appears |
| `ROSETTA_ADVERTISE_AVX=0` | Hide AVX. Only if a benchmark shows a gain |
| `STEAMBRIDGE_DESKTOP_MODE=1512x982` | Switch the desktop to this @2x mode during play so the game can run at native resolution with an exact mouse |
| `MTL_HUD_ENABLED=1` | Show the Metal fps HUD |

The same settings work as Steam launch options, but only after `%command%`, for example `%command% WINEMSYNC=0`. Launch options win over the file.

`1512x982` and the in-game resolutions set by `scripts/apply-game-configs.sh` match a 14" MacBook Pro (3024x1964 panel). On another Mac, list modes with `"$HOME/Library/Application Support/SteamBridge/dispmode" list` (columns: points W H, pixels W H, Hz) and pick the one whose pixel size equals the panel. All settings: [docs/CONFIG.md](docs/CONFIG.md).

## After a Steam update

If Windows games stop launching after Steam updates itself:

    scripts/setup.sh --skip-build

It quits Steam, re-patches Steam.app and refreshes the hook signatures. If you used the one-command install, the script is at `~/Library/Caches/steambridge/repo/scripts/setup.sh`.

## Uninstall

    scripts/setup.sh --uninstall

Restores the stock Steam.app from the backup and removes the compatibility tool. The runner, bridge and game prefixes stay in `~/Library/Application Support/SteamBridge`; delete that folder and `~/Library/Caches/steambridge` to remove everything. Games and saves in `steamapps` are not touched.

## Troubleshooting

Run `bash scripts/doctor.sh` first; it names the fix for each problem it finds. Then see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## More docs

| Doc | Contents |
|---|---|
| [docs/GAMES.md](docs/GAMES.md) | Will it run, native ports, per-game notes |
| [docs/CONFIG.md](docs/CONFIG.md) | Every per-game variable, renderer choice |
| [docs/BENCHMARKS.md](docs/BENCHMARKS.md) | All measurements |
| [docs/LOG.md](docs/LOG.md) | What was tried and decided, in order |
| [docs/SOURCES.md](docs/SOURCES.md) | Component versions and upstream links |
| [AGENTS.md](AGENTS.md) | Entry point for AI coding agents |
| [legacy/README.md](legacy/README.md) | Old route: Windows Steam in a Sikarugir wrapper |

## License

Free for personal, hobby, research and other noncommercial use under the [PolyForm Noncommercial License 1.0.0](LICENSE).
You may not sell it or use it in a paid product or service without written permission.
