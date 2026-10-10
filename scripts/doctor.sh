#!/usr/bin/env bash
# doctor.sh - report what's installed and which versions. Read-only.
# Run before debugging or before an agent acts.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"

info "System"
log "  macOS:  $(sw_vers -productVersion) (build $(sw_vers -buildVersion))"
log "  Arch:   $(uname -m)"
log "  Chip:   $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
log "  RAM:    $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
/usr/bin/pgrep -q oahd && ok "Rosetta 2 present" || warn "Rosetta 2 NOT installed"

info "Tooling"
have brew && ok "Homebrew $(brew --version | head -1 | awk '{print $2}')" || warn "Homebrew missing"
for t in cabextract 7z; do have "$t" && ok "$t" || warn "$t missing"; done
brew list --cask --versions heroic 2>/dev/null | sed 's/^/  Heroic:    /' || warn "Heroic missing"
brew list --cask --versions sikarugir 2>/dev/null | sed 's/^/  Sikarugir: /' || warn "Sikarugir missing"

info "D3DMetal (extracted)"
if [[ -x "${GPTK_EXTRACT_DIR}/lib/external/D3DMetal.framework/Versions/A/D3DMetal" ]]; then
  ok "present: $(d3dmetal_version "${GPTK_EXTRACT_DIR}/lib/external") at ${GPTK_EXTRACT_DIR}/lib/external"
else
  log "  not extracted (optional - recent wrapper templates bundle D3DMetal)"
fi

info "Sikarugir engines cached"
if [[ -d "$SIKARUGIR_ENGINES_DIR" ]]; then
  ls "$SIKARUGIR_ENGINES_DIR"/*.tar.xz 2>/dev/null | sed 's|.*/|  |' || warn "  none"
else
  warn "  no engines dir yet (open Sikarugir once)"
fi

info "Native Steam + free NotProton (default route)"
AS="${HOME}/Library/Application Support"
if [[ -d /Applications/Steam.app ]]; then
  ok "Steam.app present"
  if /usr/libexec/PlistBuddy -c "Print :LSEnvironment:DYLD_INSERT_LIBRARIES" /Applications/Steam.app/Contents/Info.plist 2>/dev/null | grep -q notproton; then
    ok "NotProton injected"
  else
    warn "NotProton not injected -> scripts/setup-notproton.sh"
  fi
  r="${AS}/notproton/runners/current"
  [[ -x "$r/bin/wine" ]] && ok "runner: $(readlink "$r") ($("$r/bin/wine" --version 2>/dev/null))" || warn "no runner -> scripts/setup-notproton.sh"
  icd="$r/Resources/vulkan/icd.d/kosmickrisp_mesa_icd.json"
  lib="$(sed -n 's/.*"library_path": *"\([^"]*\)".*/\1/p' "$icd" 2>/dev/null)"
  [[ -n "$lib" && -f "$(dirname "$icd")/$lib" ]] && ok "Vulkan driver resolves" || warn "Vulkan driver missing or unresolvable -> scripts/setup-notproton.sh"
  [[ -x "${AS}/Steam/compatibilitytools.d/notproton/run" ]] && ok "compat tool installed" || warn "compat tool missing"
  b="$(grep -m1 -oE '[0-9]{9,}' "${AS}/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx.manifest" 2>/dev/null || true)"
  [[ -n "$b" ]] && log "  Steam client build: $b"
  log "  Steam signatures known: $(find "${AS}/notproton/signatures/macos.arm64" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ -d "${AS}/Steam/steamapps/common" ]]; then
    log "  Games:"
    du -sh "${AS}/Steam/steamapps/common"/* 2>/dev/null | sort -rh | sed 's/^/    /' | head -20
  fi
else
  warn "Steam for macOS not installed -> ./install.sh"
fi

info "Legacy Steam wrapper (optional)"
w="$(find_wrapper Steam || true)"
if [[ -n "${w:-}" ]]; then
  ok "found: $w  (don't run it alongside Mac Steam)"
  tv="$(wrapper_template_version "$w")"
  log "  Template: ${tv:-?}"
  [[ -f "$(wrapper_wine_dir "$w")/version" ]] && log "  Engine:   $(cat "$(wrapper_wine_dir "$w")/version")"
else
  log "  none (not needed for the NotProton route)"
fi
