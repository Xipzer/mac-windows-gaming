# Troubleshooting

Start with `bash scripts/doctor.sh`. It only reads, prints each problem with the command that fixes it, and exits 1 if it found any.

## Logs

| What | Path |
|---|---|
| Run script, per game | `~/Library/Application Support/Steam/steamapps/compatdata/<appid>/steambridge-run.log` |
| Wine output, per game | `~/Library/Application Support/SteamBridge/launchers/<appid>/steambridge-wine.log` |
| Hook library (inside Steam) | `~/Library/Application Support/SteamBridge/steambridge.log` |
| Installer build | `~/Library/Application Support/SteamBridge/setup/build.log` |
| Valve DLL download | `~/Library/Application Support/SteamBridge/setup/valve-fetch.log` |

Hooks are working when `steambridge.log` contains `install_thread: ready, N/N hooks installed` after Steam starts.

## SteamBridge

| Symptom | Cause | Fix |
|---|---|---|
| Windows games have no Play button, or stop launching after a Steam update | Steam replaced `Info.plist` or the hook signatures do not match the new build | Quit Steam, `scripts/setup.sh --skip-build` |
| `steambridge.log` says `signatures ... resolved, installing nothing` | No signature set for this Steam build yet | `scripts/setup.sh --skip-build` fetches the latest sets. If it still fails, wait for upstream signatures |
| `Application load error 3:0000065432` | Steam DRM found lsteamclient where Valve's `steamclient64.dll` should be | `scripts/setup.sh --skip-build`. If it persists, delete the game's `pfx/drive_c/windows/system32/steamclient64.dll` |
| Blank dialog text; Wine log says `cannot find the FreeType font library` | Wine lost the runner's library path | `scripts/setup.sh --skip-build` |
| Game limited to 1800x1169 | Retina mode off | Remove `STEAMBRIDGE_RETINA=0` from launch options and `steambridge.env` |
| Mouse is offset at native resolution | Wine switched desktop modes mid-session | `STEAMBRIDGE_DESKTOP_MODE=1512x982` (see [CONFIG.md](CONFIG.md#native-resolution)) |
| `Failed to spawn process`, `OS Error 260`, or a launch option is ignored | Written as `VAR=1 %command%` | Write `%command% VAR=1`, or use `steambridge.env` |
| Game hangs before its window appears | msync | `WINEMSYNC=0` |
| 32-bit game deadlocks | WoW64 with msync | The run script already forces `WINEMSYNC=0` for 32-bit exes; check `sync:` in `steambridge-run.log` |
| Dialog: "This game needs its prefix rebuilt" | The prefix was made by a different Wine architecture | Move the prefix aside (`mv pfx pfx.old` inside `compatdata/<appid>`), launch again, copy saves back from `pfx.old`. Agents: ask first |
| Unreal launcher spins at 200% CPU (Dragon Ball) | Launcher stub never starts the game | Launch option `"$HOME/Library/Application Support/SteamBridge/direct-shipping.sh" %command%` |
| "Known issues with graphics driver" box (Unreal) | GPU is not NVIDIA or AMD | Click "No". "Yes" opens a website |
| DXMT shows a black window | Exclusive fullscreen with map flags | Borderless plus `DXMT_CONFIG=d3d11.ignoreMapFlagNoWait=True`, or use D3DMetal |
| Launch seems stuck, nothing on screen | A Steam EULA or Play dialog is behind other windows | Bring Steam to the front |
| Cloud saves missing | Old prefix with the profile named after the Mac user | Launch once; the run script merges and links the profile |
| Mac Steam and the legacy wrapper Steam both running | A `steam://` URL opened the wrapper | Quit the wrapper. Launch with `open -b com.valvesoftware.steam "steam://rungameid/<id>"` |
| Slow for a day after a macOS upgrade | Spotlight reindexing | Wait |
| Nothing Windows runs after a macOS 27 upgrade | Upgrade removed Rosetta 2 | `softwareupdate --install-rosetta --agree-to-license` |
| Want stock Steam back | | `scripts/setup.sh --uninstall` |

## Any route

| Symptom | Cause | Fix |
|---|---|---|
| `INST-14-1627` "The EA app encountered an error" | EA games need the EA App, which fails under free Wine | None free. Paid CrossOver only |
| Multiplayer game will not start or bans you | Kernel anti-cheat | None |
| Slow motion or fast forward | Game speed tied to frame rate | Lock 60 fps |
| Stutter on first play | Shader compilation | Goes away after the first level. To force a rebuild: `rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/d3dm/<GAME>/shaders.cache"` |

## Heroic (Epic, GOG, Amazon)

| Symptom | Cause | Fix |
|---|---|---|
| No Windows runner offered | Runner not downloaded | Settings > Wine Manager > download Game-Porting-Toolkit, set it as default |
| Epic EA game asks for the EA App | EA App block | No free route |

Legacy wrapper problems: [legacy/README.md](../legacy/README.md#troubleshooting).
