#!/usr/bin/env bash

LEGACY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LEGACY_DIR/../scripts/lib.sh"

{
  SIKARUGIR_ENGINES_DIR="$AS/Sikarugir/Engines"
  SIKARUGIR_WRAPPERS_DIR="$HOME/Applications/Sikarugir"
  GPTK_EXTRACT_DIR="$HOME/GPTk-D3DMetal"
  BEST_ENGINE="WS12WineSikarugir11.0_1"
  FALLBACK_ENGINE="WS12WineSikarugir10.0_8"
  SIKARUGIR_ENGINES_URL="https://github.com/Sikarugir-App/Engines/releases/download/v1.0"
  SIKARUGIR_ENGINE_LIST="https://raw.githubusercontent.com/Sikarugir-App/Engines/main/EngineList.txt"
  SIKARUGIR_WRAPPER_RELEASE_API="https://api.github.com/repos/Sikarugir-App/Wrapper/releases/tags/v1.0"
  SIKARUGIR_WRAPPER_URL="https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0"
  DXMT_REPO="3Shain/dxmt"
  SIKARUGIR_CASK="sikarugir"
}

find_wrapper() {
  local name="${1:-Steam}"
  local p="$SIKARUGIR_WRAPPERS_DIR/$name.app"
  [[ -d "$p" ]] && { printf '%s\n' "$p"; return 0; }
  /usr/bin/find "$HOME/Applications" -maxdepth 3 -iname "$name.app" -path "*ikarugir*" 2>/dev/null | head -1
}

wrapper_wine_dir()          { printf '%s/Contents/SharedSupport/wine\n' "$1"; }
wrapper_drive_c()           { printf '%s/Contents/SharedSupport/prefix/drive_c\n' "$1"; }
wrapper_steamdir()          { printf '%s/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam\n' "$1"; }
wrapper_d3dmetal_external() { printf '%s/Contents/Frameworks/renderer/d3dmetal/external\n' "$1"; }
wrapper_dxmt_dir()          { printf '%s/Contents/Frameworks/renderer/dxmt\n' "$1"; }

wrapper_template_version() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Contents/Info.plist" 2>/dev/null
}

kill_wine() {
  pkill -9 -f "steam.exe"      2>/dev/null || true
  pkill -9 -f "steamwebhelper" 2>/dev/null || true
  pkill -9 -f "wine-preloader" 2>/dev/null || true
  pkill -9 -f "wineserver"     2>/dev/null || true
}

gh_latest_tag() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1; }
gh_asset_url()  {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/\1/p' | grep -i "$2" | head -1
}

latest_template_version() {
  curl -fsSL "$SIKARUGIR_WRAPPER_RELEASE_API" \
    | sed -n 's/.*"name": *"Template-\([0-9.]*\)\.tar\.xz".*/\1/p' | sort -V | tail -1
}

latest_sikarugir_engine() {
  curl -fsSL "$SIKARUGIR_ENGINE_LIST" | grep -E '^WS12WineSikarugir[0-9]' | sort -V | tail -1
}

ensure_engine_cached() {
  local name="$1" tar="$SIKARUGIR_ENGINES_DIR/$1.tar.xz"
  if [[ ! -f "$tar" ]]; then
    mkdir -p "$SIKARUGIR_ENGINES_DIR"
    info "Downloading engine $name" >&2
    curl -fsSL -o "$tar.part" "$SIKARUGIR_ENGINES_URL/$name.tar.xz" || { rm -f "$tar.part"; return 1; }
    tar -tJf "$tar.part" >/dev/null 2>&1 || { rm -f "$tar.part"; err "Corrupt engine download"; return 1; }
    mv "$tar.part" "$tar"
  fi
  printf '%s\n' "$tar"
}
