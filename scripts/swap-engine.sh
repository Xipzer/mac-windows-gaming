#!/usr/bin/env bash
# swap-engine.sh - (legacy route) change a Sikarugir wrapper's Wine engine.
#
# Engines (docs/ENGINES.md):
#   WS12WineSikarugir11.0_1  Wine 11  ★ best all-rounder. DEFAULT. Needs wrapper template >= 1.0.16.
#   WS12WineSikarugir10.0_8  Wine 10  previous known-good line; fallback.
#   WS12WineCX24.0.7_7       Wine 9   CrossOver's patched Wine. Mature fallback.
#   WS12WineGPTK1.1_3        Wine 7   Old. D3DMetal specialist; BAD for modern Steam UI.
#
# Downloads engines from github.com/Sikarugir-App/Engines if not cached.
# The renderer (D3DMetal/DXMT/DXVK) is INDEPENDENT of the engine (Configure checkbox).
#
# Usage:  ./swap-engine.sh <EngineName> [WrapperName]
#   e.g.  ./swap-engine.sh WS12WineSikarugir11.0_1 Steam

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"

ENGINE="${1:-$BEST_ENGINE}"
WRAPPER_NAME="${2:-Steam}"

w="$(find_wrapper "$WRAPPER_NAME")" || true
[[ -n "${w:-}" ]] || die "Wrapper '${WRAPPER_NAME}' not found under ${SIKARUGIR_WRAPPERS_DIR}"

engine_tar="$(ensure_engine_cached "$ENGINE")" || die "Could not download engine ${ENGINE} (check the name against ${SIKARUGIR_ENGINE_LIST})"

# Wine 11 engines need a newer wrapper template (old ones fail with FileUtilsError error 1).
if [[ "$ENGINE" == *Sikarugir11* ]]; then
  tv="$(wrapper_template_version "$w")"
  if [[ -n "$tv" ]] && version_gt "1.0.16" "$tv"; then
    warn "Wrapper template ${tv} is too old for Wine 11 - updating it first"
    bash "${HERE}/update-wrapper.sh" "$WRAPPER_NAME"
  fi
fi

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
