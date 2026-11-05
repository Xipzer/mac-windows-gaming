#!/bin/sh
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

ntdll="${1:?usage: build32.sh <target ntdll.dll> [variant]}"
variant="${2:-rosetta}"
[ "$variant" = rosetta ] && out=detour32.bin || out="detour32-$variant.bin"

eval "$(python3 resolve.py --sh "$ntdll")"
[ "$SB_MACHINE" = 0x14c ] || { echo "$ntdll is machine $SB_MACHINE, not i386" >&2; exit 1; }

CC=i686-w64-mingw32-gcc
LD=i686-w64-mingw32-ld
OBJCOPY=i686-w64-mingw32-objcopy

CFLAGS="-Os -fno-asynchronous-unwind-tables -ffreestanding -fno-stack-protector \
-fno-ident -mno-stack-arg-probe"

"$CC" -c $CFLAGS detour32.c -o detour32_c.o \
  "-DFLAGS_SLOT=$SB_FLAGS_SLOT" "-DLOAD_PATH_SLOT=$SB_LOAD_PATH"
"$CC" -c -x assembler-with-cpp shim32.S -o shim32.o \
  "-DWM_REG=$SB_WM" "-DSTOLEN_HEAD_BYTES=$SB_STOLEN_HEAD_BYTES" \
  "-DSTOLE_BRANCH=${SB_STOLE_BRANCH:-0}"
"$LD" -T link32.ld shim32.o detour32_c.o -o detour32_linked.elf \
  --defsym "CAVE_VA=$SB_PAYLOAD_VA" \
  --defsym "BM_RESUME=$SB_RESUME_VA" \
  --defsym "BM_SKIP=$SB_SKIP_VA" \
  --defsym "LDR_GETDLLHANDLE=$SB_LDR_GET_DLL_HANDLE" \
  --defsym "LDR_LOADDLL=$SB_LDR_LOAD_DLL" \
  --defsym "NT_PROTECT=$SB_NT_PROTECT_VIRTUAL_MEMORY" \
  --defsym "NT_OPENFILE=$SB_NT_OPEN_FILE" \
  --defsym "NT_READFILE=$SB_NT_READ_FILE" \
  --defsym "NT_CLOSE=$SB_NT_CLOSE"
"$OBJCOPY" -O binary -j .cave detour32_linked.elf "$out"

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
echo "  hook $SB_HOOK_RVA stolen $SB_STOLEN, wm $SB_WM, load_path ebp$SB_LOAD_PATH"

app_copy=../app/Sources/SteamBridgeApp/Resources/$out
if [ -f "$app_copy" ] && ! cmp -s "$out" "$app_copy"; then
  echo "warning: $app_copy is stale" >&2
  echo "         cp $out $app_copy" >&2
  echo "         then update payloadSHA256 for i386Windows in NtdllPatcher.swift to" >&2
  echo "         $(shasum -a 256 "$out" | cut -d' ' -f1)" >&2
fi

if [ "${APPLY:-}" != "" ]; then
  python3 apply.py "$ntdll" "$APPLY" "$out"
fi
