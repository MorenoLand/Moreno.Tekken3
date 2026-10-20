# Tekken 3

A native Redot / Godot port of Tekken 3 (PS1, USA, SLUS-00402), built from the game's own data and logic. It needs your own disc image; no game data is in this repository.

## Goals

- Native: the game logic is rewritten in GDScript, with no emulator and no recompiled code.
- Reads the disc directly (`.cue` / `.bin`), or from a local extract made by `tools/` for faster loading.
- Cross-platform, including the web (WASM).
- Proper widescreen, window stretching and resolution upscaling.

## Setup

```
python tools/extract.py "path/to/Tekken 3.cue"
```

This reads the disc once and writes the ignored `assets/` folder: every archive record and member, the textures as PNG, the sound-bank samples and the CD music tracks as WAV. Options: `--records`, `--textures`, `--audio`, `--overwrite`. Existing files are kept unless `--overwrite` is given. Python 3.11+, standard library only.

Then open the folder with Redot 26.2 and run the main scene: a browser for the extracted textures, the two CD music tracks and every sound-bank sample.

## Status

Early. Done: disc and ISO reader, the archive table, the extractor, the asset browser. Not done: models, animation, the fight engine, menus, movies. Nothing is playable yet.
