# Troubleshooting

Start with `bash scripts/doctor.sh` (read-only; exits 1 and names the fix for each issue).

## Logs

| What | Path |
|---|---|
| Run script, per game | `~/Library/Application Support/Steam/steamapps/compatdata/<appid>/steambridge-run.log` |
| Wine output, per game | `~/Library/Application Support/SteamBridge/launchers/<appid>/steambridge-wine.log` |
| Hook library (Steam side) | `~/Library/Application Support/SteamBridge/steambridge.log` |
| Installer | `~/Library/Application Support/SteamBridge/setup/build.log` |

## SteamBridge (Mac Steam)

| Symptom | Cause | Fix |
|---|---|---|
| Games stop launching after a Steam client update | Hook signatures don't match the new Steam build, or the update replaced `Info.plist` | Quit Steam, `scripts/setup.sh --skip-build` |
| `Application load error 3:0000065432` | Steam DRM found lsteamclient in place of Valve's `steamclient64.dll` | `scripts/setup.sh --skip-build` (restores Valve's DLL + ntdll detour). If it persists, delete the game's `pfx/drive_c/windows/system32/steamclient64.dll` |
| Game dialog is a blank box; Wine log says `cannot find the FreeType font library` | SIP strips `DYLD_*` from `/bin/sh`, so Wine loses the runner's libraries | Library path is baked into the launcher; re-run `scripts/setup.sh --skip-build` |
| Every game capped at 1800x1169 | Retina mode off | Default is on. Check `STEAMBRIDGE_RETINA=0` isn't set in launch options or `steambridge.env` |
| Mouse offset after choosing native res in game | Wine switched desktop modes mid-session | `STEAMBRIDGE_DESKTOP_MODE=1512x982` in `steambridge.env` ([BENCHMARKS.md](BENCHMARKS.md#native-resolution-fix)) |
| `Failed to spawn process` / `OS Error 260` / launch option ignored | Written as `VAR=1 %command%` | Write `%command% VAR=1`, or put it in `steambridge.env` |
| Game hangs before its window appears (LEGO, some Unreal games) | msync | `WINEMSYNC=0` in `steambridge.env` |
| 32-bit game deadlocks | WoW64 + msync | Run script forces `WINEMSYNC=0` for 32-bit exes; check `steambridge-run.log` for `sync:` |
| UE launcher stub spins at 200% CPU (Dragon Ball) | Launcher never hands off | Launch option `"$HOME/Library/Application Support/SteamBridge/direct-shipping.sh" %command%` |
| "Known issues with graphics driver" box (UE) | GPU isn't NVIDIA/AMD | Click "No"/OK. "Yes" opens a website |
| DXMT: black window (Sonic Frontiers) | Exclusive fullscreen + map flags | Borderless + `DXMT_CONFIG=d3d11.ignoreMapFlagNoWait=True`, or stay on D3DMetal |
| Launch seems stuck, nothing on screen | Steam EULA / Play dialog behind other windows | Bring Steam to front and click it |
| Cloud saves missing in game | Wine profile named after the Mac user, not `steamuser` | Fixed in the run script (merges and links the profile). Backup: `compatdata/<appid>/steambridge-profile-backup-<user>` |
| Mac Steam and the legacy wrapper Steam both running, high CPU | A `steam://` URL launched the wrapper | Quit the wrapper; use `open -b com.valvesoftware.steam "steam://rungameid/<id>"` |
| Want stock Steam back | | `scripts/setup.sh --uninstall` (restores the backup in `SteamBridge/setup/backup-*`) |

## Any route (Steam or Heroic)

| Symptom | Cause | Fix |
|---|---|---|
| `INST-14-1627` "The EA app encountered an error" | EA games need the EA App, which fails under free Wine. The Origin bypass died with Origin (Apr 2025) | None free. Paid CrossOver only. Don't sink time into it |
| Multiplayer game won't launch or bans you | Kernel anti-cheat (VAC, EAC, BattlEye) | None |
| Slow motion or fast forward | Game speed tied to framerate (Dragon Ball Sparking! ZERO) | Lock 60 FPS |
| First-launch stutter | Shader compilation | Smooths out after the first level. Force a recompile: `rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/d3dm/<GAME>/shaders.cache"` |

## Heroic (Epic/GOG/Amazon)

| Symptom | Cause | Fix |
|---|---|---|
| No Windows runner offered | GPTk runner not downloaded | Settings > Wine Manager > download Game-Porting-Toolkit, set as default |
| EA game from Epic asks for the EA App | Same EA App block | No free route |

## Legacy wrapper route

| Symptom | Cause | Fix |
|---|---|---|
| Wrapper keeps re-running the Steam installer | Launch target is `SteamSetup.exe` | `bash legacy/setup-steam.sh` (rewrites `drive_c/exec*.bat` to `steam.exe -tcp`) |
| `Failed to load steamui.dll` | Self-update blocked (`steam.cfg` with `BootStrapperInhibitAll=enable`) or mismatched client files | `rm -f "<SteamDir>/steam.cfg"`, delete stale client files (keep `steamapps`/`userdata`), relaunch |
| `steamwebhelper is not responding` / `BMainLoop appears to have stalled` | Old Wine (GPTk 1.1 / Wine 7) can't run Steam's CEF UI | `bash legacy/swap-engine.sh WS12WineSikarugir11.0_1 Steam`, then clear `config/htmlcache` and `appcache/httpcache` |
| `SikarugirSdk.FileUtilsError error 1` after an engine swap | Template too old (Wine 11 needs 1.0.16+) | `bash legacy/update-wrapper.sh Steam` |
| `Unexpected Transport Error (0x3008)` | IPC handshake fails under Wine | `-tcp` (setup-steam.sh adds it), clear `appcache`, pick "VO: Continue Anyway" once |
| `steam.exe` runs, no login screen | Webhelper didn't spawn | Wait 30-40 s on first run; `pgrep -fl steamwebhelper`; else engine swap |
| Pixelated / non-Retina | Retina off in the prefix | `reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /d 'Y'` |
| Steam shows ~200 GB under NON-STEAM | Wine's `C:` maps the whole Mac disk | Nothing to clean |
| Steam and macOS Storage disagree | Lazy caches; a ghost appmanifest inflates Steam's total | Trust `diskutil info /`. Uninstall the ghost game in Steam |

Roll back an engine swap:

```bash
rm -rf "<wrapper>/Contents/SharedSupport/wine"
mv "<wrapper>/Contents/SharedSupport/wine.backup-<ts>" "<wrapper>/Contents/SharedSupport/wine"
```
