# AGENTS.md

How to set up, repair and tune Windows gaming on this Mac with this repo.

## Prime directives

1. **Never delete `steamapps/` or any `steamapps/common/<game>` or `compatdata/<appid>`.** User installs and saves.
   Cache dirs (`htmlcache`, `appcache/httpcache`, `dumps`) are fine to clear.
2. **EA App games are a hard stop.** Jedi Survivor, NFS Heat, ... fail under free Wine (`INST-14-1627`). Only paid CrossOver works. Tell the user; don't try.
3. **Kernel anti-cheat is a hard stop.** CS2 (VAC), EAC, BattlEye. Don't try.
4. **Prefer native macOS ports.** Arm64 or 64-bit Metal builds usually win, even under Rosetta 2 (`check-compat.sh --name`).
5. **Quit Steam before editing `config.vdf` / `localconfig.vdf`.** Steam rewrites them on exit.
6. **Launch options go after `%command%`** (`%command% STEAMBRIDGE_RETINA=0`). `VAR=1 %command%` fails with `OS Error 260`. Prefer `compatdata/<appid>/steambridge.env`.
7. **Keep Valve's `steamclient64.dll` in the bridge.** Never replace it with lsteamclient: Steam DRM checks it (`3:0000065432`). The ntdll detour does the rerouting; `.valve` copies sit beside it.
8. **Never commit Apple binaries** (D3DMetal, GPTk). They are fetched on the machine.
9. **Don't launch games, restart Steam or run setup scripts unless asked.** Use `scripts/doctor.sh` (read-only) to inspect.
10. Don't log into Steam/Epic/GOG for the user; never handle credentials.

## Workflow

```
1. state       -> bash scripts/doctor.sh                  (read-only, names the fix)
2. install     -> ./install.sh                            (prereqs, Steam, Heroic, setup.sh, game profiles)
3. Steam stack -> scripts/setup.sh                        (idempotent; quits Steam first)
4. new game    -> bash scripts/check-compat.sh <appid>    BEFORE installing
5. tune        -> compatdata/<appid>/steambridge.env, then save to configs/games/<appid>.env
6. Steam updated, games won't launch -> scripts/setup.sh --skip-build
```

## Paths

| What | Path |
|---|---|
| Support dir | `~/Library/Application Support/SteamBridge` (runners, bridge, signatures, launchers, helpers) |
| Runner | `SteamBridge/runners/sikarugir-11` (`current` symlink) |
| Compat tool | `~/Library/Application Support/Steam/compatibilitytools.d/steambridge` (run script = `dylib/feats/compat_run.sh`) |
| Injected dylib | `/Applications/Steam.app/Contents/MacOS/steambridge.dylib` (`LSEnvironment:DYLD_INSERT_LIBRARIES`) |
| Steam.app backup | `SteamBridge/setup/backup-*/` |
| Per-game profile | `steamapps/compatdata/<appid>/steambridge.env`; tuned copies in `configs/games/` |
| Logs | `compatdata/<appid>/steambridge-run.log`, `SteamBridge/launchers/<appid>/steambridge-wine.log`, `SteamBridge/steambridge.log` |

## Docs

| Doc | Contents |
|---|---|
| [docs/LOG.md](docs/LOG.md) | Everything tried, measured and decided. Read before changing tuning |
| [docs/GAMES.md](docs/GAMES.md) | Per-game entry scripts, routes, settings files |
| [docs/BENCHMARKS.md](docs/BENCHMARKS.md) | All numbers |
| [docs/CONFIG.md](docs/CONFIG.md) | Every `steambridge.env` variable |
| [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) | Decision tree, verified games |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptom, cause, fix |
| [docs/ENGINES.md](docs/ENGINES.md) | Engines, templates, renderers |
| [tools/bench/](tools/bench/README.md) | Benchmark and input automation |
| [legacy/](legacy/README.md) | Old Windows-Steam wrapper route |

## Benchmarking (`tools/bench`)

- The screen must be unlocked and awake: screenshots, OCR and synthetic input fail on a locked screen.
- **Never raise a game window with AppleScript while it is in menus** (it bounces the game, e.g. to save select).
- Inputs are real HID key down/up with a hold (`hold.py`, `keyhold.py`); games poll keys per frame.
- Verify menu state by OCR (`ocr.py`) or highlight (`hl.py`), never by blind key counts.
- fps: Metal HUD (`MTL_HUD_ENABLED=1`) read by `hudfps.py`. Interleave A/B runs in one session; record in BENCHMARKS.md and LOG.md.

## Other stores and routes

- Epic/GOG/Amazon: Heroic (`brew install --cask heroic`), Game-Porting-Toolkit runner from its Wine Manager.
- Legacy wrapper: `legacy/`. Don't run it alongside Mac Steam; launch Mac Steam games with
  `open -b com.valvesoftware.steam "steam://rungameid/<id>"`.
