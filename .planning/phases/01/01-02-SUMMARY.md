---
phase: 01-emulation-foundation
plan: 02
subsystem: controller-interface
tags: [controller, savestate, bizhawk, lua, gba]
dependency-graph:
  requires: []
  provides: [controller-input, savestate-management, fight-reset]
  affects: [neat-training-loop, genome-evaluation]
tech-stack:
  added: []
  patterns: [output-to-controller-mapping, save-state-anchoring, module-pattern]
key-files:
  created:
    - lua/controller.lua
    - lua/controller_test.lua
    - lua/savestate_helper.lua
    - savestates/.gitkeep
  modified:
    - .gitignore
decisions:
  - "8 GBA buttons for NEAT output mapping (excluded Start/Select as not useful for fighting)"
  - "Threshold > 0 for button press (positive NEAT output = pressed)"
  - "File-based save states over slot-based for portability and clarity"
  - "event.onloadstate guarded by conditional check for non-BizHawk environments"
metrics:
  duration: "2m 4s"
  completed: "2026-03-05T21:08:37Z"
  tasks: 2
  files: 5
---

# Phase 1 Plan 2: Controller Interface, Save State Management, and Project Setup Summary

Controller input system mapping 8 NEAT output neurons to GBA buttons with simultaneous combo support, save state helper for deterministic fight resets, and project setup with ROM/savestate gitignore patterns.

## What Was Built

### lua/controller.lua
- `ButtonNames` array with 8 GBA buttons: A, B, L, R, Up, Down, Left, Right
- `NUM_OUTPUTS` constant (8) for NEAT network configuration
- `outputsToController(outputs)` -- converts NEAT output array to button table using > 0 threshold; naturally supports simultaneous combos when multiple outputs are positive
- `applyController(outputs)` -- convenience wrapper that converts outputs then calls `joypad.set()`
- `clearController()` -- releases all buttons via `joypad.set({})`
- `getButtonNames()` and `getNumOutputs()` getters for NEAT configuration
- Module pattern export via `return Controller`

### lua/savestate_helper.lua
- Configurable `SAVE_STATE_DIR` and `FIGHT_START_FILE` paths
- `hasFightStartState()` -- checks file existence via `io.open`
- `resetFight()` -- loads fight-start save state with `savestate.load()`, returns success/failure with error message
- `createFightStartState()` -- saves current emulator frame with `savestate.save()`
- `getFightStartFile()` -- path getter
- `event.onloadstate` callback for debugging (guarded by conditional check)

### lua/controller_test.lua
- 13 test moves including 4 simultaneous combo inputs:
  - Down+B (special move)
  - A+B (strong attack)
  - Right+A (dash attack)
  - Down+Right+B (3-button full combo)
- Each move displays on-screen overlay via `gui.text()` with move name, buttons, and frame counter
- Uses `emu.frameadvance()` in all loops (no emulator freezing)
- Loads controller module via `dofile("lua/controller.lua")`
- Optionally resets fight if save state exists
- Prints summary with single-button and combo move counts
- Runnable standalone: `EmuHawk --lua=lua/controller_test.lua rom.gba`

### .gitignore Updates
- Added ROM sourcing instructions as comments
- Added `savestates/*.State` and `savestates/*.state` exclusion patterns

### savestates/.gitkeep
- Directory tracked by git but save state files excluded

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1-2  | 82326ee | feat: add controller, save state helper, and test script |

## Deviations from Plan

None - plan executed exactly as written.

## Decisions Made

1. **8 buttons for NEAT outputs** -- Start and Select excluded as they do not contribute to fighting
2. **Threshold > 0** -- NEAT sigmoid/tanh outputs: positive = press, zero or negative = release
3. **File-based save states** -- More portable than slot-based; path is configurable
4. **Guarded event.onloadstate** -- Wrapped in conditional so the module can be loaded outside BizHawk for testing purposes

## Self-Check: PASSED

All 5 files verified present. Commit 82326ee verified in git log.
