# Portal Smash

A VR block-smashing game built with **Godot 4.7** and **OpenXR**. Grab a ball in each hand, throw it at a tower of physical blocks, and clear ten increasingly creative designs.

## What it is

Portal Smash drops you in a small lab room facing a tall stack of cubes. Each round presents a new block arrangement. Knock down 98% of the current design and the next one rises from the floor. After all ten designs are destroyed, a congratulatory message appears along with a restart box — hit it with a ball to start the campaign over.

The game is designed for standing VR with two motion controllers.

## Features

- **Two throwable balls** — one bound to each controller (left ball is cyan, right ball is orange).
- **10 round designs** — pyramid, wall, brick wall, ziggurat, A-frame, square pyramid, cylinder, thick cross, spiral, and castle.
- **Physical blocks** — cubes are smaller and more numerous; they briefly indent on impact to feel like real objects.
- **Power-ups** — random drops grant Heavy, Ice, or Fire balls.
- **Restart flow** — complete all rounds, read the congratulations, then smash the green restart box to reset.
- **Procedural audio** — all one-shot sounds are synthesized at runtime, no external audio files.

## Controls

| Action | Binding |
|--------|---------|
| Grab a ball | Hold **grip** on the hand whose ball you want |
| Throw | Swing and release **grip** |
| Reset rounds | **menu_button** on either controller, or **ax_button** on the right controller |
| Adjust movement speed | **primary_click** (A/X) |
| Walk | Left/right stick **up/down** |
| Snap turn | Left/right stick **left/right** |

## Running the project

Open the `app/` folder as a Godot 4.7 project and run `res://scenes/main.tscn`. OpenXR will initialize automatically when a headset is present; otherwise it runs in non-VR mode for testing.

## Building

From the repository root:

```bash
bash tools/export.sh
```

This produces `build/portalsmash.arm64` (Linux ARM64) and writes the launcher name to `build/launcher-name.txt`.

## Project structure

```
.
├── app/
│   ├── scenes/main.tscn       # Main VR scene
│   ├── scripts/main.gd        # Game logic, rounds, designs
│   ├── scripts/xr_rig.gd      # XR origin / locomotion
│   ├── scripts/sound_kit.gd   # Procedural audio
│   └── tests/                 # Headless test suite
├── tools/export.sh            # Build script
└── build/                     # Exported binaries
```

## Tests

Run the headless suite with:

```bash
timeout 300 env -u DISPLAY godot --headless --xr-mode off --path app -s res://tests/test_game.gd
```

A visual smoke test can be run with:

```bash
timeout 120 xvfb-run -a godot --path app --xr-mode off res://tests/screenshot.tscn
```

## License

This is a personal project; no license is specified.
