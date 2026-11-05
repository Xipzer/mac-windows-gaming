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
