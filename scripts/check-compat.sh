#!/usr/bin/env bash
# check-compat.sh - will this game run on Apple Silicon via the free stack?
#
# Queries ProtonDB and applies dealbreaker rules (kernel anti-cheat, EA App, native ports).
# Advisory only: confirm on AppleGamingWiki. Decision tree: docs/COMPATIBILITY.md.
#
# Usage:
#   ./check-compat.sh <steam_app_id>
#   ./check-compat.sh --name "Dragon Ball Sparking Zero"   # best-effort, prints links
#
# Exit codes: 0 likely-works, 2 caveated, 3 blocked, 1 unknown/error

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"

# Curated dealbreakers / notes keyed by steam appid (things public APIs won't tell you cleanly).
# Format: appid|verdict|note
KNOWN=$(cat <<'EOF'
1774580|BLOCKED_EA|Star Wars Jedi: Survivor - EA game. Needs the EA App, which does NOT work under free Wine (INST-14-1627). Denuvo removed 2024, no anti-cheat. Only path: paid CrossOver.
1222680|BLOCKED_EA|Need for Speed Heat - EA game. EA App required; no free route. Use CrossOver.
730|BLOCKED_AC|Counter-Strike 2 - VAC + kernel-adjacent anti-cheat. Does not run under Wine on Mac.
1790600|OK|Dragon Ball Sparking! ZERO - DX12, no Denuvo, no anti-cheat. Works via D3DMetal. Lock 60 FPS (game speed tied to FPS). Offline only (online broken under Wine).
1237320|OK|Sonic Frontiers - no anti-cheat. Generally works via D3DMetal.
920210|OK|LEGO Star Wars: The Skywalker Saga - works via D3DMetal.
208650|NATIVE|Batman: Arkham Knight - heavy DX11; check AppleGamingWiki, D3DMetal works but tune settings.
EOF
)

# Games with official native macOS ports - prefer native over translation.
NATIVE_PORTS=$(cat <<'EOF'
Batman: Arkham City|64-bit Metal (Rosetta). Run NATIVE - beats D3DMetal.
Middle-earth: Shadow of Mordor|64-bit Metal (Rosetta). Run NATIVE - Wine route is unplayable.
Tomb Raider|64-bit Metal (Rosetta). Run NATIVE; add Steam launch option -nolauncher (32-bit launcher is broken).
Valheim|Apple Silicon NATIVE build. Run NATIVE - no Rosetta, no Wine.
EOF
)

verdict_ok()      { printf '%s\n' "${C_GRN}${C_B}LIKELY WORKS${C_RESET} - $*"; exit 0; }
verdict_caveat()  { printf '%s\n' "${C_YEL}${C_B}WORKS WITH CAVEATS${C_RESET} - $*"; exit 2; }
verdict_blocked() { printf '%s\n' "${C_RED}${C_B}BLOCKED (free route)${C_RESET} - $*"; exit 3; }
verdict_native()  { printf '%s\n' "${C_BLU}${C_B}RUN NATIVE INSTEAD${C_RESET} - $*"; exit 0; }

links() {
  local id="$1"
  cat <<EOF
${C_DIM}Verify:
  ProtonDB:        https://www.protondb.com/app/${id}
  AppleGamingWiki: https://www.applegamingwiki.com/wiki/Game_Porting_Toolkit
  AreWeAntiCheat:  https://areweanticheatyet.com
  CrossOver DB:    https://www.codeweavers.com/compatibility${C_RESET}
EOF
}

check_by_id() {
  local id="$1" row
  row="$(printf '%s\n' "$KNOWN" | awk -F'|' -v id="$id" '$1==id{print; exit}')"
  if [[ -n "$row" ]]; then
    local v note; v="$(cut -d'|' -f2 <<<"$row")"; note="$(cut -d'|' -f3- <<<"$row")"
    case "$v" in
      OK)         links "$id"; verdict_ok "$note";;
      NATIVE)     links "$id"; verdict_caveat "$note";;
      BLOCKED_EA) links "$id"; verdict_blocked "$note";;
      BLOCKED_AC) links "$id"; verdict_blocked "$note";;
    esac
  fi

  # Fall back to ProtonDB tier as a heuristic
  info "No curated entry - querying ProtonDB for appid ${id}…"
  local tier
  tier="$(curl -fsSL "https://www.protondb.com/api/v1/reports/summaries/${id}.json" 2>/dev/null \
          | sed -n 's/.*"tier": *"\([^"]*\)".*/\1/p' | head -1 || true)"
  links "$id"
  case "$tier" in
    platinum|gold) verdict_ok "ProtonDB tier: ${tier}. Good sign. Confirm no kernel anti-cheat / EA App.";;
    silver)        verdict_caveat "ProtonDB tier: silver. Playable but expect tweaks.";;
    bronze|borked) verdict_blocked "ProtonDB tier: ${tier}. Poor. Likely not worth it on Mac.";;
    *)             printf '%s\n' "${C_YEL}UNKNOWN${C_RESET} - no ProtonDB tier found. Check the links above."; exit 1;;
  esac
}

check_by_name() {
  local q="$1" hit
  hit="$(printf '%s\n' "$NATIVE_PORTS" | awk -F'|' -v q="$q" 'index(tolower($1),tolower(q)){print; exit}')"
  if [[ -n "$hit" ]]; then
    verdict_native "$(cut -d'|' -f2- <<<"$hit")  [${hit%%|*}]"
  fi
  cat <<EOF
${C_YEL}No exact match in curated data.${C_RESET} Look it up:
  Steam appid is in the store URL (store.steampowered.com/app/<ID>/).
  Then: $0 <ID>
$(links "<ID>")
EOF
  exit 1
}

main() {
  [[ $# -ge 1 ]] || { grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
  if [[ "$1" == "--name" ]]; then check_by_name "${2:-}"; fi
  [[ "$1" =~ ^[0-9]+$ ]] && check_by_id "$1"
  check_by_name "$1"
}
main "$@"
