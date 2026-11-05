#!/bin/sh
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

ntdll="${1:?usage: build.sh <target ntdll.dll> [variant]}"
variant="${2:-rosetta}"
[ "$variant" = rosetta ] && out=detour2.bin || out="detour2-$variant.bin"

eval "$(python3 resolve.py --sh "$ntdll")"
[ "$SB_MACHINE" = 0x8664 ] || { echo "$ntdll is machine $SB_MACHINE, not x86_64" >&2; exit 1; }

CC=x86_64-w64-mingw32-gcc
LD=x86_64-w64-mingw32-ld
OBJCOPY=x86_64-w64-mingw32-objcopy

CFLAGS="-Os -fno-asynchronous-unwind-tables -ffreestanding -fno-stack-protector"

"$CC" -c $CFLAGS detour.c -o detour_c.o
"$CC" -c -x assembler-with-cpp shim.S -o shim.o \
  "-DWM_REG=$SB_WM" "-DSCRATCH_REG=$SB_SCRATCH" "-DLOAD_PATH_SLOT=$SB_LOAD_PATH" \
  "-DSTOLEN_BYTES=$SB_STOLEN_BYTES"
"$LD" -T link.ld shim.o detour_c.o -o detour_linked.elf \
  --defsym "CAVE_VA=$SB_PAYLOAD_VA" \
  --defsym "BM_RESUME=$SB_RESUME_VA" \
  --defsym "LDR_GETDLLHANDLE=$SB_LDR_GET_DLL_HANDLE" \
  --defsym "LDR_LOADDLL=$SB_LDR_LOAD_DLL" \
  --defsym "NT_PROTECT=$SB_NT_PROTECT_VIRTUAL_MEMORY"
"$OBJCOPY" -O binary -j .cave detour_linked.elf "$out"

got="$(shasum -a 256 "$out" | cut -d' ' -f1)"
if [ -n "${SB_PAYLOAD_SHA256:-}" ]; then
  if [ "$got" != "$SB_PAYLOAD_SHA256" ]; then
    echo "error: $out is $got, pinned $SB_PAYLOAD_SHA256" >&2
    echo "       the detour sources no longer compile to the payload this build was verified with" >&2
    exit 1
  fi
else
  echo "note: $SB_SHA256 carries no payload pin, $out is $got"
fi

echo "built $out ($(wc -c < "$out") bytes) for $SB_ARCH $SB_SHA256"
echo "  cave $SB_CAVE_RVA fill $SB_FILL, payload at $SB_PAYLOAD_RVA, room $SB_CAVE_ROOM"
echo "  hook $SB_HOOK_RVA stolen $SB_STOLEN, wm $SB_WM, load_path rsp+$SB_LOAD_PATH"

app_copy="../app/Sources/SteamBridgeApp/Resources/$out"
if [ -f "$app_copy" ] && ! cmp -s "$out" "$app_copy"; then
  echo "warning: $app_copy is stale" >&2
  echo "         cp $out $app_copy" >&2
  echo "         then update payloadSHA256 for $variant x86_64Windows in NtdllPatcher.swift to" >&2
  echo "         $(shasum -a 256 "$out" | cut -d' ' -f1)" >&2
fi
