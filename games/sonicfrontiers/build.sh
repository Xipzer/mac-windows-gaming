#!/bin/sh
set -e
cd "$(dirname "$0")"
mkdir -p out
taskpolicy -c background x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -shared -s \
  -static-libgcc -o out/dinput8.dll src/sonicfps.c src/dinput8.def \
  -Wl,--kill-at -Wl,--dynamicbase -Wl,--nxcompat
