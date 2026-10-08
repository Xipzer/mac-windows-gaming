#!/usr/bin/env bash
# update-wrapper.sh - (legacy route) update a Sikarugir wrapper's template (launcher,
# libraries, renderers) to the newest version. CLI form of Configure -> Tools -> Update Wrapper.
#
# Why: on template 1.0.11 a Wine 11 engine fails at launch with
#        ERROR: The operation couldn't be completed. (SikarugirSdk.FileUtilsError error 1.)
#      1.0.21 runs it and bundles newer renderers (D3DMetal 4.0b2, DXMT newer than v0.80).
#
# What it replaces:  Contents/{MacOS,Frameworks,Resources,Configure.app}
# What it keeps:     Contents/SharedSupport (Wine engine, prefix, your games), Info.plist
#                    (only the version keys are bumped)
# Backup:            ~/Applications/Sikarugir/.<Name>-wrapper-backup-<timestamp>/
#
# Usage:  ./update-wrapper.sh [WrapperName] [--version 1.0.21]

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib.sh"

WRAPPER_NAME="Steam"; WANT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) WANT="$2"; shift 2;;
    *) WRAPPER_NAME="$1"; shift;;
  esac
done

w="$(find_wrapper "$WRAPPER_NAME")" || true
[[ -n "${w:-}" ]] || die "Wrapper '${WRAPPER_NAME}' not found under ${SIKARUGIR_WRAPPERS_DIR}"

cur="$(wrapper_template_version "$w")"
[[ -n "$WANT" ]] || WANT="$(latest_template_version)"
[[ -n "$WANT" ]] || die "Could not determine the latest wrapper template"
info "Wrapper '${WRAPPER_NAME}': template ${cur:-unknown}, latest ${WANT}"

if [[ -n "$cur" ]] && ! version_gt "$WANT" "$cur"; then
  ok "Already up to date"
  exit 0
fi

tmp="$(mktemp -d /tmp/tpl.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
info "Downloading Template-${WANT}…"
curl -fsSL -o "${tmp}/t.tar.xz" "${SIKARUGIR_WRAPPER_URL}/Template-${WANT}.tar.xz" || die "Download failed"
tar -xJf "${tmp}/t.tar.xz" -C "$tmp"
T="$(/usr/bin/find "$tmp" -maxdepth 1 -name "Template-*.app" | head -1)/Contents"
[[ -d "$T/MacOS" && -d "$T/Frameworks" ]] || die "Unexpected template layout"

kill_wine
C="${w}/Contents"
backup="${SIKARUGIR_WRAPPERS_DIR}/.${WRAPPER_NAME}-wrapper-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup"
for d in MacOS Frameworks Resources Configure.app Info.plist; do
  [[ -e "$C/$d" ]] && cp -Rp "$C/$d" "$backup/"
done
ok "Backed up old template parts -> $backup"

for d in MacOS Frameworks Resources Configure.app; do
  [[ -e "$T/$d" ]] || continue
  rm -rf "${C:?}/$d"
  ditto "$T/$d" "$C/$d"
done
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleVersion ${WANT}" \
  -c "Set :CFBundleShortVersionString ${WANT}" \
  -c "Set :LSMinimumSystemVersion 14.6" "$C/Info.plist" >/dev/null

ext="$(wrapper_d3dmetal_external "$w")"
ok "Template now $(wrapper_template_version "$w")"
log "  D3DMetal bundled: $(d3dmetal_version "$ext")   DXMT: $(cat "$(wrapper_dxmt_dir "$w")/version" 2>/dev/null)"
log "  Engine untouched: $(cat "$(wrapper_wine_dir "$w")/version" 2>/dev/null)"
log "  Roll back: copy the folders in $backup back into ${C}"
