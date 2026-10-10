#!/usr/bin/env bash
# setup-notproton.sh - free NotProton for NATIVE macOS Steam, on Sikarugir Wine 11.
#
# Result: /Applications/Steam.app runs Windows games itself, with a normal Play button.
# No Windows-Steam wrapper, no CrossOver licence.
#
# Pieces (all pinned + checksummed, all free):
#   NotProton fork  Maxyme/NotProton @ standalone-steam-gptk4 (GPL-3.0) + notproton/notproton-free.patch
#   Wine engine     Sikarugir WS12WineSikarugir11.0_1 (Wine 11)
#   Libraries       Sikarugir Template-1.0.21 Frameworks (D3DMetal 4.0b2, DXMT, MoltenVK, GStreamer)
#   Steam bridge    lsteamclient + steam.exe from the NotProton v1.0.1 release, Valve DLLs from Valve's CDN
#   ntdll patch     notproton/ntdll-sikarugir11.json (steamclient64 -> lsteamclient detour, keeps Steam DRM working)
#                   notproton/ntdll-sikarugir11-i386.json (the same detour for 32-bit games)
#
# Usage:  ./setup-notproton.sh [--force] [--no-default] [--skip-build]
#   --force       rebuild runner + source even if present
#   --no-default  don't make NotProton the default for all Windows games
#   --skip-build  reuse an existing build (for re-running after a Steam update)
#
# Idempotent. Backs up /Applications/Steam.app once before the first patch.
# Undo:  ./setup-notproton.sh --uninstall

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "${HERE}/lib.sh"

# ---- pins -------------------------------------------------------------------
FORK_URL="https://github.com/Maxyme/NotProton.git"
FORK_COMMIT="5b8d18683b619b66390be8cbcffc1fbf47e45971"
DOBBY_URL="https://github.com/jmpews/Dobby.git"
DOBBY_COMMIT="5dfc8546954ce3b3198132ab13fddb89ee92cdd7"
NP_ZIP_URL="https://github.com/NotProtonNot/NotProton/releases/download/v1.0.1/NotProton.zip"
NP_ZIP_SHA="1f1f4038ef44e48454c7746fad2b9964f7c82c4ae04af117e474a2d129eda52d"
NP_SIG_API="https://api.github.com/repos/NotProtonNot/NotProton/contents/signatures/macos.arm64"
ENGINE="WS12WineSikarugir11.0_1"
ENGINE_SHA="67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e"
TEMPLATE="1.0.21"
TEMPLATE_SHA="bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d"

# ---- paths ------------------------------------------------------------------
STEAM_APP="/Applications/Steam.app"
AS="$HOME/Library/Application Support"
NP="$AS/notproton"
FREE="$AS/notproton-free"
# Build tree must live on a path without spaces (the fork's Makefile/cmake can't quote them).
SRC="$HOME/Library/Caches/notproton-free/src"
CACHE="$HOME/Library/Caches/notproton-free/downloads"
RUNNER="$NP/runners/sikarugir-11"
BRIDGE="$NP/bridge"
STEAM_DIR="$AS/Steam"
COMPAT="$STEAM_DIR/compatibilitytools.d/notproton"
CONFIG_VDF="$STEAM_DIR/config/config.vdf"

FORCE=0; SET_DEFAULT=1; SKIP_BUILD=0; UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1;; --no-default) SET_DEFAULT=0;; --skip-build) SKIP_BUILD=1;;
    --uninstall) UNINSTALL=1;;
    -h|--help) sed -n '2,24p' "$0"; exit 0;;
    *) die "unknown option $a";;
  esac
done

sha_ok() { [[ "$(shasum -a 256 "$1" | cut -d' ' -f1)" == "$2" ]]; }

fetch() { # url dest sha
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
}

