#!/usr/bin/env bash

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
  info "Trying the gcenx/wine Homebrew game-porting-toolkit formula"
  have brew || { warn "Homebrew not available"; return 1; }
  brew tap gcenx/wine >/dev/null 2>&1 || true
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

  local dmg="${1:-${GPTK_DMG:-}}"
  if [[ -z "$dmg" ]]; then
    dmg="$(/usr/bin/find "${HOME}/Downloads" -maxdepth 1 -iname "*Game_Porting_Toolkit*.dmg" 2>/dev/null | head -1)"
  fi
  if [[ -n "$dmg" ]] && extract_from_dmg "$dmg"; then
    ok "D3DMetal extracted from DMG -> ${DEST}"
    exit 0
  fi

  if extract_from_brew_gptk; then
    ok "D3DMetal obtained via Homebrew game-porting-toolkit -> ${DEST}"
    exit 0
  fi

  cat >&2 <<EOF
${C_RED}Could not obtain D3DMetal automatically.${C_RESET}

Do ONE of the following, then re-run:
  - Download the Game Porting Toolkit DMG from Apple:
      https://developer.apple.com/download/all/?q=game%20porting%20toolkit
    (free, any Apple ID), then run:
      GPTK_DMG="/path/to/Game_Porting_Toolkit_*.dmg" $0
  - Or install the formula by hand:
      brew install gcenx/wine/game-porting-toolkit

EOF
  exit 1
}
main "$@"
