#!/bin/sh
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
cache="$HOME/Library/Caches/steambridge/ntdll-i386"
clean_sha=ae3ce87f0744ea9180fc91371a2ca5a6ddb5e045e7469480b447c8cd0365c20c
patched_sha=e53e7276e54d8f6fa069a95115a48d52f4697ecf9235461313c7109e9f263f91
runner_ntdll="$HOME/Library/Application Support/SteamBridge/runners/current/lib/wine/i386-windows/ntdll.dll"
clean="${1:-}"
if [ -z "$clean" ]; then
  clean="$runner_ntdll"
  [ -f "$clean.steambridge-orig" ] && clean="$clean.steambridge-orig"
fi

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
[ "$(sha "$clean")" = "$clean_sha" ] || { echo "error: $clean is not Sikarugir 11.0_1's clean i386 ntdll" >&2; exit 1; }
command -v i686-w64-mingw32-gcc >/dev/null || { echo "error: needs mingw-w64 (brew install mingw-w64)" >&2; exit 1; }

mkdir -p "$cache"
venv="$cache/venv"
[ -x "$venv/bin/python3" ] || python3 -m venv "$venv"
"$venv/bin/python3" -c 'import capstone, sys; sys.exit(capstone.__version__ != "5.0.7")' 2>/dev/null ||
  "$venv/bin/pip" install -q capstone==5.0.7
export PATH="$venv/bin:$PATH"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -R "$here" "$work/ntdll-patch"

eval "$(python3 "$work/ntdll-patch/resolve.py" --sh "$clean")"
want() { [ "$2" = "$3" ] || { echo "error: resolver $1 is '$2', disassembly says '$3'" >&2; exit 1; }; }
want hook "$SB_HOOK_RVA" 0x2eb00
want stolen "$SB_STOLEN" 8b4514a801
want wm "$SB_WM" edi
want flags_slot "$SB_FLAGS_SLOT" 0x14
want load_path "$SB_LOAD_PATH" -0x40
want gate_bit "${SB_GATE_BIT:-}" 0x1
want stole_branch "${SB_STOLE_BRANCH:-}" ""

out="$work/ntdll.dll"
APPLY="$out" sh "$work/ntdll-patch/build32.sh" "$clean"
[ "$(sha "$out")" = "$patched_sha" ] || { echo "error: rebuilt ntdll is $(sha "$out"), pinned $patched_sha" >&2; exit 1; }

python3 "$here/mkpatch.py" "$clean" "$out" WS12WineSikarugir11.0_1 lib/wine/i386-windows/ntdll.dll \
  "build_module steamclient->lsteamclient detour for 32-bit games (ntdll-patch/detour32.c), rebuilt by ntdll-patch/build-sikarugir11-i386.sh. Wine 11 gates on DONT_RESOLVE_DLL_REFERENCES (0x1) at [ebp+0x14]; the payload overflows .text padding, so it sits in the .rsrc tail, which is marked executable." \
  > "$repo/assets/ntdll-sikarugir11-i386.json"
echo "rebuilt $patched_sha, wrote assets/ntdll-sikarugir11-i386.json"
