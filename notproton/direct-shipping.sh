#!/bin/sh
out=""
for a in "$@"; do
  case "$a" in
    *"/SparkingZERO.exe") a="${a%/SparkingZERO.exe}/SparkingZERO/Binaries/Win64/SparkingZERO-Win64-Shipping.exe" ;;
  esac
  set -- "$@" "$a"; shift
done
exec "$@"
