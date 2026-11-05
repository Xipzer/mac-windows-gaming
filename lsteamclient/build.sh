#!/bin/bash

set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)

WINE_BUILD=${WINE_BUILD:-$repo/scratch/wine-build-dual}
UNIX_ARCH=${UNIX_ARCH:-x86_64}
case "$UNIX_ARCH" in
	x86_64) unix_dir=x86_64-unix ;;
	arm64) unix_dir=aarch64-unix ;;
	*) echo "==> UNIX_ARCH is $UNIX_ARCH, expected x86_64 or arm64" >&2; exit 1 ;;
esac
WINE_SRC_REL=${WINE_SRC_REL:-../wine}
TREE=${TREE:-$repo/build/lsteamclient}
CX_ROOT=${CX_ROOT:-$HOME/Library/Application Support/SteamBridge/runners/current}
BRIDGE_DIR=${BRIDGE_DIR:-$HOME/Library/Application Support/SteamBridge/bridge}

install=0
do_pe=1
do_unix=1
for arg in "$@"; do
	case "$arg" in
		--install) install=1 ;;
		--pe) do_unix=0 ;;
		--unix) do_pe=0 ;;
		*) echo "==> unknown argument $arg"; exit 1 ;;
	esac
done

"$here/fetch.sh"

dll=dlls/lsteamclient
out=$dll/lsteamclient.so

if [ ! -d "$WINE_BUILD/$dll" ]; then
	echo "==> no wine build tree at $WINE_BUILD/$dll"
	echo "    the tree is a configured CrossOver 11.0 source drop, see ALIGNMENT.md"
	exit 1
fi

cd "$WINE_BUILD"

src=$WINE_SRC_REL/$dll
[ -d "$src" ] || { echo "==> no wine source tree at $WINE_BUILD/$src"; exit 1; }

echo "==> syncing the assembled tree into $WINE_SRC_REL/$dll"
rsync -a --delete "$TREE/" "$src/"

pe_info=$here/../bridge/pe-info.py

pe_i386=$dll/i386-windows/lsteamclient.dll
pe_x86_64=$dll/x86_64-windows/lsteamclient.dll

