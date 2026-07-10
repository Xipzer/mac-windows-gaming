#!/usr/bin/env bash
# swap-engine.sh — change the Wine engine of a Sikarugir wrapper from the CLI.
#
# Engines and when to use them (see docs/ENGINES.md for the full write-up):
#   WS12WineSikarugir10.0_6  Wine 10  ★ best all-rounder + best Steam webhelper. DEFAULT.
#   WS12WineCX24.0.7_7       Wine 9   CrossOver's patched Wine. Mature fallback.
#   WS12WineGPTK1.1_3        Wine 7   Old. D3DMetal specialist; BAD for modern Steam UI.
#
# The render backend (D3DMetal/DXMT/DXVK) is INDEPENDENT of the engine (Configure checkbox).
#
# Usage:  ./swap-engine.sh <EngineName> [WrapperName]
#   e.g.  ./swap-engine.sh WS12WineSikarugir10.0_6 Steam

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"

ENGINE="${1:-$BEST_ENGINE}"
WRAPPER_NAME="${2:-Steam}"

w="$(find_wrapper "$WRAPPER_NAME")" || true
[[ -n "${w:-}" ]] || die "Wrapper '${WRAPPER_NAME}' not found under ${SIKARUGIR_WRAPPERS_DIR}"

engine_tar="${SIKARUGIR_ENGINES_DIR}/${ENGINE}.tar.xz"
[[ -f "$engine_tar" ]] || die "Engine ${ENGINE} not cached. Open Sikarugir and download it once (Tools -> Change Engine)."

wine_dir="$(wrapper_wine_dir "$w")"
cur=""; [[ -f "${wine_dir}/version" ]] && cur="$(cat "${wine_dir}/version")"
info "Swapping engine on '${WRAPPER_NAME}': ${cur:-none} -> ${ENGINE}"

kill_wine
tmp="$(mktemp -d /tmp/eng.XXXXXX)"
tar -xJf "$engine_tar" -C "$tmp"
ts="$(date +%Y%m%d%H%M%S)"
[[ -d "$wine_dir" ]] && mv "$wine_dir" "${wine_dir}.backup-${ts}"
mv "${tmp}/wswine.bundle" "$wine_dir"
rm -rf "$tmp"

# sanity: engine binary runs
if "${wine_dir}/bin/wine" --version >/dev/null 2>&1; then
  ok "Engine now: $(cat "${wine_dir}/version")  ($("${wine_dir}/bin/wine" --version))"
  ok "Previous engine backed up: ${wine_dir}.backup-${ts}"
else
  die "New engine failed to run; restore with: rm -rf '${wine_dir}' && mv '${wine_dir}.backup-${ts}' '${wine_dir}'"
fi
