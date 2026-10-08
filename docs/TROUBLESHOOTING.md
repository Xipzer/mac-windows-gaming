# Troubleshooting

Every problem below was hit for real during setup, with the fix that actually worked.
Ordered roughly in the sequence you encounter them.

## Steam wrapper

### Wrapper keeps re-running the Steam installer
**Cause:** the wrapper's launch target is still `SteamSetup.exe`.
**Fix:** point it at the installed `steam.exe`. Either in Sikarugir Configure →
*Windows app* → `C:\Program Files (x86)\Steam\steam.exe`, or run:
```bash
bash scripts/setup-steam.sh   # rewrites drive_c/exec*.bat to steam.exe -tcp
```

### `Failed to load steamui.dll` (Steam - Fatal Error)
**Cause:** Steam's self-update was blocked, so the UI files never downloaded. Usually
caused by a `steam.cfg` with `BootStrapperInhibitAll=enable`, or a stale/mismatched
client (old `steam.exe` vs newer DLLs).
**Fix:** remove any such `steam.cfg`, delete stale client files, let Steam self-update:
```bash
sd="$(bash scripts/doctor.sh >/dev/null; echo)"  # or find your Steam dir
# remove blocking cfg and stale client, keep steamapps/userdata:
rm -f "<SteamDir>/steam.cfg"
# relaunch; Steam re-downloads a matched client set.
```

### `steamwebhelper is not responding` / `CSteamEngine::BMainLoop appears to have stalled`
**Cause:** old Wine (GPTk 1.1 / Wine 7) can't run Steam's Chromium (CEF) UI.
**Fix:** switch to a modern engine:
```bash
bash scripts/swap-engine.sh WS12WineSikarugir11.0_1 Steam
```
Then clear caches and relaunch:
```bash
rm -rf "<SteamDir>/config/htmlcache" "<SteamDir>/appcache/httpcache"
```
As a stopgap the dialog's *"Restart Steam with GPU Acceleration disabled"* sometimes
works, but the real fix is the engine swap.

### `SikarugirSdk.FileUtilsError error 1` — wrapper won't launch after an engine swap
**Cause:** the wrapper template is too old for the engine. Wine 11 engines need template
1.0.16+; template 1.0.11 fails like this. Nothing appears, and Steam never starts.
**Fix:**
```bash
bash scripts/update-wrapper.sh Steam
```
(`swap-engine.sh` does this automatically when switching to a Wine 11 engine.)

### `Unexpected Transport Error (0x3008)`
**Cause:** Steam's content-manager IPC handshake fails under Wine.
**Fix:** add the `-tcp` launch flag (setup-steam.sh does this), clear `appcache`, and on
the dialog pick **"VO: Continue Anyway"** once. It reaches the login screen.

### Login screen never appears but `steam.exe` is running
The webhelper (0 `steamwebhelper` processes) failed to spawn. Wait 30-40s on first run.
If persistent → engine swap (above). Verify processes:
```bash
pgrep -fl steamwebhelper | wc -l
```

## EA games

### `INST-14-1627` — "The EA app encountered an error and couldn't finish installing"
**Cause:** EA-published games (Jedi Survivor, NFS Heat, …) require the **EA App**, which
does not work under free Wine on Mac. The old Origin bypass died when EA shut Origin down
(Apr 2025).
**Fix:** none that's free. Paid **CrossOver** is the only known working path (14-day free
trial exists). Don't sink time into it on the free stack.

## Anti-cheat

### Multiplayer game refuses to launch or bans you
Kernel anti-cheat (VAC, EAC, BattlEye) is undefeated by translation layers. CS2, most
competitive shooters. There is no fix — play something else on Mac.

## Performance / rendering

### Game runs in slow-motion or fast-forward
Some engines tie game speed to framerate (e.g. Dragon Ball Sparking! ZERO). **Lock 60 FPS**
and don't uncap. This is a game-logic issue, not a performance one.

### First-launch stutter
Shader compilation. It smooths out after the first level/match. To force a clean recompile:
```bash
rm -rf "$(getconf DARWIN_USER_CACHE_DIR)/d3dm/<GAME>/shaders.cache"
```

### Pixelated / non-Retina
Enable Retina mode in the Wine prefix:
```
reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /d 'Y'
```

## Storage confusion

### Steam's "NON-STEAM" shows ~200 GB
That's your **real macOS files** seen through Wine's fake `C:` (which maps to your whole
Mac disk). Not wasted space, nothing to clean. Steam's `C:` "size/free" mirrors your Mac
disk, not a real Windows drive.

### Numbers don't add up between Steam and macOS Storage
Both panels **cache** and refresh lazily; you catch them mid-update during installs/
deletes. And a **ghost entry** (game with an appmanifest but files already deleted) can
inflate Steam's total while contributing 0 bytes on disk. The authoritative numbers:
```bash
diskutil info / | grep -E "Free Space|Total Space"   # real free space
du -sh ~/Applications/Sikarugir/Steam.app             # real wrapper size
```
Clear a ghost by uninstalling the game properly in Steam (removes the appmanifest).

## Recovery

Every destructive helper makes a timestamped backup next to what it changed
(`wine.backup-*`, `external.bak-*`, `wine.v0.74-backup`, …). To roll back an engine swap:
```bash
rm -rf "<wrapper>/Contents/SharedSupport/wine"
mv "<wrapper>/Contents/SharedSupport/wine.backup-<ts>" "<wrapper>/Contents/SharedSupport/wine"
```

## NotProton route (native Steam)

| Symptom | Cause | Fix |
|---|---|---|
| Games stop launching after a Steam client update | dylib signatures don't match the new Steam build | `scripts/setup-notproton.sh --skip-build`; consider Steam → Settings → block client updates |
| `Application load error 3:0000065432` | Steam DRM found lsteamclient in place of Valve's `steamclient64.dll` | Re-run `setup-notproton.sh` (restores Valve's DLL + ntdll detour). Delete the game's `pfx/drive_c/windows/system32/steamclient64.dll` if it persists |
| Game's own dialog is a blank box, log says `Wine cannot find the FreeType font library` | SIP strips `DYLD_*` from the `/bin/sh` launcher, so Wine loses the runner's libraries | Fixed in the patch (path baked into the launcher). Re-run `setup-notproton.sh` |
| Every game capped at 1800×1169 (your "looks like" size) | Wine Retina mode off | On by default now; per game `%command% NOTPROTON_RETINA=1` |
| `Failed to spawn process` / `OS Error 260` | Launch option written as `VAR=1 %command%` | Write `%command% VAR=1` |
| Unreal game hangs at 0% CPU after start | msync | Default is `WINEMSYNC=0`; don't force it on |
| UE launcher stub spins at 200% CPU (Dragon Ball) | launcher exe never hands off | Launch option `"…/notproton/direct-shipping.sh" %command%` |
| "Known issues with graphics driver" box (UE) | GPU isn't NVIDIA/AMD | Click OK; don't press Enter on "Yes" (opens NVIDIA's site) |
| Launch seems stuck, nothing on screen | Steam EULA / Play dialog hidden behind windows | Bring Steam to front and click it |
| Mac Steam and the old wrapper Steam both running, high CPU | a `steam://` URL launched the wrapper | Quit the wrapper; use `open -b com.valvesoftware.steam "steam://…"` |
