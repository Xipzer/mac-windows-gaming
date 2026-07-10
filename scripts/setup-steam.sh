#!/usr/bin/env bash
# setup-steam.sh — build a working Steam-for-Windows wrapper the hard-won way.
#
# This automates the exact sequence that actually works on Apple Silicon in 2026,
# including every fix we discovered the painful way:
#   - Best Wine engine (Sikarugir 10 / Wine 10) so the CEF webhelper doesn't stall
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

step_apply_engine() {
  local w="$1" wine_dir engine_tar
  wine_dir="$(wrapper_wine_dir "$w")"
  engine_tar="${SIKARUGIR_ENGINES_DIR}/${ENGINE}.tar.xz"

  local cur=""; [[ -f "${wine_dir}/version" ]] && cur="$(cat "${wine_dir}/version")"
  if printf '%s' "$cur" | grep -qi "sikarugir 10"; then
    ok "Wine engine already Sikarugir 10 (Wine 10)"
    return 0
  fi

  [[ -f "$engine_tar" ]] || { warn "Engine ${ENGINE} not cached yet (open Sikarugir once to download it), skipping swap"; return 0; }

  info "Applying Wine engine ${ENGINE} (was: ${cur:-none})…"
  kill_wine
  local tmp; tmp="$(mktemp -d /tmp/eng.XXXXXX)"
  tar -xJf "$engine_tar" -C "$tmp"
  rm -rf "${w}/Contents/SharedSupport/wine.prev-backup" 2>/dev/null || true
  [[ -d "$wine_dir" ]] && mv "$wine_dir" "${w}/Contents/SharedSupport/wine.prev-backup"
  mv "${tmp}/wswine.bundle" "$wine_dir"
  rm -rf "$tmp"
  ok "Engine now: $(cat "${wine_dir}/version")"
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
  local w="$1" ext; ext="$(wrapper_d3dmetal_external "$w")"
  [[ -x "${GPTK_EXTRACT_DIR}/lib/external/D3DMetal.framework/Versions/A/D3DMetal" ]] \
    || { warn "No extracted D3DMetal yet; run fetch-d3dmetal.sh first (skipping overlay)"; return 0; }
  info "Overlaying freshest Apple D3DMetal into the wrapper…"
  [[ -d "$ext" ]] || mkdir -p "$ext"
  cp -R "$ext" "${ext}.bak-$(date +%Y%m%d)" 2>/dev/null || true
  ditto "${GPTK_EXTRACT_DIR}/lib/external/" "${ext}/"
  ok "D3DMetal overlaid ($(ls -la "${ext}/D3DMetal.framework/Versions/A/D3DMetal" | awk '{print $5}') bytes)"
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
  step_apply_engine "$w"
  step_overlay_d3dmetal "$w"
  step_fix_launch_target "$w" || { warn "Install Steam via Sikarugir 'Install Software' first, then re-run."; exit 0; }
  step_clear_caches "$w"

  cat <<EOF

${C_GRN}${C_B}Steam wrapper ready.${C_RESET}
  Engine:    $(cat "$(wrapper_wine_dir "$w")/version")
  D3DMetal:  overlaid (freshest)
  Launch:    steam.exe -tcp

Launch it:  open "$w"
First run rebuilds the webhelper (~30-40s) then shows the login screen.
If you see "0x3008" once, pick "VO: Continue Anyway".
EOF
}
main "$@"
