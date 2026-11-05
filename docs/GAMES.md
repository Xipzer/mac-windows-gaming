# Per-game notes: getting into gameplay and measuring it

All scripts are in `tools/bench/`. Confirm keys differ per game. Inputs are posted as real HID key down/up
(`hold.py`, `keyhold.py`). Never raise a game window with AppleScript while it is in menus.
Universal fps source: Metal HUD (`MTL_HUD_ENABLED=1` in the game's `steambridge.env`), read by OCR (`hudfps.py`).
`route.sh <label> <exe> <walk-script>` walks a fixed path and reports avg / p10 / min fps, GPU %, game CPU %.

## Batman: Arkham Knight (208650)
- Benchmark: Options > PC PERFORMANCE TEST. `relaunch.sh` + `bench2.sh` (OCR of min/max/avg). Confirm = Enter.
- Settings: DXMT (`dxmt-codegen` with vectorized buffer access, no read bounds checks), AVX off, native 3024x1964 via
  `STEAMBRIDGE_DESKTOP_MODE=1512x982`.

## LEGO Star Wars: The Skywalker Saga (920210)
- Entry: `lego_enter.sh` (confirm = Space): seizure warning, Press any key, CONTINUE GAME, Confirm Load, Autosave notice.
  Loads the cloud save into Mos Eisley, Tatooine (about 90 s, most of it the game's own loading).
- Route: `walk_lego.sh` (W/D/S/A loop around the taxi rank, 48 s).
- Resolution, refresh cap and vsync live in `AppData/Roaming/Warner Bros. Interactive Entertainment/LEGO Star Wars -
  The Skywalker Saga/PCCONFIG.TXT` (`ScreenWidth/Height`, `ScreenRefreshRate`, `VerticalSyncMode`). It was 1800x1169 at 60 Hz.
- Results: at 1800x1169 D3DMetal + msync off avg 136-154, DXMT 129-142. At native 3024x1964: avg 72-78, GPU 95-100%.
  D3DMetal + msync hangs before the window appears. Config: `STEAMBRIDGE_RENDERER=d3dmetal`, `WINEMSYNC=0`, desktop 1512x982.

## Sonic Frontiers (1237320)
- Entry: `sonic_enter.sh` (confirm = Space): Continue > AUTO save > Kronos Island (about 40 s).
- Route: `walk_sonic.sh`. Escape does not open a menu in gameplay with synthetic input.
- Internal render resolution lives in `AppData/Roaming/SEGA/SonicFrontiers/steam/x64/screen_setting.xml`
  (`resolutionWidth/Height`). It was 1800x1012 (blurry, upscaled). Set to 3024x1701 (native width, 16:9) and
  `fullscreenStyle="1"` (borderless). The Metal HUD reports the drawable size, not the game's internal resolution.
- Result at native 3024x1701: 56-57 fps (game's own 60 cap), GPU 13.1 ms per frame (~75% busy).
- DXMT works with borderless + `DXMT_CONFIG=d3d11.ignoreMapFlagNoWait=True` (black screen otherwise). Same fps under the cap;
  D3DMetal stays default.
- 60 fps cap removed in memory by `games/sonicfrontiers` (dinput8 proxy, `WINEDLLOVERRIDES=dinput8=n,b`): avg 69-82 uncapped.

## Dragon Ball: Sparking! ZERO (1790600)
- UE5 DX12, D3DMetal. A small "graphics driver" warning dialog appears under D3DMetal (it reports an NVIDIA GPU):
  `dbz_title.sh` finds the 500x500 window and clicks "No"; it then waits for "Start Game". About 45 s.
- Resolution in `AppData/Local/SparkingZERO/Saved/Config/Windows/GameUserSettings.ini` (`ResolutionSizeX/Y`), now 3024x1964.
- Title screen at native (GPU-bound, ~100%): DX12 D3DMetal 41 fps; `-dx11` + DXMT 40; `-dx11` + D3DMetal 19. Stays DX12.
  Exclusive vs borderless fullscreen: no difference (presents "Composited" either way). `STEAMBRIDGE_ARGS=-dx11` passes args.
- Saves are in the game folder (`SaveGame/`), not AppData, and were already syncing.
- Gameplay route: not scripted yet (needs a match setup through menus).

## Cloud saves fix (Oct 20 2026)
Steam writes Windows cloud saves to `C:\users\steamuser`, but this Wine names the profile after the Mac user
(`C:\users\xipz`). Games read the Mac-user profile and saw no saves. The run script now merges that profile into
`steamuser` and replaces it with a link (backup kept at `compatdata/<appid>/steambridge-profile-backup-<user>`).
Verified: Sonic shows Continue (AUTO save 2026/3/23), LEGO shows CONTINUE GAME (Mos Eisley).