uninstall() {
  quit_steam
  local bk; bk="$(find "$FREE" -maxdepth 2 -path "*/backup-*/Steam.app" 2>/dev/null | head -1)"
  if [[ -n "$bk" ]]; then
    rm -rf "$STEAM_APP"; ditto "$bk" "$STEAM_APP"; ok "Restored stock Steam.app from $bk"
  else
    /usr/libexec/PlistBuddy -c "Delete :LSEnvironment:DYLD_INSERT_LIBRARIES" "$STEAM_APP/Contents/Info.plist" 2>/dev/null || true
    rm -f "$STEAM_APP/Contents/MacOS/notproton.dylib"; codesign -f -s - "$STEAM_APP" 2>/dev/null || true
    warn "No backup found; removed the injection by hand (reinstall Steam if it misbehaves)"
  fi
  rm -rf "$COMPAT"
  ok "Removed the compatibility tool. Runner, bridge and game prefixes are left in $NP"
  exit 0
}

# ---- 1. prerequisites -------------------------------------------------------
require_apple_silicon
require_macos_14_plus
[[ -d "$STEAM_APP" ]] || die "Install Steam for macOS first: https://store.steampowered.com/about/ (or: brew install --cask steam)"
(( UNINSTALL )) && uninstall
ensure_rosetta
for t in clang make git python3 curl tar codesign; do
  command -v "$t" >/dev/null || die "Missing '$t'. Run: xcode-select --install"
done
if ! command -v cmake >/dev/null; then
  command -v brew >/dev/null || die "cmake is needed to build Dobby; install Homebrew then re-run"
  info "Installing cmake (needed once to build the hook library)"; brew install cmake >/dev/null
fi
mkdir -p "$CACHE" "$NP" "$FREE" "$(dirname "$SRC")"
ok "Prerequisites present"

quit_steam

