#!/bin/sh
# usage: notproton/ntdll-i386/build.sh [clean i386 ntdll.dll]
# Needs git, python3 and the i686-w64-mingw32 toolchain (brew install mingw-w64).
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cache="$HOME/Library/Caches/notproton-free/ntdll-i386"
np_rev=5b8d18683b619b66390be8cbcffc1fbf47e45971
clean_sha=ae3ce87f0744ea9180fc91371a2ca5a6ddb5e045e7469480b447c8cd0365c20c
patched_sha=e53e7276e54d8f6fa069a95115a48d52f4697ecf9235461313c7109e9f263f91
runner_ntdll="$HOME/Library/Application Support/notproton/runners/current/lib/wine/i386-windows/ntdll.dll"
clean="${1:-}"
if [ -z "$clean" ]; then
  clean="$runner_ntdll"
  [ -f "$clean.notproton-orig" ] && clean="$clean.notproton-orig"
fi

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
[ "$(sha "$clean")" = "$clean_sha" ] || { echo "error: $clean is not Sikarugir 11.0_1's clean i386 ntdll" >&2; exit 1; }

mkdir -p "$cache"
src="$cache/NotProton.git"
[ -d "$src" ] || git clone -q --bare --filter=blob:none https://github.com/Maxyme/NotProton.git "$src"
venv="$cache/venv"
[ -x "$venv/bin/python3" ] || python3 -m venv "$venv"
"$venv/bin/python3" -c 'import capstone, sys; sys.exit(capstone.__version__ != "5.0.7")' 2>/dev/null ||
  "$venv/bin/pip" install -q capstone==5.0.7
export PATH="$venv/bin:$PATH"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$src" archive "$np_rev" ntdll-patch | tar -x -C "$work"
patch -s -p1 -d "$work/ntdll-patch" < "$here/notproton-i386.patch"

eval "$(python3 "$work/ntdll-patch/resolve.py" --sh "$clean")"
want() { [ "$2" = "$3" ] || { echo "error: resolver $1 is '$2', disassembly says '$3'" >&2; exit 1; }; }
want hook "$NP_HOOK_RVA" 0x2eb00
want stolen "$NP_STOLEN" 8b4514a801
want wm "$NP_WM" edi
want flags_slot "$NP_FLAGS_SLOT" 0x14
want load_path "$NP_LOAD_PATH" -0x40
want gate_bit "${NP_GATE_BIT:-}" 0x1
want stole_branch "${NP_STOLE_BRANCH:-}" ""

out="$work/ntdll.dll"
APPLY="$out" sh "$work/ntdll-patch/build32.sh" "$clean"
[ "$(sha "$out")" = "$patched_sha" ] || { echo "error: rebuilt ntdll is $(sha "$out"), pinned $patched_sha" >&2; exit 1; }

python3 "$here/mkpatch.py" "$clean" "$out" WS12WineSikarugir11.0_1 lib/wine/i386-windows/ntdll.dll \
  "NotProton build_module steamclient->lsteamclient detour for 32-bit games (ntdll-patch/detour32.c, GPL-3.0), rebuilt by notproton/ntdll-i386/build.sh. Wine 11 gates on DONT_RESOLVE_DLL_REFERENCES (0x1) at [ebp+0x14]; the payload overflows .text padding, so it sits in the .rsrc tail, which is marked executable." \
  > "$here/../ntdll-sikarugir11-i386.json"
echo "rebuilt $patched_sha, wrote notproton/ntdll-sikarugir11-i386.json"
