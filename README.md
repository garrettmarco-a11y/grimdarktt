# Grimdark Tactical Tactics

This repository now includes the initial Godot project structure for a tactical squad combat prototype.

## Layout

- `project.godot` — Godot project definition
- `assets/` — art, audio, and fonts
- `scenes/` — gameplay and UI scenes
- `scripts/` — gameplay logic and resource definitions

## Running tests

Requires Godot 4.4. From the project root:

```bash
godot --headless --path . --import
godot --headless --path . -s res://tests/run_tests.gd
```

The first command builds the import cache (needed once per fresh checkout). The runner prints `PASS`/`FAIL` per test and exits with code 1 if any test fails.
