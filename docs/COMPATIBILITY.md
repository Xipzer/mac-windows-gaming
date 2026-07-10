# Compatibility guide

How to decide whether a Windows game will run on the free Apple Silicon stack, and a
table of games verified during setup.

## The decision tree

```
1. Native macOS port exists?  ── yes ──> run NATIVE (see NATIVE-VS-WRAPPER.md)
2. EA-published game?         ── yes ──> BLOCKED on free route (EA App). CrossOver only.
3. Kernel anti-cheat?         ── yes ──> BLOCKED (VAC/EAC/BattlEye).
   (VAC/EAC/BattlEye/Denuvo-online)
4. DirectX 12?                ──────────> D3DMetal renderer
5. DirectX 10/11?             ──────────> D3DMetal (or DXMT / DXVK if glitchy)
6. Online-only?               ──────────> warn: online often broken under Wine
```

Automate it:
```bash
bash scripts/check-compat.sh <steam_app_id>     # 0 works · 2 caveats · 3 blocked · 1 unknown
bash scripts/check-compat.sh --name "Game Name" # best-effort by name
```

## Where to verify (authoritative)

| Source | Use for |
|---|---|
| [AppleGamingWiki](https://www.applegamingwiki.com/wiki/Game_Porting_Toolkit) | Mac/GPTk ratings, native-port status, per-game tweaks |
| [ProtonDB](https://www.protondb.com) | Linux/Wine tier (Platinum/Gold/… ) — predicts Mac Wine |
| [AreWeAntiCheatYet](https://areweanticheatyet.com) | Anti-cheat status (the dealbreaker) |
| [CrossOver compat DB](https://www.codeweavers.com/compatibility) | Mac Wine results (paid, but informative) |
| [MacGamingDB](https://macgamingdb.app) | Per-chip Mac reports |

Green light needs: **no kernel anti-cheat**, **not EA-published** (for free), and a
decent ProtonDB tier (Gold/Platinum) or AppleGamingWiki "Perfect/Playable".

## Games verified during setup (July 2026)

| Game | App ID | DX | Verdict | Notes |
|---|---|---|---|---|
| Dragon Ball: Sparking! ZERO | 1790600 | 12 | ✅ Works (D3DMetal) | Lock 60 FPS (speed tied to FPS). Offline only. No Denuvo/anti-cheat. |
| Sonic Frontiers | 1237320 | 11 | ✅ Likely works | No anti-cheat. |
| LEGO Star Wars: Skywalker Saga | 920210 | 11/12 | ✅ Likely works | — |
| Batman: Arkham Knight | 208650 | 11 | ⚠️ Tune settings | Heavy DX11; check AppleGamingWiki. |
| Star Wars Jedi: Survivor | 1774580 | 12 | ❌ Blocked (free) | EA App required (`INST-14-1627`). Denuvo removed 2024; not the blocker. CrossOver only. |
| Need for Speed Heat | 1222680 | 11 | ❌ Blocked (free) | EA App required. |
| Counter-Strike 2 | 730 | 11 | ❌ Blocked | VAC/kernel anti-cheat. |

Native ports (run NATIVE, not in the wrapper): Valheim, Batman Arkham City, Shadow of
Mordor, Tomb Raider (2013). See `NATIVE-VS-WRAPPER.md`.

## Categories that never work on the free route

- **EA App catalog** — Jedi Survivor/Fallen Order, NFS, Battlefield, Sims 4, Apex, etc.
- **Kernel anti-cheat** — competitive multiplayer (Valorant, CS2, Fortnite, R6 Siege…).
- **Some online-only** — even non-EA games often fail matchmaking under Wine networking.
