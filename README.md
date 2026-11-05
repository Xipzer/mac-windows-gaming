# SteamBridge

SteamBridge lets the native macOS Steam client run Windows games. A small hook library
(`steambridge.dylib`) is injected into Steam.app and turns on Steam Play, and a
compatibility tool runs each game through a Wine 11 runner (Sikarugir) with D3DMetal,
DXMT and a Steam API bridge (lsteamclient).


## Routes

| Store | Route | Notes |
|---|---|---|
| Steam | Native Mac Steam + SteamBridge (Wine 11, D3DMetal/DXMT) | One Steam app for Mac and Windows games |
| Epic / GOG / Amazon | Heroic | Its Game-Porting-Toolkit runner |
| Steam (fallback) | Legacy Windows Steam in a Sikarugir wrapper ([legacy/](legacy/README.md)) | Superseded, kept for edge cases |
| EA / Origin | None free | EA App fails under free Wine |

Never works: kernel anti-cheat (CS2, EAC, BattlEye) and EA App games. Prefer a native macOS port when one exists
([docs/NATIVE-VS-WRAPPER.md](docs/NATIVE-VS-WRAPPER.md)). Check a game first: `bash scripts/check-compat.sh <appid>`.

## Quick install

From a clone:

    ./install.sh

Without a clone:

    curl -fsSL https://raw.githubusercontent.com/Xipzer/mac-windows-gaming/main/install.sh | bash

Installs Rosetta 2, Homebrew, cmake, Steam (if missing) and Heroic (`--no-heroic` to skip), runs
`scripts/setup.sh`, then `scripts/apply-game-configs.sh` if a tuned game has been launched. Other flags:
`--no-steam`, `--legacy-wrapper`; anything else goes to `scripts/setup.sh`.

## Layout

- `dylib/` hook library and the compatibility tool run script (`dylib/feats/compat_run.sh`)
- `overlay-shim/`, `helpers/` support binaries
- `lsteamclient/`, `steam-shim/`, `bridge/`, `ntdll-patch/` Steam bridge sources and tools
- `app/` optional SwiftUI management app
- `assets/` runner environment, ntdll patch for Sikarugir Wine 11, launch wrapper
- `install.sh` one-command installer; `scripts/setup.sh` SteamBridge installer
- `scripts/doctor.sh` read-only health report; `scripts/check-compat.sh` will-it-run check
- `configs/games/`, `games/` tuned per-game profiles and game fixes; `tools/bench/` benchmark automation
- `legacy/` old Windows-Steam wrapper route

## Build

Needs Xcode command line tools and cmake. The repo path must not contain spaces.

    git clone https://github.com/jmpews/Dobby.git vendor/dobby
    git -C vendor/dobby checkout 5dfc8546954ce3b3198132ab13fddb89ee92cdd7
    make dobby
    make all

Output: `out/steambridge.dylib`.

## Install (SteamBridge only)

Quit Steam, then:

    scripts/setup.sh

This builds the repo, assembles the Wine 11 runner, stages the Steam bridge, patches
ntdll, injects the dylib into `/Applications/Steam.app` (a stock copy is backed up
first) and installs the compatibility tool as `steambridge`. It also moves an older
install over to the SteamBridge names.

Options: `--skip-build` (re-run after a Steam update), `--force`, `--no-default`,
`--migrate`, `--uninstall`.

Files:

- `~/Library/Application Support/SteamBridge/` runners, bridge, signatures, launchers
- `~/Library/Application Support/Steam/compatibilitytools.d/steambridge/` compatibility tool

## Settings and results

- `scripts/apply-game-configs.sh` installs the tuned per-game profiles (`configs/games/*.env`) and in-game settings.
- [docs/LOG.md](docs/LOG.md): everything tried, measured and decided.
- [docs/BENCHMARKS.md](docs/BENCHMARKS.md): all numbers. [docs/GAMES.md](docs/GAMES.md): per-game notes and scripts.
- [docs/CONFIG.md](docs/CONFIG.md): every `steambridge.env` variable.

## Docs

- [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md): decision tree, verified games, where to check.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md): symptom, cause, fix. Start with `scripts/doctor.sh`.
- [docs/ENGINES.md](docs/ENGINES.md): engines, templates, renderers. [docs/SOURCES.md](docs/SOURCES.md): versions and links.
- [AGENTS.md](AGENTS.md): rules for AI agents working on this setup.

## Logs

- Per game: `~/Library/Application Support/Steam/steamapps/compatdata/<appid>/steambridge-run.log`
- Wine output: `~/Library/Application Support/SteamBridge/launchers/<appid>/steambridge-wine.log`
- Hook library: `~/Library/Application Support/SteamBridge/steambridge.log`
- Installer: `~/Library/Application Support/SteamBridge/setup/build.log`

## License

Free for personal, hobby, research and other noncommercial use under the [PolyForm Noncommercial License 1.0.0](LICENSE).
You may not sell it or use it in a paid product or service without written permission.
