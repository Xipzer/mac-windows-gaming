#!/bin/sh
D="$(cd "$(dirname "$0")" && pwd)"
for _ in 1 2 3; do python3 "$D"/keyhold.py w 3; python3 "$D"/keyhold.py a 2; python3 "$D"/keyhold.py s 3; python3 "$D"/keyhold.py d 2; done
