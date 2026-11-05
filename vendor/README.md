# Vendored dependencies

## cJSON

Tracked here as `cJSON.c` and `cJSON.h`. Used only by the signature database loader.

## Dobby

Not tracked (`vendor/dobby/` is ignored). Fetch it before `make dobby`:

    git clone "$DOBBY_URL" vendor/dobby
    git -C vendor/dobby checkout "$DOBBY_COMMIT"

`DOBBY_URL` and `DOBBY_COMMIT` are pinned in `scripts/setup.sh`. The pin matters: the
inline hook trampolines are architecture specific and a newer revision changes code
generation, so only move it after checking that hooks still install on a supported
Steam build.

`make dobby` builds the libraries into `build/dobby/`, where the top-level `Makefile`
links them from.

## audiobuf

`audiobuf/audiobuf.c` is Highball's audio interposer, copied unchanged from
[gauthierpiarrette/highball](https://github.com/gauthierpiarrette/highball) `spike/audiobuf/audiobuf.c`
at commit `c690f23` (repo HEAD `dbc36eb`). Highball's engine manifest
(`spike/engines/x64-crossover26.3-r31.json`) lists it as "MIT (Highball's own)"; the Highball repository
LICENSE file is GPL-3.0. It is built as a separate library and never linked into SteamBridge code.

`scripts/setup.sh` builds it (x86_64 and arm64) to `$SB/audiobuf.dylib`. The run script inserts it into
the game with `DYLD_INSERT_LIBRARIES` only when `STEAMBRIDGE_AUDIOBUF=1`. Its own switches
(`HB_AUDIOLIMIT=0`, `HB_AUDIORT=0`, `HB_AUDIOFOLLOW=0`, `HB_AUDIOBUF_DEBUG=1`) are passed through.
