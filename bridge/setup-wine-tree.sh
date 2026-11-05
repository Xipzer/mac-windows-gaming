#!/bin/sh
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"

WINE_URL="${WINE_URL:-https://gitlab.winehq.org/wine/wine.git}"
WINE_TAG="${WINE_TAG:-wine-11.15}"
WINE_COMMIT="${WINE_COMMIT:-2df1ee28039cf84776eb1421ed90bd154cebb65f}"
WINE_SRC="${WINE_SRC:-$repo/scratch/wine}"
WINE_BUILD="${WINE_BUILD:-$repo/scratch/wine-build-dual}"
CONFIGURE_OPTS="${CONFIGURE_OPTS:---enable-archs=i386,x86_64 --without-freetype --without-x}"
HOST="${HOST:-x86_64-apple-darwin}"
HOST_CPU="${HOST%%-*}"
HOST_CC="${HOST_CC:-clang -arch x86_64}"
HOST_CXX="${HOST_CXX:-clang++ -arch x86_64}"

PATH="/opt/homebrew/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/autoconf/bin:$PATH"
export PATH

missing=""
for tool in git make bison flex i686-w64-mingw32-gcc x86_64-w64-mingw32-gcc; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
    echo "==> missing tools:$missing" >&2
    echo "    brew install mingw-w64 bison flex" >&2
    exit 1
fi

if [ ! -d "$WINE_SRC/.git" ]; then
    echo "==> cloning $WINE_TAG into $WINE_SRC"
    git clone --depth 1 --branch "$WINE_TAG" "$WINE_URL" "$WINE_SRC"
else
    echo "==> source tree present, leaving it alone: $WINE_SRC"
fi

head="$(git -C "$WINE_SRC" rev-parse HEAD)"
if [ "$head" != "$WINE_COMMIT" ]; then
    echo "==> $WINE_SRC is at $head, not the pinned $WINE_COMMIT" >&2
    echo "    Either $WINE_TAG has moved upstream or this tree came from elsewhere." >&2
    echo "    Set WINE_COMMIT to adopt it, once the loader is known to boot its ntdll." >&2
    exit 1
fi
echo "==> source tree at pinned $WINE_COMMIT"

if grep -q 'WINE_CONFIG_MAKEFILE(dlls/lsteamclient)' "$WINE_SRC/configure.ac"; then
    echo "==> components already registered with configure"
else
    echo "==> registering dlls/lsteamclient and programs/steam.exe with configure"
    ( cd "$WINE_SRC" && git apply "$here/register-components.diff" )
fi

"$repo/lsteamclient/fetch.sh"
"$repo/steam-shim/fetch-headers.sh"

mkdir -p "$WINE_SRC/dlls/lsteamclient" "$WINE_SRC/programs/steam.exe"
rsync -a "$repo/build/lsteamclient/" "$WINE_SRC/dlls/lsteamclient/"
rsync -a --exclude build.sh --exclude gen-implib.sh --exclude fetch-headers.sh \
    "$repo/steam-shim/" "$WINE_SRC/programs/steam.exe/"
echo "==> placed sources for dlls/lsteamclient and programs/steam.exe"

if [ -f "$WINE_BUILD/Makefile" ]; then
    echo "==> build tree already configured, leaving it alone: $WINE_BUILD"
else
    echo "==> configuring $WINE_BUILD"
    mkdir -p "$WINE_BUILD"
    ( cd "$WINE_BUILD" && "$WINE_SRC/configure" $CONFIGURE_OPTS \
        --host="$HOST" CC="$HOST_CC" CXX="$HOST_CXX" )
fi

if ! grep -q "^host_cpu = $HOST_CPU" "$WINE_BUILD/config.status"; then
    echo "==> configure did not take the $HOST_CPU host, unix halves would be the wrong arch" >&2
    exit 1
fi

if [ -f "$WINE_BUILD/dlls/ntdll/ntdll.so" ]; then
    echo "==> dlls/ntdll/ntdll.so already built"
else
    echo "==> building dlls/ntdll/ntdll.so"
    ( cd "$WINE_BUILD" && make dlls/ntdll/ntdll.so )
fi

echo "==> ready, now run: ../lsteamclient/build.sh --install"
echo "                    ../steam-shim/build.sh --install"
