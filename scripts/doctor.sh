#!/usr/bin/env bash

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
source "$HERE/lib.sh"

RUNNER="$SB/runners/current"
BRIDGE="$SB/bridge"
COMPATDATA="$STEAMAPPS/compatdata"
issues=0
bad() { warn "$*"; issues=$((issues + 1)); }

info "System"
log "  macOS:  $(sw_vers -productVersion) (build $(sw_vers -buildVersion))"
log "  Chip:   $(sysctl -n machdep.cpu.brand_string 2>/dev/null) ($(uname -m)), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
if /usr/bin/pgrep -q oahd; then ok "Rosetta 2"; else bad "Rosetta 2 not installed -> ./install.sh"; fi

info "Tooling"
if have brew; then ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"; else bad "Homebrew missing -> ./install.sh"; fi
for t in cmake clang git python3; do
  if have "$t"; then ok "$t"; else bad "$t missing"; fi
done
if have brew; then
  h="$(brew list --cask --versions "$HEROIC_CASK" 2>/dev/null || true)"
  if [[ -n "$h" ]]; then ok "Heroic ${h#* }"; else log "  Heroic not installed (optional: Epic/GOG/Amazon)"; fi
fi

info "Steam.app"
if [[ ! -d "$STEAM_APP" ]]; then
  bad "Steam for macOS not installed -> ./install.sh"
else
  ok "present"
  b="$(steam_client_build)"
  [[ -n "$b" ]] && log "  client build: $b"
  inj="$(/usr/libexec/PlistBuddy -c "Print :LSEnvironment:DYLD_INSERT_LIBRARIES" "$STEAM_APP/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$inj" == "$STEAM_APP/Contents/MacOS/$DYLIB_NAME" && -f "$inj" ]]; then
    ok "$DYLIB_NAME injected"
  elif [[ -n "$inj" ]]; then
    bad "Steam.app injects '$inj', not $DYLIB_NAME -> scripts/setup.sh --migrate, then scripts/setup.sh"
  else
    bad "$DYLIB_NAME not injected (Steam update replaced Info.plist?) -> scripts/setup.sh --skip-build"
  fi
  bk="$(find "$SB/setup" -maxdepth 2 -path "*/backup-*/Steam.app" 2>/dev/null | head -1)"
  if [[ -n "$bk" ]]; then ok "stock backup: $bk"; else log "  no stock Steam.app backup yet"; fi
  n="$(find "$SB/signatures/macos.arm64" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  log "  signature sets: $n (re-run scripts/setup.sh --skip-build after a Steam update)"
fi

info "Runner"
if [[ -x "$RUNNER/bin/wine" ]]; then
  ok "$(readlink "$RUNNER"): $("$RUNNER/bin/wine" --version 2>/dev/null)"
  if [[ -f "$RUNNER/runner.env" ]]; then ok "runner.env"; else bad "runner.env missing -> scripts/setup.sh --skip-build"; fi
  nt="$RUNNER/lib/wine/x86_64-windows/ntdll.dll"
  if [[ -f "$nt.steambridge-orig" ]] && ! cmp -s "$nt" "$nt.steambridge-orig"; then ok "ntdll patched"
  else bad "ntdll not patched -> scripts/setup.sh --skip-build"; fi
  r="$(find "$RUNNER/Frameworks/renderer" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')"
  log "  renderers: ${r:-none}"
else
  bad "no runner at $RUNNER -> scripts/setup.sh"
fi

info "Steam bridge"
for f in steamclient64.dll steamclient64.dll.valve steamclient.dll.valve lsteamclient.dll lsteamclient.so steam.exe; do
  [[ -e "$BRIDGE/$f" ]] || bad "bridge/$f missing -> scripts/setup.sh --skip-build"
done
if [[ -f "$BRIDGE/steamclient64.dll.valve" ]]; then
  if cmp -s "$BRIDGE/steamclient64.dll" "$BRIDGE/steamclient64.dll.valve"; then ok "steamclient64.dll is Valve's"
  else bad "bridge/steamclient64.dll differs from Valve's copy (DRM error 3:0000065432) -> scripts/setup.sh --skip-build"; fi
fi

info "Compatibility tool"
if [[ -x "$COMPAT/run" && -f "$COMPAT/compatibilitytool.vdf" ]]; then ok "$TOOL_NAME installed"
else bad "compat tool missing at $COMPAT -> scripts/setup.sh --skip-build"; fi
if [[ -f "$CONFIG_VDF" ]] && grep -A5 '"CompatToolMapping"' "$CONFIG_VDF" | grep -q "\"$TOOL_NAME\""; then
  ok "default for Windows games"
else
  log "  not the global default (fine if set per game)"
fi

info "Helpers"
for f in dispmode prio-shim.dylib direct-shipping.sh; do
  if [[ -e "$SB/$f" ]]; then ok "$f"; else bad "$f missing -> scripts/setup.sh --skip-build"; fi
done

info "Per-game profiles (configs/games -> compatdata/<appid>/steambridge.env)"
for f in "$REPO"/configs/games/*.env; do
  [[ -f "$f" ]] || continue
  id="$(basename "$f" .env)"; dst="$COMPATDATA/$id/steambridge.env"
  if [[ ! -d "$COMPATDATA/$id" ]]; then log "  $id: game never launched"
  elif [[ ! -f "$dst" ]]; then bad "$id: profile not installed -> scripts/apply-game-configs.sh"
  elif cmp -s "$f" "$dst"; then ok "$id: matches repo"
  else warn "$id: differs from repo (local tuning or stale) -> diff '$f' '$dst'"; fi
done
for d in "$COMPATDATA"/*/; do
  d="${d%/}"
  [[ -f "$d/steambridge.env" ]] || continue
  id="$(basename "$d")"
  [[ -f "$REPO/configs/games/$id.env" ]] || log "  $id: local profile only (not in configs/games)"
done

info "Games"
if [[ -d "$STEAMAPPS/common" ]]; then
  du -sh "$STEAMAPPS/common"/* 2>/dev/null | sort -rh | head -20 | sed 's/^/    /'
fi
for d in "$COMPATDATA"/*/; do
  d="${d%/}"; l="$d/steambridge-run.log"
  [[ -f "$l" ]] && log "  $(basename "$d"): last run $(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$l")  ($l)"
done

info "Legacy wrapper (optional)"
w="$HOME/Applications/Sikarugir/Steam.app"
if [[ -d "$w" ]]; then
  ok "found: $w (don't run it alongside Mac Steam)"
  [[ -f "$w/Contents/SharedSupport/wine/version" ]] && log "  engine: $(cat "$w/Contents/SharedSupport/wine/version")"
else
  log "  none (not needed)"
fi

info "Logs"
log "  per game:  $COMPATDATA/<appid>/steambridge-run.log"
log "  Wine:      $SB/launchers/<appid>/steambridge-wine.log"
log "  dylib:     $SB/steambridge.log"
log "  installer: $SB/setup/build.log"

echo
if (( issues )); then warn "$issues issue(s) found"; exit 1; fi
ok "No issues found"
