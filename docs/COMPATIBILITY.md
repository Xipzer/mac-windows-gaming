# Compatibility

Will a Windows game run through SteamBridge (native Mac Steam + Wine 11 + D3DMetal/DXMT)?

## Decision tree

```
1. Native macOS port exists?  -- yes --> run NATIVE in Mac Steam (NATIVE-VS-WRAPPER.md)
2. EA-published game?         -- yes --> BLOCKED on the free route (EA App). Paid CrossOver only.
3. Kernel anti-cheat?         -- yes --> BLOCKED (VAC/EAC/BattlEye/online Denuvo).
4. DirectX 12?                --------> D3DMetal (default renderer)
5. DirectX 10/11?             --------> D3DMetal first; DXMT often faster (STEAMBRIDGE_RENDERER=dxmt); DXVK fallback
6. Online-only?               --------> warn: online often broken under Wine even if the game runs
```

Automated:

```bash
bash scripts/check-compat.sh <steam_appid>      # exit 0 works, 2 caveats, 3 blocked, 1 unknown
bash scripts/check-compat.sh --name "Game Name"  # best-effort by name (native ports)
```

Epic/GOG/Amazon games: same rules, run through Heroic with its Game-Porting-Toolkit runner.

## Never works on the free route

| Category | Examples |
|---|---|
| EA App catalog | Jedi Survivor/Fallen Order, NFS, Battlefield, Sims 4, Apex |
| Kernel anti-cheat | Valorant, CS2, Fortnite, R6 Siege, most competitive multiplayer |
| Some online-only | Non-EA games often fail matchmaking under Wine networking |

## Verified games (M4 Max, macOS 26.6.2)

| Game | App ID | DX | Verdict | Notes |
|---|---|---|---|---|
| Batman: Arkham Knight | 208650 | 11 | Works | DXMT (dxmt-codegen), AVX off. Native 3024x1964 avg 74 ([BENCHMARKS.md](BENCHMARKS.md)) |
| LEGO Star Wars: Skywalker Saga | 920210 | 11/12 | Works | D3DMetal, `WINEMSYNC=0` (msync hangs). Native avg 72-78 |
| Sonic Frontiers | 1237320 | 11 | Works | D3DMetal. DXMT black screen unless borderless. dinput8 proxy removes the 60 fps cap |
| Dragon Ball: Sparking! ZERO | 1790600 | 12 | Works | D3DMetal. `direct-shipping.sh` launch option. Lock 60 FPS (speed tied to FPS). Offline only |
| Star Wars Jedi: Survivor | 1774580 | 12 | Blocked | EA App required (`INST-14-1627`). Denuvo removed 2024; not the blocker |
| Need for Speed Heat | 1222680 | 11 | Blocked | EA App required |
| Counter-Strike 2 | 730 | 11 | Blocked | VAC/kernel anti-cheat |

Tuned profiles: `configs/games/<appid>.env`. Per-game procedures: [GAMES.md](GAMES.md).
Native ports (run in Mac Steam, not through Wine): Valheim, Batman: Arkham City, Shadow of Mordor, Tomb Raider (2013).

## Where to verify

| Source | Use for |
|---|---|
| [AppleGamingWiki](https://www.applegamingwiki.com/wiki/Game_Porting_Toolkit) | Mac/GPTk ratings, native-port status, per-game tweaks |
| [ProtonDB](https://www.protondb.com) | Linux/Wine tier, predicts Mac Wine |
| [AreWeAntiCheatYet](https://areweanticheatyet.com) | Anti-cheat status (the dealbreaker) |
| [CrossOver compat DB](https://www.codeweavers.com/compatibility) | Mac Wine results |
| [MacGamingDB](https://macgamingdb.app) | Per-chip Mac reports |

Green light: no kernel anti-cheat, not EA-published, ProtonDB Gold/Platinum or AppleGamingWiki "Perfect/Playable".
