#!/usr/bin/env bash

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

DOBBY_URL="https://github.com/jmpews/Dobby.git"
DOBBY_COMMIT="5dfc8546954ce3b3198132ab13fddb89ee92cdd7"
UPSTREAM_BRIDGE_ZIP_URL="https://github.com/NotProtonNot/NotProton/releases/download/v1.0.1/NotProton.zip"
UPSTREAM_BRIDGE_ZIP_SHA="1f1f4038ef44e48454c7746fad2b9964f7c82c4ae04af117e474a2d129eda52d"
UPSTREAM_SIGNATURES_API="https://api.github.com/repos/NotProtonNot/NotProton/contents/signatures/macos.arm64"
SIKARUGIR_ENGINES_URL="https://github.com/Sikarugir-App/Engines/releases/download/v1.0"
SIKARUGIR_WRAPPER_URL="https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0"
ENGINE="WS12WineSikarugir11.0_1"
ENGINE_SHA="67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e"
TEMPLATE="1.0.21"
TEMPLATE_SHA="bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d"
TEMPLATE_B3="1.0.24"
TEMPLATE_B3_SHA="4b5f89eeb9ef139936bdfad33d9b420b05ea4597cb7d63376674f7a8e171321c"

STEAM_APP="/Applications/Steam.app"
AS="$HOME/Library/Application Support"
SB="$AS/SteamBridge"
STATE="$SB/setup"
CACHE="$HOME/Library/Caches/steambridge/downloads"
BUILD_COPY="$HOME/Library/Caches/steambridge/build"
RUNNER="$SB/runners/sikarugir-11"
BRIDGE="$SB/bridge"
STEAM_DIR="$AS/Steam"
COMPAT="$STEAM_DIR/compatibilitytools.d/steambridge"
CONFIG_VDF="$STEAM_DIR/config/config.vdf"
DYLIB_NAME="steambridge.dylib"
TOOL_NAME="steambridge"

LEGACY_NAME="notproton"
LEGACY_SUPPORT="$AS/$LEGACY_NAME"
LEGACY_STATE="$AS/$LEGACY_NAME-free"
LEGACY_CACHE="$HOME/Library/Caches/$LEGACY_NAME-free/downloads"
LEGACY_COMPAT="$STEAM_DIR/compatibilitytools.d/$LEGACY_NAME"
LEGACY_ENV_PREFIX="NOTPROTON_"

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

require_apple_silicon() {
  [[ "$(uname -m)" == "arm64" ]] || die "SteamBridge requires Apple Silicon (arm64)."
}

require_macos_14_plus() {
  local major; major="$(sw_vers -productVersion | cut -d. -f1)"
  (( major >= 14 )) || die "macOS 14 or newer required. You have $(sw_vers -productVersion)."
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

FORCE=0; SET_DEFAULT=1; SKIP_BUILD=0; UNINSTALL=0; MIGRATE_ONLY=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1;; --no-default) SET_DEFAULT=0;; --skip-build) SKIP_BUILD=1;;
    --uninstall) UNINSTALL=1;; --migrate) MIGRATE_ONLY=1;;
    -h|--help) printf '%s\n' "Usage: setup.sh [--force] [--skip-build] [--no-default] [--migrate] [--uninstall]" "  --force       rebuild the runner and the hook library" "  --skip-build  reuse the existing build (after a Steam update)" "  --no-default  do not make SteamBridge the default for Windows games" "  --migrate     only migrate an older install to SteamBridge names" "  --uninstall   restore stock Steam.app and remove the compatibility tool"; exit 0;;
    *) die "unknown option $a";;
  esac
done

sha_ok() { [[ "$(shasum -a 256 "$1" | cut -d' ' -f1)" == "$2" ]]; }

fetch() {
  if [[ -f "$2" ]] && sha_ok "$2" "$3"; then return 0; fi
  log "  downloading $(basename "$2")"
  curl -fSL --progress-bar -o "$2.part" "$1"
  sha_ok "$2.part" "$3" || { rm -f "$2.part"; die "checksum mismatch for $1"; }
  mv "$2.part" "$2"
}

