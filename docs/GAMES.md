# Games

## Will it run?

Check in this order:

| # | Question | If yes |
|---|---|---|
| 1 | Is there a macOS version? | Run it natively in Mac Steam (see [Native ports](#native-ports)) |
| 2 | Is it published by EA? | Blocked. Needs the EA App, which fails under free Wine. Only paid CrossOver works |
| 3 | Does it use kernel anti-cheat (VAC, EAC, BattlEye, online Denuvo)? | Blocked |
| 4 | DirectX 12? | D3DMetal (default) |
| 5 | DirectX 10 or 11? | Try DXMT and D3DMetal, keep the faster one |
| 6 | Online only? | Expect online features to fail even if the game starts |

Automated check:

```sh
bash scripts/check-compat.sh <appid>        # exit 0 works, 2 caveats, 3 blocked, 1 unknown
bash scripts/check-compat.sh --name "Name"  # finds known native ports by name
```

Unknown games are looked up on ProtonDB. Other sources:

| Source | Use for |
|---|---|
| [AppleGamingWiki](https://www.applegamingwiki.com/wiki/Game_Porting_Toolkit) | Mac ratings, native-port status, per-game tweaks |
| [ProtonDB](https://www.protondb.com) | Linux Wine results; predicts Mac Wine |
| [AreWeAntiCheatYet](https://areweanticheatyet.com) | Anti-cheat status |
| [CrossOver compatibility](https://www.codeweavers.com/compatibility) | Mac Wine results |
| [MacGamingDB](https://macgamingdb.app) | Reports per Apple chip |

Good sign: no kernel anti-cheat, not EA, ProtonDB Gold or Platinum, or AppleGamingWiki "Perfect" or "Playable".

Epic, GOG and Amazon games follow the same rules and run through Heroic with its Game-Porting-Toolkit runner.

## Verified games

M4 Max, macOS 26.6.2, unless noted. Profiles: `configs/games/<appid>.env`.

| Game | App ID | DX | Verdict | Profile |
|---|---|---|---|---|
| Batman: Arkham Knight | 208650 | 11 | Works | DXMT codegen build, AVX off |
| LEGO Star Wars: The Skywalker Saga | 920210 | 11/12 | Works | D3DMetal, `WINEMSYNC=0` |
| Sonic Frontiers | 1237320 | 11 | Works | D3DMetal, dinput8 proxy removes the 60 fps cap |
| Dragon Ball: Sparking! ZERO | 1790600 | 12 | Works, offline only | D3DMetal, `direct-shipping.sh` launch option |
| The Elder Scrolls V: Skyrim | 72850 | 9 | Works (M2 Pro, macOS 27.0.1) | None. 32-bit: needs the 32-bit ntdll detour and DXVK for DX9 |
| Scribblenauts Unlimited | 218680 | 9 | Works (M2 Pro, macOS 27.0.1) | None. 32-bit: needs the 32-bit ntdll detour and the game's own `d3dx9` (unpacked on the second launch) |
| Megabonk | 3405340 | - | Works (M2 Pro, macOS 27.0.1) | None |
| Shape of Dreams | 2444750 | - | Works (M2 Pro, macOS 27.0.1) | None. Froze the whole Mac with about 2 GB disk free; fine with 28 GB |
| Star Wars Jedi: Survivor | 1774580 | 12 | Blocked | EA App (`INST-14-1627`) |
| Need for Speed Heat | 1222680 | 11 | Blocked | EA App |
| Counter-Strike 2 | 730 | 11 | Blocked | VAC |

The four M4 Max profiles also set `STEAMBRIDGE_DESKTOP_MODE=1512x982` for native 3024x1964 on a 14" MacBook Pro.

## Native ports

A real macOS build usually beats the Wine route, even when it runs through Rosetta 2: it draws with Metal directly instead of going through Wine and a DirectX translator.

| Game | Arch on Apple Silicon | Note |
|---|---|---|
| Valheim | arm64 | Official Steam build |
| Batman: Arkham City GOTY | x86_64 (Rosetta 2) | Faster than D3DMetal. Avoid the 32-bit `mac_retail_11` beta branch |
| Middle-earth: Shadow of Mordor | x86_64 (Rosetta 2) | Wine route is unplayable |
| Tomb Raider (2013) | x86_64 (Rosetta 2) | Launch option `-nolauncher` (the launcher is 32-bit). Locked 60 fps |

- Most 2012-2016 ports are x86_64. macOS cannot run 32-bit code, so some old ports or their launchers fail.
- Install native games in Mac Steam as usual. Make sure Properties > Compatibility does not force SteamBridge.

## Per-game notes

Paths below are relative to `compatdata/<appid>/pfx/drive_c/users/steamuser/` unless they start with `~` or `steamapps`. `scripts/apply-game-configs.sh` writes the in-game settings listed here. Benchmark and entry scripts: [tools/bench/README.md](../tools/bench/README.md).

### Batman: Arkham Knight (208650)

- Profile: `STEAMBRIDGE_RENDERER=dxmt`, `STEAMBRIDGE_DXMT=dxmt-codegen`, `DXMT_CONFIG` with vectorized buffer access and no read bounds checks, `ROSETTA_ADVERTISE_AVX=0`.
- Settings files: `steamapps/common/Batman Arkham Knight/BMGame/Config/BmSystemSettings.ini` (`ResX`, `ResY`, `MaxFPS`, `UseVsync`) and `~/Documents/WB Games/Batman Arkham Knight/GFXSettings.BatmanArkhamKnight.xml`. Set to 3024x1964, MaxFPS 1000, V-Sync off.
- Built-in benchmark: Options > PC PERFORMANCE TEST.

### LEGO Star Wars: The Skywalker Saga (920210)

- Profile: D3DMetal with `WINEMSYNC=0`. D3DMetal with msync hangs before the window appears.
- Settings: `AppData/Roaming/Warner Bros. Interactive Entertainment/LEGO Star Wars - The Skywalker Saga/PCCONFIG.TXT` (`ScreenWidth/Height`, `ScreenRefreshRate`, `VerticalSyncMode`). The game had forced 1800x1169 at 60 Hz with V-Sync; now 3024x1964, 120 Hz, V-Sync off.
- Logs harmless 60 s critical-section warnings at boot.

### Sonic Frontiers (1237320)

- Profile: D3DMetal, `WINEDLLOVERRIDES=dinput8=n,b` to load the fps-unlock proxy ([games/sonicfrontiers](../games/sonicfrontiers/README.md)).
- Settings: `AppData/Roaming/SEGA/SonicFrontiers/steam/x64/screen_setting.xml` (`resolutionWidth/Height`, `fullscreenStyle`). It rendered at 1800x1012 and upscaled; now 3024x1701 (16:9 at native width), borderless.
- DXMT shows a black window unless borderless plus `DXMT_CONFIG=d3d11.ignoreMapFlagNoWait=True`, and is slower uncapped. D3DMetal stays.

### Dragon Ball: Sparking! ZERO (1790600)

- Unreal Engine 5, DX12, D3DMetal.
- The Unreal launcher stub spins forever. Set this Steam launch option (a wrapper, so it goes before `%command%`):
  `"$HOME/Library/Application Support/SteamBridge/direct-shipping.sh" %command%`
- A "graphics driver" warning appears (D3DMetal reports an NVIDIA GPU). Click "No".
- Keep the 60 fps cap: game speed is tied to frame rate.
- Settings: `AppData/Local/SparkingZERO/Saved/Config/Windows/GameUserSettings.ini` (`ResolutionSizeX/Y`), now 3024x1964.
- `-dx11` (via `STEAMBRIDGE_ARGS=-dx11`) was slower: 19 fps on D3DMetal, 40 on DXMT, against 41 on DX12.
- Saves are in the game folder (`SaveGame/`), not AppData.

### Cloud saves

Steam syncs Windows cloud saves to `C:\users\steamuser`, but this Wine names the profile after the Mac user. The run script merges the Mac-user profile into `steamuser` and replaces it with a link. The old folder is kept at `compatdata/<appid>/steambridge-profile-backup-<user>`.
