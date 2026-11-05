#!/bin/sh
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

ntdll="${1:?usage: build64.sh <target ntdll.dll> [variant]}"
variant="${2:-fex}"
out="detour64-$variant.bin"

eval "$(python3 resolve.py --sh "$ntdll")"
[ "$SB_MACHINE" = 0xaa64 ] || { echo "$ntdll is machine $SB_MACHINE, not aarch64" >&2; exit 1; }

[ "${SB_SITES:-0}" = 2 ] || { echo "$ntdll has ${SB_SITES:-0} hooks, shim64.S serves two" >&2; exit 1; }

for slot in "$SB_LOAD_PATH_1" "$SB_LOAD_PATH_2"; do
  if [ "$((slot))" -lt -256 ] || [ "$((slot))" -gt 255 ]; then
    echo "load_path slot $slot is out of ldur range, shim64.S needs a wider load" >&2
    exit 1
  fi
done

CC=clang
TARGET=aarch64-unknown-none-elf
LD=/opt/homebrew/bin/ld.lld
OBJCOPY=/opt/homebrew/opt/llvm/bin/llvm-objcopy

"$CC" -target "$TARGET" -c -Os -ffreestanding -fno-stack-protector \
  -fno-asynchronous-unwind-tables -mgeneral-regs-only -ffixed-x18 detour.c -o detour64_c.o
"$CC" -target "$TARGET" -c -x assembler-with-cpp shim64.S -o shim64.o \
  "-DLOAD_PATH_1=$SB_LOAD_PATH_1" "-DLOAD_PATH_2=$SB_LOAD_PATH_2"

"$LD" -T link64.ld -e shim_entry64 shim64.o detour64_c.o -o detour64_linked.elf \
  "--defsym=CAVE_VA=$SB_PAYLOAD_VA" \
  "--defsym=BM_RESUME_1=$SB_RESUME_VA_1" \
  "--defsym=LDR_GETDLLHANDLE=$SB_LDR_GET_DLL_HANDLE" \
  "--defsym=LDR_LOADDLL=$SB_LDR_LOAD_DLL" \
  "--defsym=NT_PROTECT=$SB_NT_PROTECT_VIRTUAL_MEMORY"
"$OBJCOPY" -O binary -j .cave detour64_linked.elf "$out"

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

size=$(wc -c < "$out")
echo "built $out ($size bytes) for $SB_ARCH $SB_SHA256"
echo "  cave $SB_CAVE_RVA fill $SB_FILL, payload at $SB_PAYLOAD_RVA, room $SB_CAVE_ROOM"
echo "  hook 1 $SB_HOOK_RVA_1 resume $SB_RESUME_VA_1, load_path x29$SB_LOAD_PATH_1"
echo "  hook 2 $SB_HOOK_RVA_2 resume $SB_RESUME_VA_2, load_path x29$SB_LOAD_PATH_2"

[ "$size" -le "$SB_CAVE_ROOM" ] || { echo "payload does not fit the cave" >&2; exit 1; }

if [ -n "${APPLY:-}" ]; then
  python3 apply.py "$ntdll" "$APPLY" "$out"
fi

app_copy="../app/Sources/SteamBridgeApp/Resources/$out"
if [ -f "$app_copy" ] && ! cmp -s "$out" "$app_copy"; then
  echo "warning: $app_copy is stale" >&2
  echo "         cp $out $app_copy" >&2
  echo "         then update payloadSHA256 for $variant aarch64Windows in NtdllPatcher.swift to" >&2
  echo "         $(shasum -a 256 "$out" | cut -d' ' -f1)" >&2
fi
