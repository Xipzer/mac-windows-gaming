# notproton/: free NotProton assets

Used by `scripts/setup-notproton.sh`. Background: [../docs/NOTPROTON.md](../docs/NOTPROTON.md).

| File | What |
|---|---|
| `notproton-free.patch` | Changes to `dylib/feats/compat_run.sh` of [Maxyme/NotProton](https://github.com/Maxyme/NotProton) `5b8d186` (runner.env, SIP-proof library path, env forwarding, msync off, Retina default, keep Valve's steamclient64) |
| `ntdll-sikarugir11.json` | NotProton's `build_module` steamclient detour, pre-built for Sikarugir `WS12WineSikarugir11.0_1` `ntdll.dll` (clean sha256 `654a3911…`, patched `5429ba1f…`) |
| `apply-ntdll.py` | Applies the JSON to an `ntdll.dll`; refuses any other build |
| `runner.env` | Environment Sikarugir's launcher sets for Wine 11 + D3DMetal, sourced by the run script |
| `direct-shipping.sh` | Launch-option wrapper for Dragon Ball Sparking! ZERO (skips the UE launcher stub) |

**Rebuilding the detour for a different engine** needs the upstream NotProton repo and
`brew install mingw-w64 capstone`:

```bash
cd NotProton/ntdll-patch
NP_FORCE_LOAD_PATH=0x58 sh build.sh /path/to/clean/ntdll.dll myengine   # -> detour2-myengine.bin
NP_FORCE_LOAD_PATH=0x58 python3 apply.py clean.dll patched.dll detour2-myengine.bin
```

`resolve.py` must accept `NP_FORCE_LOAD_PATH` (the `load_path` stack slot) because Sikarugir's
build keeps it at `rsp+0x58` where upstream's heuristic expects another slot. Find it by
disassembling `build_module` up to the hook.

## License

The files in this directory are derived from NotProton (GPL-3.0) and are distributed under
the **GNU General Public License v3.0**. Source: https://github.com/NotProtonNot/NotProton and
https://github.com/Maxyme/NotProton. The rest of this repository is MIT.
