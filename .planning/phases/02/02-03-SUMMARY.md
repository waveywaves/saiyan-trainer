---
phase: 02-neat-training-engine
plan: 03
subsystem: visualization
tags: [bizhawk, gui, neural-network, species-tracking, overlay]
dependency_graph:
  requires: [02-01]
  provides: [network-visualization, species-timeline, training-hud]
  affects: [main-training-loop]
tech_stack:
  added: []
  patterns: [bizhawk-gui-overlay, force-directed-layout, stacked-bar-chart, sliding-window]
key_files:
  created:
    - lua/vis/network_display.lua
    - lua/vis/hud.lua
    - lua/vis/species_timeline.lua
  modified: []
decisions:
  - Network display occupies left 132px of GBA screen, HUD top-right, timeline below HUD
  - Force-directed layout with 4 iterations for hidden node positioning
  - Species colors assigned by order of appearance with 16-color rotating palette
  - Sliding window of 50 generations for timeline display
metrics:
  duration: 2m 37s
  completed: 2026-03-06
  tasks_completed: 2
  tasks_total: 2
  files_created: 3
  files_modified: 0
requirements: [VIS-01, VIS-02, VIS-03]
---

# Phase 2 Plan 3: Neural Network Visualization and Species Timeline Summary

BizHawk GUI overlay system with real-time neural network topology display (labeled inputs/outputs, weight-colored connections, activation-brightness neurons, force-directed hidden nodes), training stats HUD (generation, species, fitness), and species timeline stacked bar chart tracking evolutionary dynamics over 50 generations.

## What Was Built

### Neural Network Display (lua/vis/network_display.lua)
- Renders evolved NEAT topology on left 132px of GBA screen
- Input nodes labeled with game state names (P1HP, P2HP, P1Ki, etc.) plus Bias
- Output nodes labeled with button names (A, B, L, R, Up, Down, Left, Right)
- Active outputs highlighted green, inactive in dark gray
- Connections color-coded: green for positive weights, red for negative weights
- Connection alpha/intensity scales with weight magnitude
- Disabled genes rendered as faint gray lines
- Neuron fill brightness maps activation value via sigmoid to grayscale
- Hidden nodes positioned via force-directed layout (4 iterations): connectivity-based X positioning, repulsion between close nodes
- Exports: `displayGenome(genome)`, `displayNetwork(genome)`

### Training HUD (lua/vis/hud.lua)
- Positioned top-right (x=140) outside network display area
- Shows: Generation, Species count, Genome progress (N/M), Fitness, Max Fitness, Staleness, optional FPS
- Semi-transparent black background for readability
- Fitness bar: horizontal green fill proportional to fitness/maxFitness with percentage label
- Exports: `displayHUD(pool, currentGenome, fps)`, `displayFitnessBar(fitness, maxFitness)`

### Species Timeline (lua/vis/species_timeline.lua)
- Stacked bar chart below HUD (x=140, y=82)
- Each column = one generation, segments = species (height proportional to genome count)
- 16-color rotating palette with consistent color assignment across generations
- Sliding window: last 50 generations displayed
- Generation number labels every 10th generation along bottom axis
- Checkpoint integration: `getHistory()` / `loadHistory()` for save/restore
- Text summary: `getSummary()` returns species distribution string
- Exports: `record(pool)`, `display()`, `getSummary()`, `getHistory()`, `loadHistory()`, `reset()`

## Commits

| Task | Commit  | Description                                    |
|------|---------|------------------------------------------------|
| 1    | 24818d9 | Neural network visualization overlay and HUD   |
| 2    | 4df8c90 | Species timeline tracker and renderer           |

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

All 10 verification checks passed:
1. Input neurons labeled with game state names
2. Output neurons labeled with button names
3. Connections colored green (positive) / red (negative)
4. Neuron brightness varies with activation value
5. Hidden neurons positioned with force-directed layout
6. HUD shows generation, species, genome, fitness stats
7. Species timeline records per-generation membership
8. Stacked bar chart with distinct colors per species
9. All modules use gui.* BizHawk API exclusively
10. No modules modify game state or training behavior

## Self-Check: PASSED

All 3 created files exist. Both commit hashes (24818d9, 4df8c90) verified in git log.
