#!/usr/bin/env bash

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
REPO_URL="https://github.com/Xipzer/mac-windows-gaming.git"

resolve_repo() {
  if [[ -f "${SELF_DIR}/scripts/lib.sh" && -d "${SELF_DIR}/notproton" ]]; then
    REPO_DIR="$SELF_DIR"
  else
    REPO_DIR="$HOME/Library/Caches/mac-windows-gaming"
    if [[ -d "$REPO_DIR/.git" ]]; then git -C "$REPO_DIR" pull -q --ff-only || true
    else rm -rf "$REPO_DIR"; git clone -q --depth 1 "$REPO_URL" "$REPO_DIR"; fi
  fi
  SCRIPTS_DIR="$REPO_DIR/scripts"
  source "${SCRIPTS_DIR}/lib.sh"
}

NO_HEROIC=0; LEGACY=0; SKIP_STEAM=0; GPTK_DMG_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-heroic) NO_HEROIC=1; shift;;
    --legacy-wrapper) LEGACY=1; shift;;
    --gptk-dmg) GPTK_DMG_ARG="$2"; shift 2;;
    --no-steam) SKIP_STEAM=1; shift;;
    *) shift;;
  esac
done

main() {
  command -v git >/dev/null || { echo "git missing: run  xcode-select --install  then re-run"; exit 1; }
  resolve_repo

  info "mac-windows-gaming - one-shot installer"
  log  "macOS $(sw_vers -productVersion) ($(uname -m))"
  require_apple_silicon
  require_macos_14_plus
  ensure_rosetta
  ensure_homebrew
  brew list cmake >/dev/null 2>&1 || brew install --quiet cmake
  ok "cmake"

  if (( ! NO_HEROIC )); then
    brew install --quiet --cask "$HEROIC_CASK" 2>/dev/null || true
    ok "Heroic Games Launcher (Epic/GOG/Amazon)"
  fi

  if (( SKIP_STEAM )); then :
  elif (( LEGACY )); then
    brew tap Sikarugir-App/sikarugir >/dev/null 2>&1 || true
    brew install --quiet --cask "Sikarugir-App/sikarugir/${SIKARUGIR_CASK}" 2>/dev/null || true
    if [[ -n "$GPTK_DMG_ARG" ]]; then GPTK_DMG="$GPTK_DMG_ARG" bash "${SCRIPTS_DIR}/fetch-d3dmetal.sh" || true
    else bash "${SCRIPTS_DIR}/fetch-d3dmetal.sh" || true; fi
    bash "${SCRIPTS_DIR}/setup-steam.sh" || true
  else
    if [[ ! -d /Applications/Steam.app ]]; then
      info "Installing Steam for macOS"
      brew install --quiet --cask steam
      warn "Open Steam once, log in and let it finish updating, then quit it and re-run this installer."
      open -a Steam || true
      exit 0
    fi
    bash "${SCRIPTS_DIR}/setup-notproton.sh"
  fi

  cat <<EOF

${C_GRN}${C_B}Done.${C_RESET}

Next:
  • Steam:  open -a Steam  → Windows games now show a Play button.
            Settings → Compatibility shows "NotProton (free, Wine 11)" as the default.
  • Heroic: Settings → Wine Manager → download 'Game-Porting-Toolkit', set it as the
            default runner, then log into Epic/GOG/Amazon.

Check a game first:   bash "${SCRIPTS_DIR}/check-compat.sh" <steam_app_id>
After a Steam update stops games launching:   bash "${SCRIPTS_DIR}/setup-notproton.sh" --skip-build
Docs & troubleshooting: https://github.com/Xipzer/mac-windows-gaming
EOF
}
main "$@"
