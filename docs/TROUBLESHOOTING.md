# Troubleshooting

Every fix below was verified on a real setup.

## NotProton route (default)

| Symptom | Cause | Fix |
|---|---|---|
| Games stop launching after a Steam client update | dylib signatures don't match the new Steam build | `scripts/setup-notproton.sh --skip-build`; consider Steam → Settings → block client updates |
| `Application load error 3:0000065432` | Steam DRM found lsteamclient in place of Valve's `steamclient64.dll` | Re-run `setup-notproton.sh` (restores Valve's DLL + ntdll detour). If it persists, delete the game's `pfx/drive_c/windows/system32/steamclient64.dll` |
| Game's own dialog is a blank box; log says `Wine cannot find the FreeType font library` | SIP strips `DYLD_*` from the `/bin/sh` launcher, so Wine loses the runner's libraries | Fixed in the patch (path baked into the launcher). Re-run `setup-notproton.sh` |
| Every game capped at 1800×1169 (your "looks like" size) | Wine Retina mode off | On by default; check you didn't pass `NOTPROTON_RETINA=0`. Force per game: `%command% NOTPROTON_RETINA=1` |
| `Failed to spawn process` / `OS Error 260` / launch option ignored | Launch option written as `VAR=1 %command%` | Write `%command% VAR=1` |
| Unreal game hangs at 0% CPU after start | msync | Default is `WINEMSYNC=0`; don't force it on |
| UE launcher stub spins at 200% CPU (Dragon Ball) | Launcher exe never hands off | Launch option `"…/notproton/direct-shipping.sh" %command%` |
| "Known issues with graphics driver" box (UE) | GPU isn't NVIDIA/AMD | Click OK; don't press Enter on "Yes" (opens NVIDIA's site) |
| Launch seems stuck, nothing on screen | Steam EULA / Play dialog hidden behind windows | Bring Steam to front and click it |
| Mac Steam and the old wrapper Steam both running, high CPU | A `steam://` URL launched the wrapper | Quit the wrapper; use `open -b com.valvesoftware.steam "steam://…"` |

Logs: [NOTPROTON.md](NOTPROTON.md#logs).

## Any route

| Symptom | Cause | Fix |
|---|---|---|
| `INST-14-1627` "The EA app encountered an error and couldn't finish installing" | EA games (Jedi Survivor, NFS Heat, ...) need the **EA App**, which fails under free Wine. The Origin bypass died with Origin (Apr 2025) | None free. Paid **CrossOver** (14-day trial) is the only known path. Don't sink time into it |
| Multiplayer game won't launch or bans you | Kernel anti-cheat (VAC, EAC, BattlEye; CS2, most competitive shooters) | None. Play something else on Mac |
| Game runs in slow-motion or fast-forward | Engine ties game speed to framerate (e.g. Dragon Ball Sparking! ZERO). Game logic, not performance | **Lock 60 FPS**; don't uncap |
| First-launch stutter | Shader compilation; smooths out after the first level/match | Force a clean recompile: `rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/d3dm/<GAME>/shaders.cache"` |

## Legacy wrapper route

| Symptom | Cause | Fix |
|---|---|---|
| Wrapper keeps re-running the Steam installer | Launch target is still `SteamSetup.exe` | Configure → *Windows app* → `C:\Program Files (x86)\Steam\steam.exe`, or `bash scripts/setup-steam.sh` (rewrites `drive_c/exec*.bat` to `steam.exe -tcp`) |
| `Failed to load steamui.dll` (Steam - Fatal Error) | Self-update blocked, so UI files never downloaded: a `steam.cfg` with `BootStrapperInhibitAll=enable`, or stale/mismatched client (old `steam.exe` vs newer DLLs) | `rm -f "<SteamDir>/steam.cfg"`, delete stale client files (keep `steamapps`/`userdata`), relaunch; Steam re-downloads a matched client set. `scripts/doctor.sh` helps locate the Steam dir |
| `steamwebhelper is not responding` / `CSteamEngine::BMainLoop appears to have stalled` | Old Wine (GPTk 1.1 / Wine 7) can't run Steam's CEF UI | `bash scripts/swap-engine.sh WS12WineSikarugir11.0_1 Steam`, then `rm -rf "<SteamDir>/config/htmlcache" "<SteamDir>/appcache/httpcache"`. Stopgap: the dialog's "Restart Steam with GPU Acceleration disabled" sometimes works |
| `SikarugirSdk.FileUtilsError error 1`; nothing appears after an engine swap | Template too old: Wine 11 needs 1.0.16+, 1.0.11 fails | `bash scripts/update-wrapper.sh Steam` (`swap-engine.sh` does this automatically for Wine 11) |
| `Unexpected Transport Error (0x3008)` | Content-manager IPC handshake fails under Wine | `-tcp` launch flag (setup-steam.sh adds it), clear `appcache`, pick **"VO: Continue Anyway"** once; it reaches login |
| `steam.exe` runs but no login screen | Webhelper failed to spawn (0 `steamwebhelper` processes) | Wait 30-40s on first run; check `pgrep -fl steamwebhelper \| wc -l`; if persistent, engine swap (above) |
| Pixelated / non-Retina | Retina mode off in the prefix | `reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /d 'Y'` |
| Steam's "NON-STEAM" shows ~200 GB | Wine's fake `C:` maps your whole Mac disk; Steam's `C:` size/free mirrors it | Nothing to clean; not wasted space |
| Steam and macOS Storage numbers disagree | Both cache and refresh lazily; a **ghost entry** (appmanifest left, files deleted) inflates Steam's total with 0 bytes on disk | Trust `diskutil info / \| grep -E "Free Space\|Total Space"` and `du -sh ~/Applications/Sikarugir/Steam.app`. Clear a ghost by uninstalling the game in Steam (removes the appmanifest) |

### Rolling back

Destructive helpers make timestamped backups next to what they change (`wine.backup-*`, `external.bak-*`, `wine.v0.74-backup`, ...). Undo an engine swap:

```bash
rm -rf "<wrapper>/Contents/SharedSupport/wine"
mv "<wrapper>/Contents/SharedSupport/wine.backup-<ts>" "<wrapper>/Contents/SharedSupport/wine"
```
