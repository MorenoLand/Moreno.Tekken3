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

This reads the disc once and writes the ignored `assets/` folder: every archive record and member, the textures as PNG, the sound-bank samples and the CD music tracks as WAVand the shipped executable. Options: `--records`, `--textures`, `--audio`, `--overwrite`. Existing files are kept unless `--overwrite` is given. Python 3.11+, standard library only.

Then open the folder with Redot 26.2 and run the main scene (title, character select, fight view; F2 toggles the original 4:3 shape, the default fills the window; keyboard and controller).

## Playing

Run the main scene. The intro movie leads to the title menu: arcade (ten fights), VS, team battle, time attack, survival, practice, theater and option modes. Tekken Ball (the ball physics, hit rules and beach arena) and Tekken Force (four side-scrolling stages with a boss each, keys and the final stage that unlocks Doctor B) are playable from the title menu.

Default keys, both remappable under Option Mode, Key Configuration (a controller works out of the box, the d-pad or left stick moves, X / Y / A / B are the four attack buttons, Start or Esc pauses, with Cancel / Command / Reset):

| | Move | LP | RP | LK | RK | Start |
|---|---|---|---|---|---|---|
| Player 1 | W A S D | U | I | J | K | Enter |
| Player 2 | arrow keys | Num 4 | Num 5 | Num 1 | Num 2 | Num Enter |

F2 switches between the widescreen view and the original 4:3 shape.

## Status

Playable. The fight engine (input history, cancel lists, move playback, movement, hit detection, damage, reactions, rounds) is ported from the game's own code and its sound effects, voices, music and stages are read from the disc. The fighters, the fifteen stages, the HUD, the menus and the movies are native. The computer opponent is a simple stand-in, not the original AI, and the in-fight camera is a plain follow camera. The theater (movies and the music player), the VS screen, the continue scene and the option pages (game, sounds, keys, records, display adjust, memory card) follow the original screens. Not done: the in-fight camera shots, the attract-mode record screens and the Command list of the pause menu.