# ---- 2. NotProton fork: fetch, patch, build ----------------------------------
if (( ! SKIP_BUILD )); then
  info "Building the free NotProton fork"
  if (( FORCE )) || [[ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$FORK_COMMIT" ]]; then
    rm -rf "$SRC"; git clone -q "$FORK_URL" "$SRC"; git -C "$SRC" checkout -q "$FORK_COMMIT"
  fi
  git -C "$SRC" checkout -q -- dylib/feats/compat_run.sh
  git -C "$SRC" apply "$REPO/notproton/notproton-free.patch"
  ok "Fork @ ${FORK_COMMIT:0:7} + notproton-free.patch"
  if [[ ! -d "$SRC/vendor/dobby/.git" ]]; then
    git clone -q "$DOBBY_URL" "$SRC/vendor/dobby"; git -C "$SRC/vendor/dobby" checkout -q "$DOBBY_COMMIT"
  fi
  ( cd "$SRC"
    [[ -f build/dobby/libdobby.a ]] || make dobby >"$FREE/build.log" 2>&1 || { tail -20 "$FREE/build.log"; exit 1; }
    make all helpers-install sigdb-install >>"$FREE/build.log" 2>&1 || { tail -20 "$FREE/build.log"; exit 1; } )
  ok "Built notproton.dylib (log: $FREE/build.log)"
fi
[[ -f "$SRC/out/notproton.dylib" ]] || die "No build at $SRC/out (run without --skip-build)"

# Newest Steam-client signatures from upstream (lets the dylib match new Steam builds).
sigdir="$NP/signatures/macos.arm64"; mkdir -p "$sigdir"
for u in $(curl -fsSL "$NP_SIG_API" 2>/dev/null | sed -n 's/.*"download_url": *"\([^"]*\.json\)".*/\1/p'); do
  curl -fsSL -o "$sigdir/$(basename "$u")" "$u" || true
done
ok "Signatures: $(find "$sigdir" -name "*.json" | wc -l | tr -d ' ') Steam builds"

# ---- 3. Wine 11 runner ---------------------------------------------------------
if (( FORCE )) || [[ ! -x "$RUNNER/bin/wine" ]]; then
  info "Assembling the Wine 11 runner"
  fetch "${SIKARUGIR_ENGINES_URL}/${ENGINE}.tar.xz" "$CACHE/${ENGINE}.tar.xz" "$ENGINE_SHA"
  fetch "${SIKARUGIR_WRAPPER_URL}/Template-${TEMPLATE}.tar.xz" "$CACHE/Template-${TEMPLATE}.tar.xz" "$TEMPLATE_SHA"
  tmp="$(mktemp -d /tmp/npf.XXXXXX)"; trap 'rm -rf "$tmp"' EXIT
  tar -xJf "$CACHE/${ENGINE}.tar.xz" -C "$tmp"
  tar -xJf "$CACHE/Template-${TEMPLATE}.tar.xz" -C "$tmp"
  T="$(find "$tmp" -maxdepth 1 -name 'Template-*.app' | head -1)/Contents"
  [[ -d "$tmp/wswine.bundle/bin" && -d "$T/Frameworks" ]] || die "Unexpected engine/template layout"
  rm -rf "$RUNNER"; mkdir -p "$RUNNER"
  ditto "$tmp/wswine.bundle" "$RUNNER"
  ditto "$T/Frameworks" "$RUNNER/Frameworks"
  [[ -d "$T/Resources/vulkan" ]] && ditto "$T/Resources/vulkan" "$RUNNER/Resources/vulkan"
  ok "Runner: $("$RUNNER/bin/wine" --version 2>/dev/null) + Template-${TEMPLATE} libraries"
fi
# The Vulkan ICD manifests point at ../../../Frameworks, which only resolves from Resources/vulkan.
if [[ -d "$RUNNER/vulkan" && ! -d "$RUNNER/Resources/vulkan" ]]; then
  mkdir -p "$RUNNER/Resources"; mv "$RUNNER/vulkan" "$RUNNER/Resources/vulkan"
fi
cp -f "$REPO/notproton/runner.env" "$RUNNER/runner.env"
ln -sfn sikarugir-11 "$NP/runners/current"

# ---- 4. Steam bridge ------------------------------------------------------------
info "Staging the Steam bridge"
fetch "$NP_ZIP_URL" "$CACHE/NotProton-v1.0.1.zip" "$NP_ZIP_SHA"
pz="$(mktemp -d /tmp/npz.XXXXXX)"; unzip -q "$CACHE/NotProton-v1.0.1.zip" -d "$pz"
P="$(find "$pz" -type d -path '*payload/bridge' | head -1)"; [[ -n "$P" ]] || die "bridge payload missing from NotProton.zip"
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
[[ -d "$W/i386-windows" ]] && cp -f "$P/i386-windows-lsteamclient.dll" "$W/i386-windows/lsteamclient.dll"
cp -f "$P/x86_64-unix-lsteamclient.so" "$W/x86_64-unix/lsteamclient.so"
ln -sf lsteamclient.so "$W/x86_64-unix/steamclient.so"; ln -sf lsteamclient.so "$W/x86_64-unix/steamclient64.so"
codesign -f -s - "$BRIDGE/lsteamclient.so" "$BRIDGE/x86_64-unix/lsteamclient.so" "$W/x86_64-unix/lsteamclient.so" 2>/dev/null
rm -rf "$pz"
# Valve's own steamclient/tier0/vstdlib + legacycompat, hash-checked against the fork's manifest.
( cd "$SRC" && BRIDGE_DIR="$BRIDGE" ./bridge/fetch-valve.sh --install >"$FREE/valve-fetch.log" 2>&1 ) \
  || { tail -15 "$FREE/valve-fetch.log"; die "Valve bridge fetch failed"; }
# Games must load VALVE's steamclient64 (Steam DRM checks it); the ntdll detour reroutes it.
# fetch-valve.sh just (re)installed the hash-verified Valve copies; keep a pristine .valve beside them.
for f in steamclient64.dll steamclient.dll; do cp -p "$BRIDGE/$f" "$BRIDGE/$f.valve"; done
ok "Bridge: lsteamclient + Valve DLLs"

# ---- 5. ntdll detour -------------------------------------------------------------
info "Patching Wine's ntdll.dll (Steam DRM fix)"
nt="$W/x86_64-windows/ntdll.dll"
[[ -f "$nt.notproton-orig" ]] || cp -p "$nt" "$nt.notproton-orig"
cp -f "$nt.notproton-orig" "$nt"
python3 "$REPO/notproton/apply-ntdll.py" "$REPO/notproton/ntdll-sikarugir11.json" "$nt"
cp -f "$nt" "$BRIDGE/wine/x86_64-windows/ntdll.dll"
nt32="$W/i386-windows/ntdll.dll"
[[ -f "$nt32.notproton-orig" ]] || cp -p "$nt32" "$nt32.notproton-orig"
cp -f "$nt32.notproton-orig" "$nt32"
python3 "$REPO/notproton/apply-ntdll.py" "$REPO/notproton/ntdll-sikarugir11-i386.json" "$nt32"
cp -f "$nt32" "$BRIDGE/wine/i386-windows/ntdll.dll"
ok "ntdll patched (runner + bridge, 64- and 32-bit)"

# ---- 6. Patch Steam.app ------------------------------------------------------------
info "Injecting NotProton into Steam.app"
if [[ -z "$(find "$FREE" -maxdepth 2 -path "*/backup-*/Steam.app" 2>/dev/null | head -1)" ]]; then
  bk="$FREE/backup-$(date +%Y%m%d%H%M%S)"; mkdir -p "$bk"; ditto "$STEAM_APP" "$bk/Steam.app"
  ok "Backed up stock Steam.app -> $bk"
fi
cp -f "$SRC/out/notproton.dylib" "$STEAM_APP/Contents/MacOS/notproton.dylib"
PL="$STEAM_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$PL" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :LSEnvironment:DYLD_INSERT_LIBRARIES" "$PL" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:DYLD_INSERT_LIBRARIES string $STEAM_APP/Contents/MacOS/notproton.dylib" "$PL"
codesign -f -s - "$STEAM_APP/Contents/MacOS/notproton.dylib" 2>/dev/null
codesign -f -s - "$STEAM_APP/Contents/MacOS/steam_osx" 2>/dev/null
codesign -f -s - "$STEAM_APP" 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$STEAM_APP"
ok "Steam.app patched and re-signed"

# ---- 7. Compatibility tool -----------------------------------------------------------
mkdir -p "$COMPAT"
cat > "$COMPAT/compatibilitytool.vdf" <<'EOF'
"compatibilitytools"
{
  "compat_tools"
  {
    "notproton"
    {
      "install_path" "."
      "display_name" "NotProton (free, Wine 11)"
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
  cp -p "$CONFIG_VDF" "$CONFIG_VDF.bak-notproton-free"
  python3 - "$CONFIG_VDF" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
entry = '\t\t\t\t\t"0"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"notproton"\n\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"75"\n\t\t\t\t\t}\n'
m = re.search(r'\n(\t*)"CompatToolMapping"\n\t*\{\n', s)
if m:
    blk = s[m.end():]
    m0 = re.match(r'\t*"0"\n\t*\{\n(?:.*\n)*?\t*\}\n', blk)
    if m0 and '"notproton"' in m0.group(0):
        print("default already notproton"); sys.exit(0)
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
  ok "NotProton is the default for Windows games (Settings > Compatibility)"
fi

# ---- 8. verify ------------------------------------------------------------------------
t="$(STEAM_COMPAT_DATA_PATH=/tmp/np_test "$COMPAT/run" getcompatpath 2>/dev/null || true)"
if [[ "$t" == /tmp/np_test ]]; then ok "Run script responds"; else warn "Run script self-test returned '$t'"; fi

info "Done. Start Steam:  open -a Steam"
log "  Windows games now have a Play button. First launch of each game builds its prefix (~30 s)."
log "  Per-game options go AFTER %command% in Launch Options, e.g.  %command% NOTPROTON_RETINA=0"
log "  After a Steam client update breaks launching, re-run:  $0 --skip-build"
