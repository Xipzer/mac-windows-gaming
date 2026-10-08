# Compatibility

Will a Windows game run on the free stack (native Mac Steam + NotProton)?

## Decision tree

```
1. Native macOS port exists?  ── yes ──> run NATIVE in Mac Steam (see NATIVE-VS-WRAPPER.md)
2. EA-published game?         ── yes ──> BLOCKED on free route (EA App). CrossOver only (trial exists).
3. Kernel anti-cheat?         ── yes ──> BLOCKED (VAC/EAC/BattlEye/Denuvo-online).
4. DirectX 12?                ──────────> D3DMetal renderer
5. DirectX 10/11?             ──────────> D3DMetal first; DXMT if glitchy; DXVK as fallback
6. Online-only?               ──────────> warn: online often broken under Wine even if the game runs
```

Automated:

```bash
bash scripts/check-compat.sh <steam_app_id>     # 0 works · 2 caveats · 3 blocked · 1 unknown
bash scripts/check-compat.sh --name "Game Name" # best-effort by name
```

## Never works on the free route

| Category | Examples |
|---|---|
| EA App catalog | Jedi Survivor/Fallen Order, NFS, Battlefield, Sims 4, Apex |
| Kernel anti-cheat | Valorant, CS2, Fortnite, R6 Siege, most competitive multiplayer |
| Some online-only | Even non-EA games often fail matchmaking under Wine networking |

## Verified games

| Game | App ID | DX | Verdict | Notes |
|---|---|---|---|---|
| Dragon Ball: Sparking! ZERO | 1790600 | 12 | ✅ Works (D3DMetal) | Lock 60 FPS (speed tied to FPS). Offline only. No Denuvo/anti-cheat. Needs `direct-shipping.sh` ([NOTPROTON.md](NOTPROTON.md)). |
| Sonic Frontiers | 1237320 | 11 | ✅ Plays | No anti-cheat. |
| LEGO Star Wars: Skywalker Saga | 920210 | 11/12 | ✅ Plays | - |
| Batman: Arkham Knight | 208650 | 11 | ✅ Plays | Heavy DX11. High: avg 92 fps at 1800×1169 ([BENCHMARKS.md](BENCHMARKS.md)). |
| Star Wars Jedi: Survivor | 1774580 | 12 | ❌ Blocked (free) | EA App required (`INST-14-1627`). Denuvo removed 2024; not the blocker. CrossOver only. |
| Need for Speed Heat | 1222680 | 11 | ❌ Blocked (free) | EA App required. |
| Counter-Strike 2 | 730 | 11 | ❌ Blocked | VAC/kernel anti-cheat. |

First pass July 2026 (Sonic, LEGO rated "likely works", Arkham Knight "tune settings"); play results October 2026 on NotProton.
Native ports (run in Mac Steam, not through Wine): Valheim, Batman: Arkham City, Shadow of Mordor, Tomb Raider (2013). See [NATIVE-VS-WRAPPER.md](NATIVE-VS-WRAPPER.md).

## Where to verify

| Source | Use for |
|---|---|
| [AppleGamingWiki](https://www.applegamingwiki.com/wiki/Game_Porting_Toolkit) | Mac/GPTk ratings, native-port status, per-game tweaks |
| [ProtonDB](https://www.protondb.com) | Linux/Wine tier (Platinum/Gold/...), predicts Mac Wine |
| [AreWeAntiCheatYet](https://areweanticheatyet.com) | Anti-cheat status (the dealbreaker) |
| [CrossOver compat DB](https://www.codeweavers.com/compatibility) | Mac Wine results (paid, but informative) |
| [MacGamingDB](https://macgamingdb.app) | Per-chip Mac reports |

Green light: no kernel anti-cheat, not EA-published, and ProtonDB Gold/Platinum or AppleGamingWiki "Perfect/Playable".
