# AGENTS.md

Entry point for AI coding agents. Read this file fully before running anything.

SteamBridge lets native macOS Steam run Windows games: `steambridge.dylib` is injected into `/Applications/Steam.app`, and a compatibility tool runs each game with Sikarugir Wine 11 plus D3DMetal or DXMT.

## Runbooks

| Task | Doc |
|---|---|
| Install and configure on a fresh Mac | [docs/agent/INSTALL.md](docs/agent/INSTALL.md) |
| Add a game, update after Steam or macOS updates, benchmark, collect logs, uninstall | [docs/agent/OPERATIONS.md](docs/agent/OPERATIONS.md) |
| How the pieces connect, with file paths | [docs/agent/ARCHITECTURE.md](docs/agent/ARCHITECTURE.md) |
| Symptom to fix | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |
| Per-game variables | [docs/CONFIG.md](docs/CONFIG.md) |
| History and dead ends (read before tuning) | [docs/LOG.md](docs/LOG.md) |

## Prime directives

1. Never delete `steamapps/`, `steamapps/common/<game>` or `steamapps/compatdata/<appid>`. They hold the human's games and saves. Clearing `htmlcache`, `appcache/httpcache` and `dumps` is fine.
2. Quit Steam before editing `config/config.vdf` or `userdata/*/config/localconfig.vdf`. Steam rewrites them on exit.
3. Environment variables in launch options go after `%command%` (`%command% WINEMSYNC=0`). `VAR=1 %command%` fails with `OS Error 260`. Only a wrapper program such as `direct-shipping.sh` goes before `%command%`. Prefer `compatdata/<appid>/steambridge.env`.
4. Never replace Valve's `steamclient64.dll` in `$SB/bridge` with lsteamclient. Steam DRM checks it (`3:0000065432`). The ntdll detour does the rerouting.
5. Never change repository visibility, delete repositories, or change GitHub settings.
6. No comments in code. Keep the existing style.
7. EA App games are a hard stop: they fail under free Wine (`INST-14-1627`); only paid CrossOver works. Kernel anti-cheat (VAC on CS2, EAC, BattlEye) is a hard stop. Tell the human; do not try.
8. Prefer a native macOS port when one exists (`bash scripts/check-compat.sh --name "<game>"`).
9. Benchmark and input tools (`tools/bench`) need an unlocked screen that nobody touches. Confirm with the human first.
10. Never raise a game window with AppleScript while the game is in menus. It bounces the game (Arkham Knight returns to save select).
11. Before benchmarking, if `~/.hwlock/hw.sh` exists, run `~/.hwlock/hw.sh acquire <name>` and release it afterwards.
12. Do not launch games, restart Steam or run `scripts/setup.sh` unless the task needs it or the human asked. `bash scripts/doctor.sh` is read only; use it to inspect.
13. Never commit Apple binaries (D3DMetal, GPTk). They are downloaded on the machine.
14. Never log into Steam, Epic or GOG for the human, and never handle passwords.
15. No em or en dashes in any file.

## Repo map

| Path | What |
|---|---|
| `install.sh` | One-command installer: prerequisites, Steam, Heroic, then `scripts/setup.sh` and `scripts/apply-game-configs.sh` |
| `scripts/setup.sh` | Builds and installs SteamBridge. Flags: `--skip-build`, `--force`, `--no-default`, `--migrate`, `--uninstall` |
| `scripts/apply-game-configs.sh` | Copies `configs/games/*.env` into `compatdata/<appid>/steambridge.env` and writes in-game settings |
| `scripts/doctor.sh` | Read-only health report; exit 1 if issues, each with its fix |
| `scripts/check-compat.sh` | Will-it-run check by App ID or `--name` |
| `scripts/launch-game.sh` | `launch-game.sh <appid> [--hud] [--tail]`: start a game via `steam://` |
| `scripts/lib.sh` | Shared paths and helpers for the scripts |
| `configs/games/` | Tuned per-game profiles, `<appid>.env` |
| `games/sonicfrontiers/` | dinput8 proxy that removes Sonic Frontiers' fps cap |
| `dylib/` | Hook library injected into Steam; `dylib/feats/compat_run.sh` is the compatibility tool run script (embedded into the dylib at build) |
| `tests/` | `test_runner_env.py`: sources `assets/runner.env` against a fake runner (Python standard library only) |
| `assets/` | `runner.env` (renderer selection), ntdll patch spec and applier, `direct-shipping.sh`, DXMT codegen build |
| `helpers/` | `dispmode` (desktop mode switch), `prio_shim` (wineserver priority), `appinfo` and `iconmaker` (launcher bundle name and icon), `icon.swift` (app icon) |
| `overlay-shim/` | Optional Metal hook for the Steam overlay in games |
| `ntdll-patch/` | Source of the ntdll detour that reroutes Valve's `steamclient64.dll` to lsteamclient |
| `lsteamclient/`, `steam-shim/`, `bridge/` | Steam API bridge sources, Valve DLL fetcher (`bridge/fetch-valve.sh`) |
| `signatures/macos.arm64/` | Hook signature sets per Steam build |
| `patches/` | DXMT patches (`dxmt-codegen` is shipped) |
| `app/` | Optional SwiftUI manager app (`make app`); not used by the scripts |
| `tools/bench/` | Benchmark and input automation |
| `legacy/` | Old route: Windows Steam in a Sikarugir wrapper |
| `vendor/` | cJSON; Dobby is cloned here at build time |
| `docs/` | Human docs; `docs/agent/` agent runbooks |
| `Makefile` | Build and checks |
| `.shellcheckrc`, `.github/workflows/shellcheck.yml` | Shell lint config and CI |
| `LICENSE` | PolyForm Noncommercial 1.0.0. Do not edit |

Runtime paths (`$SB` = `~/Library/Application Support/SteamBridge`): runner `$SB/runners/current`, bridge `$SB/bridge`, compat tool `~/Library/Application Support/Steam/compatibilitytools.d/steambridge`, logs listed in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#logs).

## Making changes

1. Read the files you change and the matching section of [docs/agent/ARCHITECTURE.md](docs/agent/ARCHITECTURE.md).
2. Edit. Keep scripts POSIX `sh` where they already are; no comments.
3. Check:

| Change | Command | Pass |
|---|---|---|
| Any `.sh` | `make runcheck scriptcheck` | Each prints a line ending in `parses clean`; needs `shellcheck` (`brew install shellcheck`) |
| Any `.sh`, same as CI | `git ls-files '*.sh' \| xargs shellcheck -x -S warning` | No output |
| `assets/runner.env` | `sh -n assets/runner.env && python3 tests/test_runner_env.py` | `OK` |
| C in `dylib/` | `make all` (needs Dobby: `scripts/setup.sh` fetches it, or see [vendor/README.md](vendor/README.md)) | Builds `out/steambridge.dylib` |
| `dylib/` behavior | `make compatcheck sigcheck anchorcheck` | Exit 0 (anchorcheck reads the installed Steam client, read only) |
| Docs | `LC_ALL=C grep -rnI $'\xe2\x80\x93\\|\xe2\x80\x94' --exclude-dir=.git .` (en and em dash) and check every relative link resolves | No output |

4. Apply to the machine only if asked: `scripts/setup.sh` after `dylib/` changes (full build; the dylib rewrites the installed `run` script from its embedded copy), `scripts/setup.sh --skip-build` for other installer changes, `scripts/apply-game-configs.sh` for `configs/games`.
5. Commit with a clear message. Update `docs/LOG.md` when you measured or decided something.
