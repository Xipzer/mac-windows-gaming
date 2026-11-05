#!/usr/bin/env bash

set -o pipefail

{
  AS="$HOME/Library/Application Support"
  SB="$AS/SteamBridge"
  STEAM_APP="/Applications/Steam.app"
  STEAM_DIR="$AS/Steam"
  STEAMAPPS="$STEAM_DIR/steamapps"
  COMPAT="$STEAM_DIR/compatibilitytools.d/steambridge"
  CONFIG_VDF="$STEAM_DIR/config/config.vdf"
  DYLIB_NAME="steambridge.dylib"
  TOOL_NAME="steambridge"
  HEROIC_CASK="heroic"
}

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_B=$'\033[1m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_RED=$'\033[31m'; C_BLU=$'\033[34m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_B=""; C_GRN=""; C_YEL=""; C_RED=""; C_BLU=""; C_DIM=""
fi
log()  { printf '%s\n' "${C_DIM}$*${C_RESET}"; }
info() { printf '%s\n' "${C_BLU}${C_B}==>${C_RESET} ${C_B}$*${C_RESET}"; }
ok()   { printf '%s\n' "${C_GRN}  ok${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YEL}  !!${C_RESET} $*" >&2; }
err()  { printf '%s\n' "${C_RED}  xx${C_RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

require_apple_silicon() {
  [[ "$(uname -m)" == "arm64" ]] || die "Apple Silicon (arm64) required. Intel Macs cannot use D3DMetal."
}

macos_major() { sw_vers -productVersion | cut -d. -f1; }

require_macos_14_plus() {
  (( $(macos_major) >= 14 )) || die "macOS 14 or newer required. You have $(sw_vers -productVersion)."
}

ensure_rosetta() {
  if /usr/bin/pgrep -q oahd 2>/dev/null; then
    ok "Rosetta 2 present"
  else
    info "Installing Rosetta 2 (needed for x86 Wine)"
    softwareupdate --install-rosetta --agree-to-license || die "Rosetta 2 install failed"
    ok "Rosetta 2 installed"
  fi
}

ensure_homebrew() {
  if have brew; then ok "Homebrew present"; return 0; fi
  info "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || die "Homebrew install failed"
  if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
  ok "Homebrew installed"
}

version_gt() {
  [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}

d3dmetal_version() {
  local plist="$1/D3DMetal.framework/Versions/A/Resources/version.plist"
  [[ -f "$plist" ]] && plutil -extract CFBundleVersion raw "$plist" 2>/dev/null
}

steam_client_build() {
  local m
  for m in "$STEAM_DIR"/Steam.AppBundle/Steam/Contents/MacOS/package/steam_client_*osx.manifest; do
    [[ -f "$m" ]] && sed -n 's/^[[:space:]]*"version"[[:space:]]*"\([0-9]*\)".*/\1/p' "$m" | head -1
  done | sort -n | tail -1
}
