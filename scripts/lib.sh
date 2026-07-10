#!/usr/bin/env bash
# lib.sh — shared functions for the mac-windows-gaming toolkit.
# Source this from other scripts:  source "$(dirname "$0")/lib.sh"
#
# Design notes for AGENTS:
#   - Every function prints structured, greppable output.
#   - Functions return non-zero on failure; callers should check.
#   - No function deletes user game data. Destructive ops are opt-in and named *_danger.
#   - All paths are computed, never hardcoded to a username.

set -o pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034  # consumed by scripts that source this file
export SIKARUGIR_ENGINES_DIR="${HOME}/Library/Application Support/Sikarugir/Engines"
export SIKARUGIR_WRAPPERS_DIR="${HOME}/Applications/Sikarugir"
export GPTK_EXTRACT_DIR="${HOME}/GPTk-D3DMetal"   # where we cache extracted D3DMetal
export BEST_ENGINE="WS12WineSikarugir10.0_6"      # Wine 10 — best all-rounder (see docs/ENGINES.md)
export DXMT_REPO="3Shain/dxmt"
export HEROIC_CASK="heroic"
export SIKARUGIR_CASK="sikarugir"

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_B=$'\033[1m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_RED=$'\033[31m'; C_BLU=$'\033[34m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_B=""; C_GRN=""; C_YEL=""; C_RED=""; C_BLU=""; C_DIM=""
fi

log()   { printf '%s\n' "${C_DIM}$*${C_RESET}"; }
info()  { printf '%s\n' "${C_BLU}${C_B}==>${C_RESET} ${C_B}$*${C_RESET}"; }
ok()    { printf '%s\n' "${C_GRN}  ✓${C_RESET} $*"; }
warn()  { printf '%s\n' "${C_YEL}  !${C_RESET} $*" >&2; }
err()   { printf '%s\n' "${C_RED}  ✗${C_RESET} $*" >&2; }
die()   { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Environment checks
# ---------------------------------------------------------------------------
require_apple_silicon() {
  [[ "$(uname -m)" == "arm64" ]] || die "This toolkit requires Apple Silicon (arm64). Intel Macs cannot use D3DMetal."
}

macos_major() { sw_vers -productVersion | cut -d. -f1; }

require_macos_14_plus() {
  local major; major="$(macos_major)"
  if (( major < 14 )); then
    die "macOS 14 (Sonoma) or newer required. You have $(sw_vers -productVersion). macOS 15+ recommended for AVX games; 26 (Tahoe) for MetalFX."
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

ensure_rosetta() {
  if /usr/bin/pgrep -q oahd 2>/dev/null; then
    ok "Rosetta 2 present"
  else
    info "Installing Rosetta 2 (needed for x86 Wine)…"
    softwareupdate --install-rosetta --agree-to-license || die "Rosetta 2 install failed"
    ok "Rosetta 2 installed"
  fi
}

ensure_homebrew() {
  if have brew; then ok "Homebrew present"; return 0; fi
  info "Installing Homebrew…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || die "Homebrew install failed"
  # add to PATH for this session (arm64 default location)
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  ok "Homebrew installed"
}

# ---------------------------------------------------------------------------
# Wrapper discovery
# ---------------------------------------------------------------------------
# Find a Steam (or other) Sikarugir wrapper. Arg1 = app name (default Steam).
find_wrapper() {
  local name="${1:-Steam}"
  local p="${SIKARUGIR_WRAPPERS_DIR}/${name}.app"
  [[ -d "$p" ]] && { printf '%s\n' "$p"; return 0; }
  # broader search
  /usr/bin/find "${HOME}/Applications" -maxdepth 3 -iname "${name}.app" -path "*ikarugir*" 2>/dev/null | head -1
}

wrapper_wine_dir()   { printf '%s/Contents/SharedSupport/wine\n' "$1"; }
wrapper_drive_c()    { printf '%s/Contents/SharedSupport/prefix/drive_c\n' "$1"; }
wrapper_steamdir()   { printf '%s/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam\n' "$1"; }
wrapper_d3dmetal_external() { printf '%s/Contents/Frameworks/renderer/d3dmetal/external\n' "$1"; }
wrapper_dxmt_dir()   { printf '%s/Contents/Frameworks/renderer/dxmt\n' "$1"; }

# ---------------------------------------------------------------------------
# Process control
# ---------------------------------------------------------------------------
kill_wine() {
  pkill -9 -f "steam.exe"       2>/dev/null || true
  pkill -9 -f "steamwebhelper"  2>/dev/null || true
  pkill -9 -f "wine-preloader"  2>/dev/null || true
  pkill -9 -f "wineserver"      2>/dev/null || true
}

# ---------------------------------------------------------------------------
# GitHub release helpers
# ---------------------------------------------------------------------------
gh_latest_tag() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1; }
gh_asset_url()  { # repo, substring-of-asset-name
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/\1/p' | grep -i "$2" | head -1
}
