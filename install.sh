#!/usr/bin/env bash
# install.sh — one-shot setup for a free Windows-gaming environment on Apple Silicon macOS.
#
# What it does (all free, no CrossOver):
#   1. Verifies Apple Silicon + macOS 14+.
#   2. Installs Rosetta 2, Homebrew, helper tools (cabextract, p7zip).
#   3. Installs Heroic Games Launcher (Epic/GOG/Amazon) + Sikarugir (Steam).
#   4. Fetches YOUR OWN Apple D3DMetal locally (never redistributed).
#   5. Guides the 2 unavoidable Sikarugir GUI clicks, then auto-applies every fix.
#
# Run it:
#   curl -fsSL https://raw.githubusercontent.com/Xipzer/mac-windows-gaming/main/install.sh | bash
# or, cloned:
#   ./install.sh
#
# Flags:
#   --no-steam     skip the Steam/Sikarugir wrapper part (Heroic only)
#   --gptk-dmg P   use a specific Game Porting Toolkit DMG for D3DMetal
#
# See docs/ for the full knowledge base. This script is idempotent — safe to re-run.

set -euo pipefail

# Resolve script dir even when curl|bash'd (fall back to fetching scripts).
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
RAW_BASE="https://raw.githubusercontent.com/Xipzer/mac-windows-gaming/main"

fetch_lib() {
  # If run via curl|bash, scripts/ won't exist locally — fetch them to a temp dir.
  if [[ -f "${SELF_DIR}/scripts/lib.sh" ]]; then
    SCRIPTS_DIR="${SELF_DIR}/scripts"
  else
    SCRIPTS_DIR="$(mktemp -d /tmp/mwg.XXXXXX)"
    local s
    for s in lib.sh fetch-d3dmetal.sh setup-steam.sh swap-engine.sh update-dxmt.sh check-compat.sh; do
      curl -fsSL -o "${SCRIPTS_DIR}/${s}" "${RAW_BASE}/scripts/${s}"
      chmod +x "${SCRIPTS_DIR}/${s}"
    done
  fi
  source "${SCRIPTS_DIR}/lib.sh"
}

NO_STEAM=0; GPTK_DMG_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-steam) NO_STEAM=1; shift;;
    --gptk-dmg) GPTK_DMG_ARG="$2"; shift 2;;
    *) shift;;
  esac
done

main() {
  fetch_lib

  info "mac-windows-gaming — one-shot installer"
  log  "macOS $(sw_vers -productVersion) ($(uname -m))"

  require_apple_silicon
  require_macos_14_plus
  ensure_rosetta
  ensure_homebrew

  info "Installing helper tools…"
  brew install --quiet cabextract p7zip 2>/dev/null || true
  ok "cabextract, p7zip"

  info "Installing launchers…"
  brew install --quiet --cask "$HEROIC_CASK" 2>/dev/null || true
  ok "Heroic Games Launcher"
  brew tap Sikarugir-App/sikarugir >/dev/null 2>&1 || true
  brew install --quiet --cask "Sikarugir-App/sikarugir/${SIKARUGIR_CASK}" 2>/dev/null || true
  ok "Sikarugir Creator"

  info "Obtaining Apple D3DMetal (locally, never redistributed)…"
  if [[ -n "$GPTK_DMG_ARG" ]]; then
    GPTK_DMG="$GPTK_DMG_ARG" bash "${SCRIPTS_DIR}/fetch-d3dmetal.sh" || warn "D3DMetal not obtained; you can run scripts/fetch-d3dmetal.sh later."
  else
    bash "${SCRIPTS_DIR}/fetch-d3dmetal.sh" || warn "D3DMetal not obtained; you can run scripts/fetch-d3dmetal.sh later."
  fi

  if [[ "$NO_STEAM" -eq 0 ]]; then
    info "Setting up Steam wrapper…"
    bash "${SCRIPTS_DIR}/setup-steam.sh" || true
  fi

  cat <<EOF

${C_GRN}${C_B}Done.${C_RESET}

Next:
  • Heroic: open Heroic -> Settings -> Wine Manager -> download 'Game-Porting-Toolkit',
    set it as default runner + enable ESYNC, then log into Epic/GOG/Amazon.
  • Steam:  if setup-steam printed a GUI step, do it once and re-run:
              bash "${SCRIPTS_DIR}/setup-steam.sh"
            then:  open ~/Applications/Sikarugir/Steam.app

Check a game before installing:
  bash "${SCRIPTS_DIR}/check-compat.sh" <steam_app_id>

Full docs & troubleshooting: https://github.com/Xipzer/mac-windows-gaming
EOF
}
main "$@"
