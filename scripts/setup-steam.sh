#!/usr/bin/env bash
# setup-steam.sh — build a working Steam-for-Windows wrapper the hard-won way.
#
# This automates the exact sequence that actually works on Apple Silicon in 2026,
# including every fix we discovered the painful way:
#   - Latest wrapper template + best Wine engine (Sikarugir 11 / Wine 11) so the CEF webhelper doesn't stall
#   - Launch target = steam.exe (NOT the installer) so it stops re-running setup
#   - `-tcp` launch flag so you don't hit "Unexpected Transport Error (0x3008)"
#   - Freshest Apple D3DMetal overlaid for DX11/12 games
#
# Sikarugir Creator has a GUI; there is no fully-headless wrapper-create API.
# So this script does the automatable 90% and tells you the 2 GUI clicks needed.
#
# Usage:  ./setup-steam.sh
#         ./setup-steam.sh --engine WS12WineCX24.0.7_7   # override engine

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"

ENGINE="$BEST_ENGINE"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine) ENGINE="$2"; shift 2;;
    *) shift;;
  esac
done

STEAM_URL="https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe"

step_download_steamsetup() {
  local dest="${HOME}/Downloads/SteamSetup.exe"
  if [[ -f "$dest" ]]; then ok "SteamSetup.exe present"; return 0; fi
  info "Downloading SteamSetup.exe…"
  curl -fsSL -o "$dest" "$STEAM_URL" && ok "Downloaded -> $dest"
}

step_guide_create_wrapper() {
  local w; w="$(find_wrapper Steam || true)"
  if [[ -n "$w" ]]; then ok "Steam wrapper already exists: $w"; return 0; fi

  cat <<EOF

${C_YEL}${C_B}MANUAL STEP (one time, ~30s in Sikarugir Creator GUI):${C_RESET}
  1. Open "Sikarugir Creator" (installed in /Applications).
  2. Create a new blank wrapper.
     - Engine: choose ${C_B}${ENGINE}${C_RESET}  (best; this script re-applies it anyway)
     - Save As: ${C_B}Steam.app${C_RESET}   Where: ${C_B}Sikarugir${C_RESET} (default)
  3. When Configure opens, set:
     - Windows app: ${C_B}"Z:\\Users\\$USER\\Downloads\\SteamSetup.exe"${C_RESET}  (Browse)
     - Tick ${C_B}Direct3D to Metal (D3DMetal)${C_RESET}
  4. Click ${C_B}Install Software${C_RESET} -> run the Steam installer -> Finish.

Then re-run this script; it will apply all the fixes automatically.
EOF
  return 1
}

step_update_template() {
  # Newer engines (Wine 11) need a newer wrapper template; newer templates also ship
  # newer D3DMetal/DXMT. Safe: keeps SharedSupport (engine, prefix, games).
  bash "${HERE}/update-wrapper.sh" Steam || warn "Template update failed; continuing with the current one"
}

step_apply_engine() {
  local w="$1" wine_dir cur want
  wine_dir="$(wrapper_wine_dir "$w")"
  cur=""; [[ -f "${wine_dir}/version" ]] && cur="$(cat "${wine_dir}/version")"
  # "WS12WineSikarugir11.0_1" -> "sikarugir 11.0 (revision 1)"
  want="$(printf '%s' "$ENGINE" | sed -E 's/^WS12WineSikarugir([0-9]+\.[0-9]+)(_([0-9]+))?$/sikarugir \1 (revision \3)/' | tr '[:upper:]' '[:lower:]')"
  if [[ -n "$cur" ]] && printf '%s' "$cur" | tr '[:upper:]' '[:lower:]' | grep -qF "${want% (revision )}"; then
    ok "Wine engine already ${cur}"
    return 0
  fi
  bash "${HERE}/swap-engine.sh" "$ENGINE" Steam
}

step_fix_launch_target() {
  local w="$1" dc; dc="$(wrapper_drive_c "$w")"
  local steam_exe='C:\Program Files (x86)\Steam\steam.exe'
  [[ -f "${dc}/Program Files (x86)/Steam/steam.exe" ]] || { warn "steam.exe not found — is Steam installed in the wrapper yet?"; return 1; }
  info "Pointing wrapper launch target at steam.exe with -tcp flag…"
  local f
  for f in "${dc}/"exec*.bat; do
    [[ -f "$f" ]] || continue
    printf '"%s" -tcp \n' "$steam_exe" > "$f"
  done
  ok "Launch target fixed (steam.exe -tcp) — no more installer loop / 0x3008"
}

step_overlay_d3dmetal() {
  # Only overlay YOUR extracted D3DMetal if it is newer than what the wrapper already has.
  # (Sikarugir templates now bundle recent D3DMetal builds, e.g. 4.0b2 in template 1.0.21.)
  local w="$1" ext mine theirs
  ext="$(wrapper_d3dmetal_external "$w")"
  [[ -x "${GPTK_EXTRACT_DIR}/lib/external/D3DMetal.framework/Versions/A/D3DMetal" ]] \
    || { log "  No extracted D3DMetal; using the wrapper's bundled $(d3dmetal_version "$ext")"; return 0; }
  mine="$(d3dmetal_version "${GPTK_EXTRACT_DIR}/lib/external")"
  theirs="$(d3dmetal_version "$ext")"
  if [[ -n "$theirs" ]] && ! version_gt "$mine" "$theirs"; then
    ok "Wrapper D3DMetal ${theirs} is as new or newer than yours (${mine:-?}); not overlaying"
    return 0
  fi
  info "Overlaying D3DMetal ${mine} over ${theirs:-none}…"
  [[ -d "$ext" ]] || mkdir -p "$ext"
  cp -R "$ext" "${ext}.bak-$(date +%Y%m%d)" 2>/dev/null || true
  ditto "${GPTK_EXTRACT_DIR}/lib/external/" "${ext}/"
  ok "D3DMetal now $(d3dmetal_version "$ext")"
}

step_clear_caches() {
  local w="$1" sd; sd="$(wrapper_steamdir "$w")"
  rm -rf "${sd}/config/htmlcache" "${sd}/appcache/httpcache" 2>/dev/null || true
  ok "Cleared webhelper caches (fresh start)"
}

main() {
  require_apple_silicon
  require_macos_14_plus

  step_download_steamsetup

  local w; w="$(find_wrapper Steam || true)"
  if [[ -z "$w" ]]; then
    step_guide_create_wrapper || exit 0   # exits 0: user must do GUI step then re-run
  fi
  w="$(find_wrapper Steam)"; [[ -n "$w" ]] || die "Steam wrapper still not found"

  info "Configuring wrapper: $w"
  step_update_template
  step_apply_engine "$w"
  step_overlay_d3dmetal "$w"
  step_fix_launch_target "$w" || { warn "Install Steam via Sikarugir 'Install Software' first, then re-run."; exit 0; }
  step_clear_caches "$w"

  cat <<EOF

${C_GRN}${C_B}Steam wrapper ready.${C_RESET}
  Engine:    $(cat "$(wrapper_wine_dir "$w")/version")
  Template:  $(wrapper_template_version "$w")
  D3DMetal:  $(d3dmetal_version "$(wrapper_d3dmetal_external "$w")")
  Launch:    steam.exe -tcp

Launch it:  open "$w"
First run rebuilds the webhelper (~30-40s) then shows the login screen.
If you see "0x3008" once, pick "VO: Continue Anyway".
EOF
}
main "$@"
