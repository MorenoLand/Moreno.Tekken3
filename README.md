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

This reads the disc once and writes the ignored `assets/` folder: every archive record and member, the textures as PNG, the sound-bank samples and the CD music tracks as WAV, and every fighter as a textured, posed model. Options: `--records`, `--textures`, `--audio`, `--models`, `--overwrite`. Existing files are kept unless `--overwrite` is given. Python 3.11+, standard library only.

Then open the folder with Redot 26.2 and run the main scene: a browser for the extracted textures, the two CD music tracks, every sound-bank sample and the fighter models (drag to orbit, wheel to zoom).

## Status

Early. Done: disc reader, extractor, asset browser, fighter models with textures, the motion decoder and the skeleton pose. Not done: playing animations, the fight engine, menus, movies. Nothing is playable yet.
