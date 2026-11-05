# sonicfps: Sonic Frontiers FPS unlock without Hedge Mod Manager

`dinput8.dll` is a proxy DLL. It passes every dinput8 call to Wine's real
`C:\windows\system32\dinput8.dll` and, when the game loads it, patches the game code in memory.
The exe on disk is never changed. `scripts/apply-game-configs.sh` installs it with the Sonic profile. This is a port of HMMCodes "Disable FPS Limit (experimental)" by NM & RagdollClash:
https://github.com/hedge-dev/HMMCodes/blob/main/Source/Sonic%20Frontiers/Graphics/Display/Disable%20FPS%20Limit%20(experimental).hmm
(checked against commit 4de3a9b, 2026-10-13).

Target: SonicFrontiers.exe v1.41 (PE timestamp 2024-12-25). Each signature appears exactly once, at the v1.41 address.

| patch | address (v1.41) | change |
|---|---|---|
| sleep_call | 0x140D64D50 | NOP the 5-byte `call Sleep(ms)` in the frame limiter |
| fps_clamp | 0x140D64E21 | replace `comiss/cmova/mov/mov` (15 bytes) with `mov eax,[rax]; mov [rbx+144h],eax; mov [rdi],eax`. Sets the limiter's target fps to the measured fps, so delta time follows the real frame rate |
| cutscene_je | 0x140146A1C | `je` -> `jmp`: skip the SetTargetFps(30) / fixed-timestep path for cutscenes |
| refresh_60 | 0x1410EC6CE | fullscreen `DXGI_MODE_DESC.RefreshRate` 60/1 -> 0/0 (lets DXGI choose) |

Cap mode (`cap=N`): the sleep stays in place and fps_clamp becomes `mov dword [rdi], N.0f`.
The game's own limiter then targets N fps, and delta time is `max(1/N, real dt)`.

## Deploy

```sh
G="$HOME/Library/Application Support/Steam/steamapps/common/SonicFrontiers"
E="$HOME/Library/Application Support/Steam/steamapps/compatdata/1237320/steambridge.env"
cp dinput8.dll "$G/dinput8.dll"
echo 'WINEDLLOVERRIDES=dinput8=n,b' >> "$E"
```

The run script puts its own overrides in front of this value, so no other entries are needed.
Optional: copy `sonicfps.ini.example` to `"$G/sonicfps.ini"`, or put any of these in steambridge.env.
Environment variables override the ini.
Use the `STEAMBRIDGE_*` names below; the run script drops unknown prefixes.

- `STEAMBRIDGE_SONICFPS_CAP=120`: cap mode. `0` or unset means unlimited.
- `STEAMBRIDGE_SONICFPS=0`: turn off the patches but keep the DLL loaded.
- `STEAMBRIDGE_SONICFPS_CUTSCENES=0`: keep the 30 fps cutscene limit.
- `STEAMBRIDGE_SONICFPS_REFRESH=0`: keep the forced 60 Hz fullscreen mode.

Check after a launch: `"$G/sonicfps.log"` should contain `all patches applied at load` and `forwarding to C:\windows\system32\dinput8.dll`.

## Remove

```sh
rm "$G/dinput8.dll" "$G/sonicfps.ini" "$G/sonicfps.log"
sed -i '' '/^WINEDLLOVERRIDES=dinput8=n,b$/d' "$E"
```

If you only delete the DLL, the leftover override is harmless: Wine falls back to the builtin dinput8.
Steam "Verify integrity" does not remove extra files.

## Known issues (HMM, unlimited mode)

- Game speed can fluctuate.
- Wyvern's final QTE takes a long time to show up.
- Falling platforms in Cyber Space 2-5, 2-7 and 3-3 trigger faster.
- The 4-3 spawn point throws you into an invisible wall.
- Light dash can disconnect from its path.
- Some cutscenes stay at 30 fps (audio sync).

## Build

Run `./build.sh` (needs mingw-w64). The source is in `src/`; the result is `out/dinput8.dll`.
Copy it over `dinput8.dll` in this folder to ship it: `scripts/apply-game-configs.sh` installs that copy.
