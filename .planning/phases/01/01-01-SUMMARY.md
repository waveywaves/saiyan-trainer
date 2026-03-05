---
phase: 01-emulation-foundation
plan: 01
subsystem: memory-map
tags: [gba, bizhawk, lua, memory-map, diagnostics]
dependency_graph:
  requires: []
  provides: [memory-map-config, memory-reader-diagnostic, utils-module]
  affects: [01-02]
tech_stack:
  added: [lua-5.4-module-pattern, bizhawk-lua-api]
  patterns: [centralized-config, dofile-module-loading, system-bus-domain]
key_files:
  created:
    - lua/memory_map.lua
    - lua/memory_reader.lua
    - lua/utils.lua
    - docs/MEMORY_MAP.md
  modified: []
decisions:
  - "System Bus domain for all memory reads (matches cheat DBs, avoids IWRAM offset confusion)"
  - "dofile() for BizHawk module loading instead of require (BizHawk-compatible)"
  - "Placeholder addresses in 0x03000000 range for user to fill in after RAM Search"
  - "Verified field on each entry to track discovery progress"
  - "Color-coded overlay: green for verified addresses, yellow for unverified"
metrics:
  duration: "3 minutes"
  completed: "2026-03-06"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 0
---

# Phase 1 Plan 1: Memory Map Config and Diagnostic Reader Summary

Centralized GBA memory address config with 12 typed entries, BizHawk diagnostic overlay script, and RAM Search discovery documentation for DBZ Supersonic Warriors.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Memory map config and utility modules | 0ea4b83 | lua/memory_map.lua, lua/utils.lua |
| 2 | Diagnostic memory reader and reference docs | 0ea4b83 | lua/memory_reader.lua, docs/MEMORY_MAP.md |

## What Was Built

### lua/memory_map.lua
- Single source of truth for all 12 memory addresses (p1_health, p1_ki, p1_x, p1_y, p1_state, p2_health, p2_ki, p2_x, p2_y, p2_state, round_state, timer)
- Each entry has addr, size, type, desc, and verified fields
- `MemoryMap.read(entry)` dispatches to correct BizHawk API (u8, u16_le, s16_le, u32_le) with System Bus domain
- `MemoryMap.readAll()` returns all game state as {name = value} table
- `MemoryMap.getUnverified()` lists entries still needing real addresses
- Two entries pre-verified from cheat code seeds: p1_ki (0x0300274A) and round_state (0x03002826)

### lua/memory_reader.lua
- BizHawk diagnostic script with color-coded on-screen overlay
- Left column: P1 values (health, ki, x, y, state)
- Right column: P2 values
- Bottom row: round state and timer
- Green text for verified addresses, yellow for unverified
- Console logging throttled to every 60 frames
- Startup banner lists all unverified addresses

### lua/utils.lua
- `formatHex(value)` -- formats numbers as "0xNNNN" hex strings
- `formatState(name, value, entry)` -- formats state entries for display

### docs/MEMORY_MAP.md
- Complete address table with all 12 entries
- Step-by-step RAM Search instructions for each variable type (health, ki, position, timer, attack state, round state)
- Known cheat code seeds with CodeBreaker format reference
- Address conventions (System Bus domain, IWRAM range, P1/P2 offset notes)
- Post-discovery update instructions

## Decisions Made

1. **System Bus domain exclusively** -- all reads specify "System Bus" to match cheat database conventions and avoid IWRAM base-offset confusion
2. **dofile() over require()** -- BizHawk Lua does not use standard require paths; dofile with relative paths is the compatible approach
3. **Placeholder addresses** -- all addresses in 0x03000000 range are placeholders except the two cheat-code seeds; user replaces them after RAM Search discovery
4. **Verified tracking** -- boolean field on each entry lets the diagnostic overlay and getUnverified() show discovery progress

## Deviations from Plan

None -- plan executed exactly as written.

## Verification Results

- 12 address entries confirmed in memory_map.lua
- 3 functions exported (read, readAll, getUnverified)
- 2 utility functions in utils.lua (formatHex, formatState)
- memory_reader.lua uses dofile, gui.text, emu.frameadvance
- No hardcoded addresses outside memory_map.lua (0 matches in memory_reader.lua)
- docs/MEMORY_MAP.md contains all 12 addresses with discovery methodology

## Self-Check: PASSED

All 4 created files exist on disk. Commit 0ea4b83 verified in git log.
