#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
L=$1; S=$3
printf 'sleep %s\n' "$S" > /tmp/steambridge-idle.sh
"$D"/route.sh "$L" "$2" /tmp/steambridge-idle.sh
