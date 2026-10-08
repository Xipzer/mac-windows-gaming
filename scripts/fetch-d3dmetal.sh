#!/usr/bin/env bash
# fetch-d3dmetal.sh — obtain Apple's D3DMetal on THIS machine (never redistributed).
#
# WHY: Apple's D3DMetal (the DirectX 11/12 -> Metal translator) is free to download
#      but its EULA forbids redistribution. So this repo ships ZERO Apple binaries.
#      Instead, each user fetches their own copy locally, here, at install time.
#
# OPTIONAL since Oct 2026: Sikarugir wrapper templates (1.0.21+) already bundle D3DMetal
# (4.0b2). Use this only if you have a NEWER Apple build than the wrapper ships.
#
# Sources tried, in order:
#   1. A GPTk DMG the user already has (arg / env GPTK_DMG / ~/Downloads/*Game_Porting_Toolkit*.dmg)
#   2. Gcenx's Homebrew game-porting-toolkit formula (pulls Apple's redistributable D3DMetal)
#
# Output: extracts D3DMetal.framework + libd3dshared.dylib into $GPTK_EXTRACT_DIR/lib/external
#
# Usage:  ./fetch-d3dmetal.sh [/path/to/Game_Porting_Toolkit.dmg]

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"

DEST="${GPTK_EXTRACT_DIR}/lib/external"
mkdir -p "${GPTK_EXTRACT_DIR}/lib"

already_have() {
  [[ -x "${DEST}/D3DMetal.framework/Versions/A/D3DMetal" ]]
}

extract_from_dmg() {
  local dmg="$1" mnt
  [[ -f "$dmg" ]] || return 1
  info "Extracting D3DMetal from DMG: ${dmg}"
  mnt="$(mktemp -d /tmp/gptk.XXXXXX)"
  hdiutil attach "$dmg" -nobrowse -quiet -mountpoint "$mnt" || return 1

  # The outer GPTk DMG contains an inner "Evaluation environment" DMG.
  local eval_dmg redist mnt2=""
  eval_dmg="$(/usr/bin/find "$mnt" -maxdepth 1 -iname "*Evaluation environment*Windows games*.dmg" | head -1)"
  if [[ -n "$eval_dmg" ]]; then
    mnt2="$(mktemp -d /tmp/gptke.XXXXXX)"
    hdiutil attach "$eval_dmg" -nobrowse -quiet -mountpoint "$mnt2" || true
    redist="$(/usr/bin/find "$mnt2" -maxdepth 4 -type d -path "*redist/lib/external" | head -1)"
  else
    redist="$(/usr/bin/find "$mnt" -maxdepth 5 -type d -path "*redist/lib/external" | head -1)"
  fi

  if [[ -z "${redist:-}" || ! -d "$redist" ]]; then
    warn "Could not locate redist/lib/external inside the DMG"
    [[ -n "$mnt2" ]] && hdiutil detach "$mnt2" -quiet 2>/dev/null || true
    hdiutil detach "$mnt" -quiet 2>/dev/null || true
    return 1
  fi

  ditto "$(dirname "$redist")/" "${GPTK_EXTRACT_DIR}/lib/"
  [[ -n "$mnt2" ]] && hdiutil detach "$mnt2" -quiet 2>/dev/null || true
  hdiutil detach "$mnt" -quiet 2>/dev/null || true
  already_have
}

extract_from_brew_gptk() {
  info "Trying Gcenx Homebrew game-porting-toolkit (ships Apple's redistributable D3DMetal)…"
  have brew || { warn "Homebrew not available"; return 1; }
  brew tap gcenx/wine >/dev/null 2>&1 || true
  # The formula installs D3DMetal into its prefix; we copy it out.
  if brew list game-porting-toolkit >/dev/null 2>&1 || brew install --quiet gcenx/wine/game-porting-toolkit 2>/dev/null; then
    local prefix ext
    prefix="$(brew --prefix game-porting-toolkit 2>/dev/null || true)"
    ext="$(/usr/bin/find "${prefix:-/opt/homebrew}" -maxdepth 4 -type d -name external -path "*d3dmetal*" 2>/dev/null | head -1)"
    [[ -z "$ext" ]] && ext="$(/usr/bin/find "${prefix:-/opt/homebrew}" -maxdepth 5 -type d -name external 2>/dev/null | head -1)"
    if [[ -n "$ext" && -d "$ext" ]]; then
      ditto "$ext/" "${DEST}/"
      already_have && return 0
    fi
  fi
  return 1
}

main() {
  require_apple_silicon

  if already_have; then
    ok "D3DMetal already extracted at ${DEST}"
    exit 0
  fi

  # 1) explicit arg or env or ~/Downloads
  local dmg="${1:-${GPTK_DMG:-}}"
  if [[ -z "$dmg" ]]; then
    dmg="$(/usr/bin/find "${HOME}/Downloads" -maxdepth 1 -iname "*Game_Porting_Toolkit*.dmg" 2>/dev/null | head -1)"
  fi
  if [[ -n "$dmg" ]] && extract_from_dmg "$dmg"; then
    ok "D3DMetal extracted from DMG -> ${DEST}"
    exit 0
  fi

  # 2) brew gptk
  if extract_from_brew_gptk; then
    ok "D3DMetal obtained via Homebrew game-porting-toolkit -> ${DEST}"
    exit 0
  fi

  cat >&2 <<EOF
${C_RED}Could not obtain D3DMetal automatically.${C_RESET}

Do ONE of the following, then re-run:
  • Download the Game Porting Toolkit DMG from Apple:
      https://developer.apple.com/download/all/?q=game%20porting%20toolkit
    (free, any Apple ID), then run:
      GPTK_DMG="/path/to/Game_Porting_Toolkit_*.dmg" $0
  • Or install Gcenx's formula manually:
      brew install gcenx/wine/game-porting-toolkit

Note: this repo cannot ship D3DMetal — Apple's license forbids redistribution.
EOF
  exit 1
}
main "$@"
