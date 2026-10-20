# Tekken 3

A native Redot / Godot port of Tekken 3 (PS1, USA, SLUS-00402), built from the game's own data and logic. It needs your own disc image; no game data is in this repository.

## Goals

- Native: the game logic is rewritten in GDScript, with no emulator and no recompiled code.
- Reads the disc directly (`.cue` / `.bin`), or from a local extract made by `tools/` for faster loading.
- Cross-platform, including the web (WASM).
- Proper widescreen, window stretching and resolution upscaling.

## Status

Early. The disc reader and the archive table are done; see `tools/disc.py`. Nothing is playable yet.