quit_steam() {
  pgrep -x steam_osx >/dev/null || return 0
  info "Quitting Steam"
  osascript -e 'quit app "Steam"' >/dev/null 2>&1 || true
  local _; for _ in $(seq 1 30); do pgrep -x steam_osx >/dev/null || return 0; sleep 1; done
  pkill -x steam_osx || true; sleep 2
  pgrep -x steam_osx >/dev/null && die "Steam is still running; quit it and re-run"
  return 0
}

require_no_games() {
  if pgrep -x wineserver >/dev/null || pgrep -f 'wine-preloader|wineserver' >/dev/null; then
    die "A Wine process is running (a game?). Close it, then re-run."
  fi
}

steam_backup() {
  find "$STATE" "$LEGACY_STATE" -maxdepth 2 -path "*/backup-*/Steam.app" 2>/dev/null | head -1
}

remove_injection() {
  /usr/libexec/PlistBuddy -c "Delete :LSEnvironment:DYLD_INSERT_LIBRARIES" "$STEAM_APP/Contents/Info.plist" 2>/dev/null || true
  rm -f "$STEAM_APP/Contents/MacOS/$1"
}

backup_file() {
  local b; b="$1.bak-steambridge-$2-$(date +%Y%m%d%H%M%S)"
  cp -p "$1" "$b"; log "  backup: $b"
}

