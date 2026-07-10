#!/usr/bin/env bash
# doctor.sh — inspect the current environment and report what's installed / current.
# Read-only. Great for humans debugging and for agents to gather state before acting.

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
  ok "present ($(ls -la "${GPTK_EXTRACT_DIR}/lib/external/D3DMetal.framework/Versions/A/D3DMetal" | awk '{print $5}') bytes) at ${GPTK_EXTRACT_DIR}/lib/external"
else
  warn "not extracted — run scripts/fetch-d3dmetal.sh"
fi

info "Sikarugir engines cached"
if [[ -d "$SIKARUGIR_ENGINES_DIR" ]]; then
  ls "$SIKARUGIR_ENGINES_DIR"/*.tar.xz 2>/dev/null | sed 's|.*/|  |' || warn "  none"
else
  warn "  no engines dir yet (open Sikarugir once)"
fi

info "Steam wrapper"
w="$(find_wrapper Steam || true)"
if [[ -n "${w:-}" ]]; then
  ok "found: $w"
  [[ -f "$(wrapper_wine_dir "$w")/version" ]] && log "  Engine:   $(cat "$(wrapper_wine_dir "$w")/version")"
  [[ -f "$(wrapper_dxmt_dir "$w")/version" ]]  && log "  DXMT:     $(cat "$(wrapper_dxmt_dir "$w")/version")"
  ext="$(wrapper_d3dmetal_external "$w")"
  [[ -x "${ext}/D3DMetal.framework/Versions/A/D3DMetal" ]] && \
    log "  D3DMetal: $(ls -la "${ext}/D3DMetal.framework/Versions/A/D3DMetal" | awk '{print $5}') bytes (overlaid)"
  sd="$(wrapper_steamdir "$w")"
  if [[ -d "${sd}/steamapps/common" ]]; then
    log "  Games:"
    du -sh "${sd}/steamapps/common"/* 2>/dev/null | sort -rh | sed 's/^/    /' | head -20
  fi
else
  warn "no Steam wrapper yet — run scripts/setup-steam.sh"
fi

info "Native macOS Steam client (separate from the wrapper)"
[[ -d "/Applications/Steam.app" || -d "${HOME}/Applications/Steam.app" ]] \
  && ok "native Steam.app present (use for games with native Mac ports)" \
  || log "  not installed (optional; for native ports like Valheim/Tomb Raider)"
