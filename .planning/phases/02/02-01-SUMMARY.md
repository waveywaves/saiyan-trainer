---
phase: 02-neat-training-engine
plan: 01
subsystem: neat-core
tags: [neat, neuroevolution, fitness, lua, algorithm]
dependency_graph:
  requires: [memory_map]
  provides: [neat-config, neat-genome, neat-network, neat-mutation, neat-crossover, neat-species, neat-pool, neat-innovation, game-inputs, game-fitness, dkjson]
  affects: [training-loop, checkpoint, visualization]
tech_stack:
  added: [dkjson-minimal]
  patterns: [dofile-modules, NEAT-MarIO-pattern, multi-component-fitness]
key_files:
  created:
    - lua/neat/config.lua
    - lua/neat/genome.lua
    - lua/neat/innovation.lua
    - lua/neat/network.lua
    - lua/neat/mutation.lua
    - lua/neat/crossover.lua
    - lua/neat/species.lua
    - lua/neat/pool.lua
    - lua/game/inputs.lua
    - lua/game/fitness.lua
    - lua/lib/dkjson.lua
    - tests/test_neat.lua
  modified: []
decisions:
  - Used minimal JSON implementation instead of downloading dkjson since we need BizHawk-compatible pure Lua
  - Population size 300 with StaleSpecies 30 (doubled from MarI/O's 15) for fighting game complexity
  - Dynamic compatibility threshold targeting 12 species with 0.3 floor
  - NEAT sigmoid 2/(1+exp(-4.9*x))-1 per original NEAT paper
  - Fitness weights: offense 2.0, defense 1.5, win +1000, loss -500, stall -0.5/frame
metrics:
  completed: "2026-03-06"
  tasks_completed: 2
  tasks_total: 2
  files_created: 12
  test_assertions: 67
  test_functions: 22
---

# Phase 2 Plan 1: NEAT Algorithm Core and Fitness Function Summary

Complete NEAT neuroevolution engine in modular Lua with MarI/O-derived architecture, multi-component fighting game fitness (offense/defense/win/loss/stall/self-destruction guard), and 22 passing tests validating all operations.

## What Was Built

### NEAT Core (8 modules in lua/neat/)
- **config.lua**: All hyperparameters -- population 300, 11 inputs, 8 outputs, MaxNodes 1M, compatibility distance coefficients, mutation rates, dynamic threshold targeting 12 species
- **innovation.lua**: Global innovation counter with increment, reset, and get operations
- **genome.lua**: Gene and Genome data structures with newGenome, newGene, copyGene, copyGenome (deep copy), and basicGenome (minimal topology seed with Inputs*Outputs connections)
- **network.lua**: Neural network construction from genome genes and sigmoid forward pass. NEAT sigmoid: 2/(1+exp(-4.9*x))-1. Evaluates all non-input neurons in sorted order.
- **mutation.lua**: Point mutation (weight perturbation/randomization), link mutation (new connection with innovation tracking), node mutation (connection splitting), enable/disable mutation. Main mutate() applies all operators with rate-based probability.
- **crossover.lua**: Aligns genes by innovation number. Matching genes randomly selected from either parent. Disjoint/excess from fitter parent.
- **species.lua**: Compatibility distance (disjoint + weight diff), speciation (addToSpecies), fitness sharing (calculateAverageFitness), culling (cullSpecies, removeStaleSpecies, removeWeakSpecies), dynamic threshold adjustment.
- **pool.lua**: Population initialization (newPool), global ranking (rankGlobally), breeding with crossover + mutation, newGeneration with elitism (best genome per species preserved).

### Game Integration (2 modules in lua/game/)
- **inputs.lua**: 11-element normalized input vector from memory map (P1/P2 health, ki, distance X/Y, attack states, round state, timer, bias)
- **fitness.lua**: 6-component fitness: offense reward (FIT-01), defense penalty (FIT-02), win bonus +1000 (FIT-03), loss penalty -500 (FIT-04), anti-stall after 300 frames (FIT-05), self-destruction guard (FIT-06). Floor at -1 to avoid 0.

### Supporting
- **lua/lib/dkjson.lua**: Minimal pure-Lua JSON encoder/decoder supporting strings, numbers, booleans, null, arrays, objects, nested structures
- **tests/test_neat.lua**: 22 test functions with 67 assertions covering all NEAT operations

## Deviations from Plan

None - plan executed exactly as written.

## Decisions Made

1. **Minimal JSON instead of vendored dkjson**: Created a ~200-line JSON implementation rather than downloading the full dkjson library. Handles all needed types (strings, numbers, booleans, arrays, objects, nested). MIT-compatible.
2. **Dependency injection pattern**: Modules that depend on other modules use a `setDependencies()` function rather than dofile at load time. This prevents circular dependencies and makes testing easier.
3. **Lua 5.5 compatibility**: Tests run on Lua 5.5 (installed via Homebrew). The integer/float distinction works the same as 5.4. Used math.floor() for all index operations.

## Commits

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1-2 | NEAT core + game integration | 50fc6c2 | All 12 files |

## Verification

- 22/22 test functions passed
- 67/67 assertions passed
- No require() calls (BizHawk compatible)
- All modules follow local M = {} ... return M pattern
- Fitness function produces correct scores: winning with damage = 1050.0

## Self-Check: PASSED

- All 12 created files verified to exist on disk
- Commit 50fc6c2 verified in git log