if [ "$do_pe" -eq 1 ]; then
	for cc in i686-w64-mingw32-gcc x86_64-w64-mingw32-gcc; do
		command -v "$cc" >/dev/null || { echo "==> missing $cc, install mingw-w64"; exit 1; }
	done

	for target in "$pe_i386" "$pe_x86_64"; do
		echo "==> building $target"
		make "$target" >/dev/null
	done

	for target in "$pe_i386" "$pe_x86_64"; do
		want=${target#"$dll/"}
		want=${want%%-windows/*}
		size=$(stat -f %z "$target")
		set -- $("$pe_info" "$target")
		[ "$1" = "$want" ] || { echo "==> $target is $1, expected $want"; exit 1; }
		[ "$size" -gt 1000000 ] || { echo "==> $target is only $size bytes, the link dropped objects"; exit 1; }
		echo "==> built $target  $1  $size bytes  $2 (timestamp and checksum zeroed)"
	done
fi

if [ "$do_unix" -eq 1 ]; then
	[ -f dlls/ntdll/ntdll.so ] || { echo "==> missing dlls/ntdll/ntdll.so, build ntdll first"; exit 1; }
	if [ "$(lipo -archs dlls/ntdll/ntdll.so)" != "$UNIX_ARCH" ]; then
		echo "==> dlls/ntdll/ntdll.so is not $UNIX_ARCH, the tree was built for the wrong arch"
		exit 1
	fi

	objs=$(sed -n 's/^[[:space:]]*\([A-Za-z0-9_]*\.cpp\)[[:space:]]*\\*[[:space:]]*$/\1/p' "$TREE/Makefile.in")
	count=$(echo "$objs" | wc -l | tr -d ' ')
	echo "==> unix half: $count sources from Makefile.in SOURCES"

	CXXFLAGS="-arch $UNIX_ARCH -I$dll -I$src -Iinclude -I$WINE_SRC_REL/include \
-D__WINESRC__ -DSTEAM_API_EXPORTS -Dprivate=public -Dprotected=public -DWINE_UNIX_LIB \
-fPIC -fasynchronous-unwind-tables -g -O2"

	built=0
	for cpp in $objs; do
		o=$dll/${cpp%.cpp}.o
		if [ ! -f "$o" ] || [ "$src/$cpp" -nt "$o" ]; then
			echo "    CXX $cpp"
			g++ $CXXFLAGS -c -o "$o" "$src/$cpp"
			built=$((built + 1))
		fi
	done
	echo "==> compiled $built object(s), $((count - built)) already current"

	link_objs=""
	for cpp in $objs; do
		o=$dll/${cpp%.cpp}.o
		[ -f "$o" ] || { echo "==> missing object $o"; exit 1; }
		link_objs="$link_objs $o"
	done

	echo "==> linking $out"
	gcc -std=gnu23 -arch "$UNIX_ARCH" -o "$out" -dynamiclib \
		-install_name @rpath/lsteamclient.so -Wl,-rpath,@loader_path/ \
		$link_objs dlls/ntdll/ntdll.so -lc++ -Wl,-undefined,dynamic_lookup

	size=$(stat -f %z "$out")
	arch=$(lipo -archs "$out")
	[ "$arch" = "$UNIX_ARCH" ] || { echo "==> built $arch, expected $UNIX_ARCH"; exit 1; }
	[ "$size" -gt 1000000 ] || { echo "==> only $size bytes, the link dropped objects"; exit 1; }
	signing=$(codesign -dv "$out" 2>&1 || true)
	if [ "$UNIX_ARCH" = x86_64 ]; then
		if ! echo "$signing" | grep -q "not signed at all"; then
			echo "==> output is signed, wine will refuse to load it"
			exit 1
		fi
		state=unsigned
	else
		if ! echo "$signing" | grep -q "linker-signed"; then
			echo "==> output is not linker-signed, the platform will refuse to map it"
			exit 1
		fi
		state=linker-signed
	fi
	echo "==> built $out  $arch  $size bytes  $(shasum -a 256 "$out" | cut -c1-16)  $state"
fi

[ "$install" -eq 1 ] || { echo "==> not installing, pass --install to deploy"; exit 0; }

[ -d "$CX_ROOT/lib/wine" ] || { echo "==> no CrossOver tree at $CX_ROOT"; exit 1; }

case "$CX_ROOT" in
	/Applications/*)
		echo "==> refusing to install into $CX_ROOT" >&2
		echo "    that is an installed CrossOver and it has to stay stock." >&2
		echo "    point CX_ROOT at the runner clone under the support directory." >&2
		exit 1
		;;
esac

install_one() {
	from=$1
	shift
	for dst in "$@"; do
		mkdir -p "$(dirname "$dst")"
		cp -f "$from" "$dst"
		case "$dst" in
			*.so)
				if [ "$UNIX_ARCH" = x86_64 ]; then
					codesign --remove-signature "$dst" 2>/dev/null || true
				fi
				;;
		esac
		cmp -s "$from" "$dst" || { echo "==> install verify failed: $dst differs from $from"; exit 1; }
		echo "==> installed $dst"
	done
}

if [ "$do_pe" -eq 1 ]; then
	install_one "$pe_i386" \
		"$BRIDGE_DIR/i386-windows/lsteamclient.dll" \
		"$CX_ROOT/lib/wine/i386-windows/lsteamclient.dll"
	install_one "$pe_x86_64" \
		"$BRIDGE_DIR/x86_64-windows/lsteamclient.dll" \
		"$BRIDGE_DIR/lsteamclient.dll" \
		"$CX_ROOT/lib/wine/x86_64-windows/lsteamclient.dll"
fi

if [ "$do_unix" -eq 1 ]; then
	install_one "$out" \
		"$BRIDGE_DIR/$unix_dir/lsteamclient.so" \
		"$CX_ROOT/lib/wine/$unix_dir/lsteamclient.so"
fi

echo "==> done. prefixes refresh their copy from the bridge on next launch."
