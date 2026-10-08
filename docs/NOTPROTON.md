# NotProton (Steam Play for macOS)

[NotProton](https://github.com/NotProtonNot/NotProton) appeared in September 2026. It turns
on Steam Play inside the **native macOS Steam client**, the same feature Proton uses on Linux
and the Steam Deck. Windows games then install and launch straight from Mac Steam, with no
separate Windows Steam client.

```
This repo:  Mac -> Sikarugir wrapper -> Windows Steam client -> game
NotProton:  Mac -> native Mac Steam (patched) -> CrossOver Wine -> game
```

That avoids most of the Windows-Steam problems in [TROUBLESHOOTING.md](TROUBLESHOOTING.md):
the webhelper stalls, the installer loop and `0x3008`.

## Why it isn't part of this free stack

NotProton itself is free and open source (GPL-3.0). The catch is the Wine it runs on:

- **It only works with paid CrossOver.** The app checks for an activated CrossOver licence
  (`CrossOverLicense.swift`).
- **Only specific CrossOver Preview builds are accepted** (checked by hash in
  `SupportedRunner.swift`). CrossOver Preview is only available to licence holders
  ([codeweavers.com/preview](https://www.codeweavers.com/preview)).
- **The maintainer won't add free-Wine support.** A pull request adding it was closed with
  "Supporting things that are not CrossOver is not a design goal of this project"
  ([PR #18](https://github.com/NotProtonNot/NotProton/pull/18)).

If you own CrossOver, NotProton is worth trying for Steam games alongside this setup.

## Can it be forked to use free Wine?

**Yes, legally.** The GPL allows it, and running it on your own free Wine doesn't
circumvent anything because CrossOver isn't involved at all. Do **not** strip the licence
check while still running on CrossOver; that's just piracy.

**A free fork already exists, but it's unproven:**
[Maxyme/NotProton, branch `standalone-steam-gptk4`](https://github.com/Maxyme/NotProton/tree/standalone-steam-gptk4)
(2 Oct 2026). It is the rejected PR #18, which:

- uses Gcenx's free Wine-Crossover 8.0.1 build and Apple GPTk 4 beta 2 instead of CrossOver
- registers as a "Game Porting Toolkit 4" compatibility tool in native Steam
- adds a compatibility layer so Valve's Steam bridge works with the free Wine, plus fixes for
  D3DMetal crashing on 64-bit games and for Steam killing games after 10–35 seconds

Caveats:
- One author, no stars, and the PR says the code was AI-generated. Nobody else has tested it.
- It uses Wine 8.0.1, older than this repo's Wine 11. 32-bit games are "not proven to run".
- It **re-signs and injects into your native `/Applications/Steam.app`**, the same Steam that
  runs native Mac games. Back up Steam.app first.
- Like NotProton, it's tied to specific Steam client builds, so a Steam update can break it.

**Building our own fork** would be cleaner: NotProton's Steam bridge (`lsteamclient`) is
already built against stock Wine 11.15 (`bridge/setup-wine-tree.sh`), which is close to
Sikarugir's Wine 11. The hard parts are the `ntdll.dll` loader patch (written for exact
CrossOver builds; `ntdll-patch/resolve.py` can work out new values for a different build)
and turning on D3DMetal outside CrossOver. Expect several days of work and ongoing upkeep.

## Status (8 October 2026)

| | |
|---|---|
| NotProton | 1.0.3 (6 Oct 2026); 1.1.0 announced |
| Requires | macOS 26+, Apple Silicon, CrossOver Preview 20260821 or 20261006 |
| Anti-cheat | Still fails (CS2: [#27](https://github.com/NotProtonNot/NotProton/issues/27)) |
| EA App | Not documented |
| D3DMetal | Only on CrossOver's Rosetta build, not the FEX (ARM64) build |
