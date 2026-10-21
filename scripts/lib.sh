#!/usr/bin/env bash

set -o pipefail

export SIKARUGIR_ENGINES_DIR="${HOME}/Library/Application Support/Sikarugir/Engines"
export SIKARUGIR_WRAPPERS_DIR="${HOME}/Applications/Sikarugir"
export GPTK_EXTRACT_DIR="${HOME}/GPTk-D3DMetal"
export BEST_ENGINE="WS12WineSikarugir11.0_1"
export FALLBACK_ENGINE="WS12WineSikarugir10.0_8"
export SIKARUGIR_ENGINES_URL="https://github.com/Sikarugir-App/Engines/releases/download/v1.0"
export SIKARUGIR_ENGINE_LIST="https://raw.githubusercontent.com/Sikarugir-App/Engines/main/EngineList.txt"
export SIKARUGIR_WRAPPER_RELEASE_API="https://api.github.com/repos/Sikarugir-App/Wrapper/releases/tags/v1.0"
export SIKARUGIR_WRAPPER_URL="https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0"
export DXMT_REPO="3Shain/dxmt"
export HEROIC_CASK="heroic"
export SIKARUGIR_CASK="sikarugir"

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
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  ok "Homebrew installed"
}

find_wrapper() {
  local name="${1:-Steam}"
  local p="${SIKARUGIR_WRAPPERS_DIR}/${name}.app"
  [[ -d "$p" ]] && { printf '%s\n' "$p"; return 0; }
  /usr/bin/find "${HOME}/Applications" -maxdepth 3 -iname "${name}.app" -path "*ikarugir*" 2>/dev/null | head -1
}

wrapper_wine_dir()   { printf '%s/Contents/SharedSupport/wine\n' "$1"; }
wrapper_drive_c()    { printf '%s/Contents/SharedSupport/prefix/drive_c\n' "$1"; }
wrapper_steamdir()   { printf '%s/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam\n' "$1"; }
wrapper_d3dmetal_external() { printf '%s/Contents/Frameworks/renderer/d3dmetal/external\n' "$1"; }
wrapper_dxmt_dir()   { printf '%s/Contents/Frameworks/renderer/dxmt\n' "$1"; }

kill_wine() {
  pkill -9 -f "steam.exe"       2>/dev/null || true
  pkill -9 -f "steamwebhelper"  2>/dev/null || true
  pkill -9 -f "wine-preloader"  2>/dev/null || true
  pkill -9 -f "wineserver"      2>/dev/null || true
}

gh_latest_tag() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1; }
gh_asset_url()  {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/\1/p' | grep -i "$2" | head -1
}

version_gt() {
  [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}

d3dmetal_version() {
  local plist="$1/D3DMetal.framework/Versions/A/Resources/version.plist"
  [[ -f "$plist" ]] && plutil -extract CFBundleVersion raw "$plist" 2>/dev/null
}

wrapper_template_version() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Contents/Info.plist" 2>/dev/null
}

latest_template_version() {
  curl -fsSL "$SIKARUGIR_WRAPPER_RELEASE_API" \
    | sed -n 's/.*"name": *"Template-\([0-9.]*\)\.tar\.xz".*/\1/p' | sort -V | tail -1
}

latest_sikarugir_engine() {
  curl -fsSL "$SIKARUGIR_ENGINE_LIST" | grep -E '^WS12WineSikarugir[0-9]' | sort -V | tail -1
}

ensure_engine_cached() {
  local name="$1" tar="${SIKARUGIR_ENGINES_DIR}/$1.tar.xz"
  if [[ ! -f "$tar" ]]; then
    mkdir -p "$SIKARUGIR_ENGINES_DIR"
    info "Downloading engine ${name}…" >&2
    curl -fsSL -o "${tar}.part" "${SIKARUGIR_ENGINES_URL}/${name}.tar.xz" || { rm -f "${tar}.part"; return 1; }
    tar -tJf "${tar}.part" >/dev/null 2>&1 || { rm -f "${tar}.part"; err "Corrupt engine download" ; return 1; }
    mv "${tar}.part" "$tar"
  fi
  printf '%s\n' "$tar"
}
