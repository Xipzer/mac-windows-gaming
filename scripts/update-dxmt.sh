#!/usr/bin/env bash
# update-dxmt.sh — update the DXMT (DirectX 10/11 -> Metal) layer in a wrapper.
#
# DXMT is the best FREE open DX10/11->Metal translator. Sikarugir bundles a version;
# this pulls the latest "builtin" release from github.com/3Shain/dxmt and overlays it.
# Only matters for DX10/11 games where you select DXMT instead of D3DMetal.
#
# Usage:  ./update-dxmt.sh [WrapperName]

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"

WRAPPER_NAME="${1:-Steam}"
w="$(find_wrapper "$WRAPPER_NAME")" || true
[[ -n "${w:-}" ]] || die "Wrapper '${WRAPPER_NAME}' not found"

dxmt_dir="$(wrapper_dxmt_dir "$w")"
[[ -d "$dxmt_dir" ]] || die "Wrapper has no dxmt renderer dir: $dxmt_dir"

cur=""; [[ -f "${dxmt_dir}/version" ]] && cur="$(cat "${dxmt_dir}/version")"
tag="$(gh_latest_tag "$DXMT_REPO")"; [[ -n "$tag" ]] || die "Could not resolve latest DXMT tag"
info "DXMT: installed=${cur:-none}  latest=${tag}"

if [[ "$cur" == "$tag" ]]; then ok "Already up to date (${tag})"; exit 0; fi

url="$(gh_asset_url "$DXMT_REPO" "builtin")"; [[ -n "$url" ]] || die "No 'builtin' asset in ${tag}"
info "Downloading ${tag} builtin…"
tmp="$(mktemp -d /tmp/dxmt.XXXXXX)"
curl -fsSL -o "${tmp}/dxmt.tgz" "$url"
tar -xzf "${tmp}/dxmt.tgz" -C "$tmp"

# release layout: <tag>/{x86_64-unix,i386-windows,x86_64-windows}/...
src="$(/usr/bin/find "$tmp" -maxdepth 2 -type d -name "x86_64-windows" | head -1)"; src="$(dirname "$src")"
[[ -d "$src" ]] || die "Unexpected DXMT archive layout"

kill_wine
cp -R "${dxmt_dir}/wine" "${dxmt_dir}/wine.backup-${cur:-old}" 2>/dev/null || true
ditto "${src}/" "${dxmt_dir}/wine/"
printf '%s' "$tag" > "${dxmt_dir}/version"
rm -rf "$tmp"
ok "DXMT updated: ${cur:-none} -> $(cat "${dxmt_dir}/version")"