move_entries() {
  local from="$1" to="$2" e name
  [[ -d "$from" ]] || return 0
  mkdir -p "$to"
  for e in "$from"/* "$from"/.[!.]*; do
    [[ -e "$e" || -L "$e" ]] || continue
    name="$(basename "$e")"
    [[ "$name" == ".DS_Store" ]] && { rm -f "$e"; continue; }
    name="${name//$LEGACY_NAME/$TOOL_NAME}"
    if [[ -e "$to/$name" || -L "$to/$name" ]]; then
      if [[ -d "$e" && -d "$to/$name" && ! -L "$e" ]]; then
        move_entries "$e" "$to/$name"
      else
        warn "kept both: $to/$name exists, left $e in place"
      fi
    else
      mv "$e" "$to/$name"
    fi
  done
  rmdir "$from" 2>/dev/null || warn "$from not empty after migration; check it by hand"
}

rename_legacy_files() {
  local f new
  find "$1" -maxdepth "$2" -name "*$LEGACY_NAME*" ! -type d -print0 2>/dev/null \
    | while IFS= read -r -d '' f; do
        new="$(dirname "$f")/$(basename "$f" | sed "s/$LEGACY_NAME/$TOOL_NAME/g")"
        if [[ -e "$new" ]]; then warn "kept both: $new exists, left $f"; else mv "$f" "$new"; fi
      done
}

repoint_symlinks() {
  local l t
  find "$1" -type l -print0 2>/dev/null \
    | while IFS= read -r -d '' l; do
        t="$(readlink "$l")"
        case "$t" in
          "$LEGACY_SUPPORT"/*) ln -sfn "$SB/${t#"$LEGACY_SUPPORT"/}" "$l" ;;
        esac
      done
}

rewrite_text() {
  python3 - "$1" "$2" "$LEGACY_NAME" "$LEGACY_ENV_PREFIX" <<'PY'
import re, sys
path, mode, old, envp = sys.argv[1:5]
raw = open(path, "rb").read()
s = raw.decode("utf-8", errors="surrogateescape")
n = s
if mode == "config":
    n = re.sub(r'("name"\s+)"%s"' % re.escape(old), r'\1"steambridge"', n)
elif mode == "localconfig":
    n = n.replace(envp, "STEAMBRIDGE_")
    n = n.replace("Application Support/%s-free/direct-shipping.sh" % old,
                  "Application Support/SteamBridge/direct-shipping.sh")
    n = n.replace("Application Support/%s/" % old, "Application Support/SteamBridge/")
elif mode == "reg":
    n = n.replace("Application Support\\\\%s\\\\" % old, "Application Support\\\\SteamBridge\\\\")
if n != s:
    open(path, "wb").write(n.encode("utf-8", errors="surrogateescape"))
    print("changed")
PY
}

migrate() {
  local need=0
  [[ -d "$LEGACY_SUPPORT" || -d "$LEGACY_STATE" || -d "$LEGACY_COMPAT" ]] && need=1
  [[ -f "$CONFIG_VDF" ]] && grep -q "\"$LEGACY_NAME\"" "$CONFIG_VDF" && need=1
  (( need )) || return 0

  info "Migrating the older install to SteamBridge"
  quit_steam
  require_no_games
  mkdir -p "$SB" "$STATE"

  if [[ -d "$LEGACY_SUPPORT" ]]; then
    move_entries "$LEGACY_SUPPORT" "$SB"
    rename_legacy_files "$SB/runners" 6
    rename_legacy_files "$SB/launchers" 2
    repoint_symlinks "$SB"
    ok "Runners, bridge, signatures, launchers -> $SB"
  fi

  if [[ -d "$LEGACY_STATE" ]]; then
    move_entries "$LEGACY_STATE" "$STATE"
    ok "Steam.app backup and logs -> $STATE"
  fi

  if [[ -d "$LEGACY_CACHE" ]]; then
    mkdir -p "$CACHE"
    cp -n "$LEGACY_CACHE"/* "$CACHE"/ 2>/dev/null || true
  fi

  if [[ -d "$LEGACY_COMPAT" ]]; then
    if [[ -d "$COMPAT" ]]; then rm -rf "$LEGACY_COMPAT"; else mv "$LEGACY_COMPAT" "$COMPAT"; fi
    ok "Compatibility tool dir -> $COMPAT"
  fi

  if [[ -f "$CONFIG_VDF" ]] && grep -q "\"$LEGACY_NAME\"" "$CONFIG_VDF"; then
    backup_file "$CONFIG_VDF" migrate
    rewrite_text "$CONFIG_VDF" config >/dev/null
    ok "CompatToolMapping entries -> \"$TOOL_NAME\""
  fi

  local f
  for f in "$STEAM_DIR"/userdata/*/config/localconfig.vdf; do
    [[ -f "$f" ]] || continue
    grep -q -e "$LEGACY_ENV_PREFIX" -e "Application Support/$LEGACY_NAME" "$f" || continue
    backup_file "$f" migrate
    rewrite_text "$f" localconfig >/dev/null
    ok "Launch options rewritten in $f"
  done

  local d
  for d in "$STEAM_DIR"/steamapps/compatdata/*/; do
    [[ -d "$d" ]] || continue
    rename_legacy_files "$d" 1
    for f in "$d"pfx/system.reg "$d"pfx/user.reg; do
      [[ -f "$f" ]] && grep -q "Application Support\\\\\\\\$LEGACY_NAME\\\\\\\\" "$f" || continue
      cp -p "$f" "$f.bak-steambridge-migrate"
      rewrite_text "$f" reg >/dev/null
    done
  done
  ok "Per-prefix files renamed in compatdata"

  if [[ -f "$STEAM_APP/Contents/MacOS/$LEGACY_NAME.dylib" ]]; then
    remove_injection "$LEGACY_NAME.dylib"
    codesign -f -s - "$STEAM_APP" 2>/dev/null || true
    ok "Removed the old injection from Steam.app (re-injected below)"
  fi
}

uninstall() {
  quit_steam
  local bk; bk="$(steam_backup)"
  if [[ -n "$bk" ]]; then
    rm -rf "$STEAM_APP"; ditto "$bk" "$STEAM_APP"; ok "Restored stock Steam.app from $bk"
  else
    remove_injection "$DYLIB_NAME"; remove_injection "$LEGACY_NAME.dylib"
    codesign -f -s - "$STEAM_APP" 2>/dev/null || true
    warn "No backup found; removed the injection by hand (reinstall Steam if it misbehaves)"
  fi
  rm -rf "$COMPAT" "$LEGACY_COMPAT"
  ok "Removed the compatibility tool. Runner, bridge and game prefixes are left in $SB"
  exit 0
}

require_apple_silicon
require_macos_14_plus
[[ -d "$STEAM_APP" ]] || die "Install Steam for macOS first: https://store.steampowered.com/about/ (or: brew install --cask steam)"
(( UNINSTALL )) && uninstall
migrate
(( MIGRATE_ONLY )) && { ok "Migration done"; exit 0; }
ensure_rosetta
for t in clang make git python3 curl tar codesign rsync; do
  command -v "$t" >/dev/null || die "Missing '$t'. Run: xcode-select --install"
done
if ! command -v cmake >/dev/null; then
  command -v brew >/dev/null || die "cmake is needed to build Dobby; install Homebrew then re-run"
  info "Installing cmake (needed once to build the hook library)"; brew install cmake >/dev/null
fi
mkdir -p "$CACHE" "$SB" "$STATE"
ok "Prerequisites present"

quit_steam

if [[ "$REPO" == *" "* ]]; then
  SRC="$BUILD_COPY/src"
else
  SRC="$REPO"
fi
if (( ! SKIP_BUILD )); then
  info "Building SteamBridge"
  if [[ "$SRC" != "$REPO" ]]; then
    mkdir -p "$SRC"
    rsync -a --delete --exclude .git --exclude out --exclude build --exclude vendor/dobby "$REPO/" "$SRC/"
  fi
  if [[ ! -d "$SRC/vendor/dobby/.git" ]]; then
    git clone -q "$DOBBY_URL" "$SRC/vendor/dobby"
  fi
  git -C "$SRC/vendor/dobby" checkout -q "$DOBBY_COMMIT"
  ( cd "$SRC"
    (( FORCE )) && rm -rf out build/dobby
    [[ -f build/dobby/libdobby.a ]] || make dobby >"$STATE/build.log" 2>&1 || { tail -20 "$STATE/build.log"; exit 1; }
    make all helpers-install sigdb-install >>"$STATE/build.log" 2>&1 || { tail -20 "$STATE/build.log"; exit 1; } )
  ok "Built $DYLIB_NAME (log: $STATE/build.log)"
fi
[[ -f "$SRC/out/$DYLIB_NAME" ]] || die "No build at $SRC/out (run without --skip-build)"

clang -O2 -Wall -arch arm64 -arch x86_64 -framework ApplicationServices \
  "$REPO/helpers/dispmode.c" -o "$SB/dispmode"
clang -arch x86_64 -O2 -Wall -dynamiclib -mmacosx-version-min=11.0 \
  -install_name @rpath/prio-shim.dylib "$REPO/helpers/prio_shim.c" -o "$SB/prio-shim.dylib"
codesign -fs - "$SB/dispmode" "$SB/prio-shim.dylib" 2>/dev/null
ok "Helpers: dispmode, prio-shim"

sigdir="$SB/signatures/macos.arm64"; mkdir -p "$sigdir"
for u in $(curl -fsSL "$UPSTREAM_SIGNATURES_API" 2>/dev/null | sed -n 's/.*"download_url": *"\([^"]*\.json\)".*/\1/p'); do
  curl -fsSL -o "$sigdir/$(basename "$u")" "$u" || true
done
ok "Signatures: $(find "$sigdir" -name "*.json" | wc -l | tr -d ' ') Steam builds"

if (( FORCE )) || [[ ! -x "$RUNNER/bin/wine" ]]; then
  info "Assembling the Wine 11 runner"
  fetch "${SIKARUGIR_ENGINES_URL}/${ENGINE}.tar.xz" "$CACHE/${ENGINE}.tar.xz" "$ENGINE_SHA"
  fetch "${SIKARUGIR_WRAPPER_URL}/Template-${TEMPLATE}.tar.xz" "$CACHE/Template-${TEMPLATE}.tar.xz" "$TEMPLATE_SHA"
  tmp="$(mktemp -d /tmp/sbr.XXXXXX)"; trap 'rm -rf "$tmp"' EXIT
  tar -xJf "$CACHE/${ENGINE}.tar.xz" -C "$tmp"
  tar -xJf "$CACHE/Template-${TEMPLATE}.tar.xz" -C "$tmp"
  T="$(find "$tmp" -maxdepth 1 -name 'Template-*.app' | head -1)/Contents"
  [[ -d "$tmp/wswine.bundle/bin" && -d "$T/Frameworks" ]] || die "Unexpected engine/template layout"
  rm -rf "$RUNNER"; mkdir -p "$RUNNER"
  ditto "$tmp/wswine.bundle" "$RUNNER"
  ditto "$T/Frameworks" "$RUNNER/Frameworks"
  if [[ -d "$T/Resources/vulkan" ]]; then ditto "$T/Resources/vulkan" "$RUNNER/Resources/vulkan"; fi
  ok "Runner: $("$RUNNER/bin/wine" --version 2>/dev/null) + Template-${TEMPLATE} libraries"
fi
if [[ -d "$RUNNER/vulkan" && ! -d "$RUNNER/Resources/vulkan" ]]; then
  mkdir -p "$RUNNER/Resources"; mv "$RUNNER/vulkan" "$RUNNER/Resources/vulkan"
  ok "Vulkan driver manifests moved to Resources/vulkan"
fi
if [[ ! -d "$RUNNER/Frameworks/renderer/d3dmetal-4.0b3" ]]; then
  info "Adding D3DMetal 4.0b3 from Template-${TEMPLATE_B3}"
  fetch "${SIKARUGIR_WRAPPER_URL}/Template-${TEMPLATE_B3}.tar.xz" "$CACHE/Template-${TEMPLATE_B3}.tar.xz" "$TEMPLATE_B3_SHA"
  tb="$(mktemp -d /tmp/sbt.XXXXXX)"
  tar -xJf "$CACHE/Template-${TEMPLATE_B3}.tar.xz" -C "$tb"
  rb="$(find "$tb" -maxdepth 1 -name 'Template-*.app' | head -1)/Contents/SharedSupport/renderer/d3dmetal"
  [[ -d "$rb/wine" ]] || die "Template-${TEMPLATE_B3} has no SharedSupport/renderer/d3dmetal"
  ditto "$rb" "$RUNNER/Frameworks/renderer/d3dmetal-4.0b3"; rm -rf "$tb"
  ok "D3DMetal 4.0b3 available (STEAMBRIDGE_D3DMETAL=d3dmetal-4.0b3)"
fi
if [[ ! -d "$RUNNER/Frameworks/renderer/dxmt-codegen" ]]; then
  tar -xJf "$REPO/assets/renderers/dxmt-codegen.tar.xz" -C "$RUNNER/Frameworks/renderer"
  ok "DXMT codegen build available (STEAMBRIDGE_DXMT=dxmt-codegen, patches/dxmt-codegen)"
fi
cp -f "$REPO/assets/runner.env" "$RUNNER/runner.env"
ln -sfn sikarugir-11 "$SB/runners/current"
cp -f "$REPO/assets/direct-shipping.sh" "$SB/direct-shipping.sh"; chmod +x "$SB/direct-shipping.sh"

info "Staging the Steam bridge"
fetch "$UPSTREAM_BRIDGE_ZIP_URL" "$CACHE/bridge-payload-v1.0.1.zip" "$UPSTREAM_BRIDGE_ZIP_SHA"
pz="$(mktemp -d /tmp/sbz.XXXXXX)"; unzip -q "$CACHE/bridge-payload-v1.0.1.zip" -d "$pz"
P="$(find "$pz" -type d -path '*payload/bridge' | head -1)"; [[ -n "$P" ]] || die "bridge payload missing from the release zip"
mkdir -p "$BRIDGE"/{x86_64-windows,i386-windows,x86_64-unix,aarch64-unix,wine/x86_64-windows,wine/i386-windows}
cp -f "$P/steam.exe" "$BRIDGE/steam.exe"
cp -f "$P/x86_64-windows-lsteamclient.dll" "$BRIDGE/lsteamclient.dll"
cp -f "$P/x86_64-windows-lsteamclient.dll" "$BRIDGE/x86_64-windows/lsteamclient.dll"
cp -f "$P/i386-windows-lsteamclient.dll" "$BRIDGE/i386-windows/lsteamclient.dll"
cp -f "$P/x86_64-unix-lsteamclient.so" "$BRIDGE/lsteamclient.so"
cp -f "$P/x86_64-unix-lsteamclient.so" "$BRIDGE/x86_64-unix/lsteamclient.so"
cp -f "$P/aarch64-unix-lsteamclient.so" "$BRIDGE/aarch64-unix/lsteamclient.so"
ln -sf lsteamclient.so "$BRIDGE/x86_64-unix/steamclient.so"; ln -sf lsteamclient.so "$BRIDGE/x86_64-unix/steamclient64.so"
ln -sf x86_64-unix/lsteamclient.so "$BRIDGE/steamclient.so"; ln -sf x86_64-unix/lsteamclient.so "$BRIDGE/steamclient64.so"
W="$RUNNER/lib/wine"
cp -f "$P/x86_64-windows-lsteamclient.dll" "$W/x86_64-windows/lsteamclient.dll"
if [[ -d "$W/i386-windows" ]]; then cp -f "$P/i386-windows-lsteamclient.dll" "$W/i386-windows/lsteamclient.dll"; fi
cp -f "$P/x86_64-unix-lsteamclient.so" "$W/x86_64-unix/lsteamclient.so"
ln -sf lsteamclient.so "$W/x86_64-unix/steamclient.so"; ln -sf lsteamclient.so "$W/x86_64-unix/steamclient64.so"
codesign -f -s - "$BRIDGE/lsteamclient.so" "$BRIDGE/x86_64-unix/lsteamclient.so" "$W/x86_64-unix/lsteamclient.so" 2>/dev/null
rm -rf "$pz"
( cd "$SRC" && BRIDGE_DIR="$BRIDGE" ./bridge/fetch-valve.sh --install >"$STATE/valve-fetch.log" 2>&1 ) \
  || { tail -15 "$STATE/valve-fetch.log"; die "Valve bridge fetch failed"; }
for f in steamclient64.dll steamclient.dll; do cp -p "$BRIDGE/$f" "$BRIDGE/$f.valve"; done
ok "Bridge: lsteamclient + Valve DLLs"

info "Patching Wine's ntdll.dll (Steam DRM fix)"
nt="$W/x86_64-windows/ntdll.dll"
[[ -f "$nt.steambridge-orig" ]] || cp -p "$nt" "$nt.steambridge-orig"
cp -f "$nt.steambridge-orig" "$nt"
python3 "$REPO/assets/apply-ntdll.py" "$REPO/assets/ntdll-sikarugir11.json" "$nt"
cp -f "$nt" "$BRIDGE/wine/x86_64-windows/ntdll.dll"
nt32="$W/i386-windows/ntdll.dll"
[[ -f "$nt32.steambridge-orig" ]] || cp -p "$nt32" "$nt32.steambridge-orig"
cp -f "$nt32.steambridge-orig" "$nt32"
python3 "$REPO/assets/apply-ntdll.py" "$REPO/assets/ntdll-sikarugir11-i386.json" "$nt32"
cp -f "$nt32" "$BRIDGE/wine/i386-windows/ntdll.dll"
ok "ntdll patched (runner + bridge, 64- and 32-bit)"

info "Injecting SteamBridge into Steam.app"
if [[ -z "$(steam_backup)" ]]; then
  bk="$STATE/backup-$(date +%Y%m%d%H%M%S)"; mkdir -p "$bk"; ditto "$STEAM_APP" "$bk/Steam.app"
  ok "Backed up stock Steam.app -> $bk"
fi
rm -f "$STEAM_APP/Contents/MacOS/$LEGACY_NAME.dylib"
cp -f "$SRC/out/$DYLIB_NAME" "$STEAM_APP/Contents/MacOS/$DYLIB_NAME"
PL="$STEAM_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$PL" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :LSEnvironment:DYLD_INSERT_LIBRARIES" "$PL" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:DYLD_INSERT_LIBRARIES string $STEAM_APP/Contents/MacOS/$DYLIB_NAME" "$PL"
codesign -f -s - "$STEAM_APP/Contents/MacOS/$DYLIB_NAME" 2>/dev/null
codesign -f -s - "$STEAM_APP/Contents/MacOS/steam_osx" 2>/dev/null
codesign -f -s - "$STEAM_APP" 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$STEAM_APP"
ok "Steam.app patched and re-signed"

mkdir -p "$COMPAT"
cat > "$COMPAT/compatibilitytool.vdf" <<EOF
"compatibilitytools"
{
  "compat_tools"
  {
    "$TOOL_NAME"
    {
      "install_path" "."
      "display_name" "SteamBridge"
      "from_oslist" "windows"
      "to_oslist" "macos"
    }
  }
}
EOF
printf '"manifest"\n{\n  "version" "2"\n  "commandline" "/run %%verb%%"\n}\n' > "$COMPAT/toolmanifest.vdf"
cp -f "$SRC/dylib/feats/compat_run.sh" "$COMPAT/run"; chmod +x "$COMPAT/run"
ok "Compatibility tool installed"

if (( SET_DEFAULT )) && [[ -f "$CONFIG_VDF" ]]; then
  backup_file "$CONFIG_VDF" default
  python3 - "$CONFIG_VDF" "$TOOL_NAME" <<'PY'
import re, sys
p, tool = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
entry = '\t\t\t\t\t"0"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"%s"\n\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"75"\n\t\t\t\t\t}\n' % tool
m = re.search(r'\n(\t*)"CompatToolMapping"\n\t*\{\n', s)
if m:
    blk = s[m.end():]
    m0 = re.match(r'\t*"0"\n\t*\{\n(?:.*\n)*?\t*\}\n', blk)
    if m0 and '"%s"' % tool in m0.group(0):
        print("default already set"); sys.exit(0)
    if m0:
        blk = blk[m0.end():]
    s = s[:m.end()] + entry + blk
else:
    m = re.search(r'\n\t\t\t"Steam"\n\t\t\t\{\n', s)
    if not m:
        print("could not find Steam block; set the default in Steam > Settings > Compatibility"); sys.exit(0)
    s = s[:m.end()] + '\t\t\t\t"CompatToolMapping"\n\t\t\t\t{\n' + entry + '\t\t\t\t}\n' + s[m.end():]
open(p, "w", encoding="utf-8").write(s); print("default set")
PY
  ok "SteamBridge is the default for Windows games (Settings > Compatibility)"
fi

t="$(STEAM_COMPAT_DATA_PATH=/tmp/sb_test "$COMPAT/run" getcompatpath 2>/dev/null || true)"
if [[ "$t" == /tmp/sb_test ]]; then ok "Run script responds"; else warn "Run script self-test returned '$t'"; fi

info "Done. Start Steam:  open -a Steam"
log "  Windows games now have a Play button. First launch of each game builds its prefix (about 30 s)."
log "  Per-game options go AFTER %command% in Launch Options, e.g.  %command% STEAMBRIDGE_RETINA=0"
log "  After a Steam client update breaks launching, re-run:  $0 --skip-build"
