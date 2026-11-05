#!/usr/bin/env bash

set -euo pipefail

REPO_URL="https://github.com/Xipzer/mac-windows-gaming.git"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

NO_HEROIC=0; NO_STEAM=0; LEGACY=0; GPTK_DMG_ARG=""; SETUP_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-heroic) NO_HEROIC=1; shift;;
    --no-steam) NO_STEAM=1; shift;;
    --legacy-wrapper) LEGACY=1; shift;;
    --gptk-dmg) GPTK_DMG_ARG="${2:?--gptk-dmg needs a path}"; shift 2;;
    -h|--help) sed -n '2,21p' "$0" 2>/dev/null || true; exit 0;;
    *) SETUP_ARGS+=("$1"); shift;;
  esac
done

resolve_repo() {
  if [[ -f "$SELF_DIR/scripts/setup.sh" && -f "$SELF_DIR/scripts/lib.sh" ]]; then
    REPO="$SELF_DIR"
    return 0
  fi
  REPO="${STEAMBRIDGE_REPO:-$HOME/Library/Caches/steambridge/repo}"
  if [[ -d "$REPO/.git" ]]; then
    git -C "$REPO" pull -q --ff-only || echo "  !! could not update $REPO; using it as is" >&2
    return 0
  fi
  command -v git >/dev/null || { echo "git missing: xcode-select --install, then re-run" >&2; exit 1; }
  mkdir -p "$(dirname "$REPO")"
  git clone -q --depth 1 "$REPO_URL" "$REPO"
}

games_launched() {
  local f id
  for f in "$REPO"/configs/games/*.env; do
    id="$(basename "$f" .env)"
    [[ -d "$HOME/Library/Application Support/Steam/steamapps/compatdata/$id" ]] && return 0
  done
  return 1
}

main() {
  command -v git >/dev/null || { echo "git missing: run  xcode-select --install  then re-run" >&2; exit 1; }
  resolve_repo
  source "$REPO/scripts/lib.sh"

  info "SteamBridge installer ($REPO)"
  log "  macOS $(sw_vers -productVersion) ($(uname -m))"
  require_apple_silicon
  require_macos_14_plus
  ensure_rosetta
  ensure_homebrew
  if ! brew list cmake >/dev/null 2>&1 && ! have cmake; then brew install --quiet cmake; fi
  ok "cmake"

  if (( ! NO_HEROIC )); then
    if brew list --cask "$HEROIC_CASK" >/dev/null 2>&1 || [[ -d "/Applications/Heroic.app" ]]; then
      ok "Heroic present"
    else
      info "Installing Heroic (Epic/GOG/Amazon)"
      brew install --quiet --cask "$HEROIC_CASK" || warn "Heroic install failed; continuing"
    fi
  fi

  if (( NO_STEAM )); then
    :
  elif (( LEGACY )); then
    info "Legacy route: Windows Steam in a Sikarugir wrapper"
    brew tap Sikarugir-App/sikarugir >/dev/null 2>&1 || true
    brew install --quiet --cask "Sikarugir-App/sikarugir/sikarugir" || warn "Sikarugir install failed"
    if [[ -n "$GPTK_DMG_ARG" ]]; then bash "$REPO/legacy/fetch-d3dmetal.sh" "$GPTK_DMG_ARG" || true
    else bash "$REPO/legacy/fetch-d3dmetal.sh" || true; fi
    bash "$REPO/legacy/setup-steam.sh"
  else
    if [[ ! -d "$STEAM_APP" ]]; then
      info "Installing Steam for macOS"
      brew install --quiet --cask steam
      warn "Open Steam once, log in, let it finish updating, quit it, then re-run this installer."
      open -a Steam || true
      exit 0
    fi
    bash "$REPO/scripts/setup.sh" ${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"}
    if games_launched; then
      info "Applying tuned per-game profiles"
      sh "$REPO/scripts/apply-game-configs.sh"
    else
      log "  No tuned game launched yet. After a first launch: scripts/apply-game-configs.sh"
    fi
  fi

  cat <<EOF

${C_GRN}${C_B}Done.${C_RESET}

  Steam:   open -a Steam. Windows games show a Play button; Settings > Compatibility shows SteamBridge.
  Heroic:  Settings > Wine Manager > download Game-Porting-Toolkit, set it as default, log into Epic/GOG/Amazon.

  Check a game first:      bash "$REPO/scripts/check-compat.sh" <steam_appid>
  Health report:           bash "$REPO/scripts/doctor.sh"
  After a Steam update:    bash "$REPO/scripts/setup.sh" --skip-build
  Docs:                    $REPO/README.md, $REPO/docs/TROUBLESHOOTING.md
EOF
}
main "$@"
