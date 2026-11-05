#!/bin/sh
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

CX_ROOT="${CX_ROOT:-/Applications/CrossOver Preview.app/Contents/SharedSupport/CrossOver}"
BRIDGE_DIR="${BRIDGE_DIR:-$HOME/Library/Application Support/SteamBridge/bridge}"
OUT="${OUT:-$here/build}"

ROSETTA_CLEAN_X86_64=04c7200b6645decb7c2d1ba6b0195abc9af83257072558d11aa72cc067ac3377
ROSETTA_CLEAN_I386=94cc7c14c1e9dcf58ef501015c115f8405c73b2a65cefe31faa5d9e47f36e58b
ROSETTA_PATCHED_X86_64=b21f4bace5a7a0cfef0f74cef9b27561f6eb3ad38daf76f36b186ca0677c2b2c
ROSETTA_PATCHED_I386=25bfde1f50ee96485763968ef10b9d9ad35e38214232f17ebdc009b098af44a0

FEX_CLEAN_I386=09474795d6f306163cebab6429819999fcff50e07dbc4b067a90ec4f74a3a7d7
FEX_CLEAN_AARCH64=7823d71fbce6c9947163bf8b96beb299eabb02878245bcaf6759f2a22e81f071
FEX_PATCHED_I386=e799ea02418294588ee353a90b967358be316a3044ff9515b28aa1ce07e63981
FEX_PATCHED_AARCH64=560939a0f6e58314fc9d79fe6f839dce2b181f829ae58dca195fa142fcf40f39

install=0
[ "${1:-}" = "--install" ] && install=1

die() { echo "error: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

command -v python3 >/dev/null || die "python3 not found"

OBJCOPY=/opt/homebrew/opt/llvm/bin/llvm-objcopy

flavor_of() {
    for cand in "$CX_ROOT/lib/wine/aarch64-windows/ntdll.dll.steambridge-orig" \
                "$CX_ROOT/lib/wine/aarch64-windows/ntdll.dll"; do
        [ -f "$cand" ] || continue
        if [ "$(sha "$cand")" = "$FEX_CLEAN_AARCH64" ]; then echo fex; return 0; fi
    done
    for cand in "$CX_ROOT/lib/wine/x86_64-windows/ntdll.dll.steambridge-orig" \
                "$CX_ROOT/lib/wine/x86_64-windows/ntdll.dll"; do
        [ -f "$cand" ] || continue
        if [ "$(sha "$cand")" = "$ROSETTA_CLEAN_X86_64" ]; then echo rosetta; return 0; fi
    done
    die "no ntdll under $CX_ROOT/lib/wine matches a pinned build
       pass FLAVOR=rosetta or FLAVOR=fex to choose the pins anyway"
}

if [ -z "${FLAVOR:-}" ]; then
    FLAVOR="$(flavor_of)"
fi

case "$FLAVOR" in
    rosetta) tools="x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc" ;;
    fex)     tools="i686-w64-mingw32-gcc clang ld.lld" ;;
    *)       die "unknown flavor $FLAVOR, expected rosetta or fex" ;;
esac

for t in $tools; do
    command -v "$t" >/dev/null || die "$t not found (brew install mingw-w64 llvm)"
done

if [ "$FLAVOR" = fex ] && [ ! -x "$OBJCOPY" ]; then
    die "$OBJCOPY not found (brew install llvm)"
fi

echo "==> $FLAVOR flavor, reading $CX_ROOT/lib/wine"

clean_for() {
    arch="$1"; want="$2"
    for cand in "$CX_ROOT/lib/wine/$arch/ntdll.dll.steambridge-orig" \
                "$CX_ROOT/lib/wine/$arch/ntdll.dll"; do
        [ -f "$cand" ] || continue
        [ "$(sha "$cand")" = "$want" ] || continue
        echo "$cand"
        return 0
    done
    die "no clean $arch ntdll.dll found under $CX_ROOT/lib/wine/$arch
       expected sha256 $want
       extract a clean ntdll.dll from the CrossOver installer and point CX_ROOT at it"
}

mkdir -p "$OUT"

patch_one() {
    arch="$1"; builder="$2"; variant="$3"; payload="$4"; want_in="$5"; want_out="$6"
    src="$(clean_for "$arch" "$want_in")"
    dst="$OUT/$arch/ntdll.dll"
    mkdir -p "$OUT/$arch"
    echo "==> building $arch payload from ${src##*/}"
    ./"$builder" "$src" "$variant" >/dev/null
    echo "==> patching $arch"
    python3 apply.py "$src" "$dst" "$payload" >/dev/null
    got="$(sha "$dst")"
    [ "$got" = "$want_out" ] || die "$arch output hash $got, expected $want_out
       the patch no longer reproduces the known-good binary, do not ship this"
    echo "==> built $arch ntdll.dll  $(stat -f %z "$dst") bytes  $(echo "$got" | cut -c1-16)"
}

case "$FLAVOR" in
    rosetta)
        ARCHES="x86_64-windows i386-windows"
        patch_one x86_64-windows build.sh   rosetta detour2.bin \
            "$ROSETTA_CLEAN_X86_64" "$ROSETTA_PATCHED_X86_64"
        patch_one i386-windows   build32.sh rosetta detour32.bin \
            "$ROSETTA_CLEAN_I386"   "$ROSETTA_PATCHED_I386"
        ;;
    fex)
        ARCHES="i386-windows aarch64-windows"
        patch_one i386-windows    build32.sh fex detour32-fex.bin \
            "$FEX_CLEAN_I386"    "$FEX_PATCHED_I386"
        patch_one aarch64-windows build64.sh fex detour64-fex.bin \
            "$FEX_CLEAN_AARCH64" "$FEX_PATCHED_AARCH64"
        ;;
esac

if [ "$install" -eq 0 ]; then
    echo "==> not installing, pass --install to stage into the bridge"
    exit 0
fi

for arch in $ARCHES; do
    d="$BRIDGE_DIR/wine/$arch"
    mkdir -p "$d"
    cp "$OUT/$arch/ntdll.dll" "$d/ntdll.dll"
    echo "==> installed $arch  $(sha "$d/ntdll.dll" | cut -c1-16)  $d/ntdll.dll"
done
echo "==> RUN_SCRIPT copies these into the CrossOver tree on the next Steam launch"
