-- memory_reader.lua
-- Diagnostic BizHawk Lua script for DBZ: Supersonic Warriors (USA).
--
-- Reads ALL game state from memory via memory_map.lua and displays it
-- as a color-coded on-screen overlay.  Load this script in BizHawk during
-- a fight to verify that memory addresses are returning correct values.
--
-- Usage:
--   BizHawk > Tools > Lua Console > Open Script > lua/memory_reader.lua
--   Or launch: EmuHawk --lua=lua/memory_reader.lua "roms/Dragon Ball Z - Supersonic Warriors (USA).gba"

---------------------------------------------------------------------------
-- Module loading (BizHawk uses dofile, not standard require paths)
---------------------------------------------------------------------------
local mm    = dofile("lua/memory_map.lua")
local utils = dofile("lua/utils.lua")

---------------------------------------------------------------------------
-- Display configuration
---------------------------------------------------------------------------
local COLOR_VERIFIED   = 0xFF00FF00  -- green  (ARGB: fully opaque green)
local COLOR_UNVERIFIED = 0xFFFFFF00  -- yellow (ARGB: fully opaque yellow)
local COLOR_LABEL      = 0xFFFFFFFF  -- white
local LINE_HEIGHT      = 14

-- Layout columns
local COL_P1_X   = 10   -- left column for P1
local COL_P2_X   = 150  -- right column for P2
local COL_MATCH_Y = 140  -- bottom row for match-level state
local HEADER_Y   = 2

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Pick overlay color based on whether the address has been verified.
local function colorFor(entryName)
    local entry = mm[entryName]
    if entry and entry.verified then
        return COLOR_VERIFIED
    end
    return COLOR_UNVERIFIED
end

--- Display a single value on the BizHawk overlay.
local function drawEntry(x, y, label, value, entryName)
    local color = colorFor(entryName)
    local text  = string.format("%s: %d", label, value or 0)
    gui.text(x, y, text, color)
end

---------------------------------------------------------------------------
-- Overlay renderer
---------------------------------------------------------------------------

--- Render the full game-state overlay onto BizHawk's screen.
-- @param state table  {name = value} from mm.readAll()
local function displayOverlay(state)
    -- Header
    gui.text(COL_P1_X, HEADER_Y, "=== Saiyan Trainer ===", COLOR_LABEL)

    -- Player 1 column (left)
    local y = HEADER_Y + LINE_HEIGHT + 4
    gui.text(COL_P1_X, y, "-- P1 --", COLOR_LABEL)
    y = y + LINE_HEIGHT
    drawEntry(COL_P1_X, y, "Health", state.p1_health, "p1_health"); y = y + LINE_HEIGHT
    drawEntry(COL_P1_X, y, "Ki",     state.p1_ki,     "p1_ki");     y = y + LINE_HEIGHT
    drawEntry(COL_P1_X, y, "X",      state.p1_x,      "p1_x");     y = y + LINE_HEIGHT
    drawEntry(COL_P1_X, y, "Y",      state.p1_y,      "p1_y");     y = y + LINE_HEIGHT
    drawEntry(COL_P1_X, y, "State",  state.p1_state,  "p1_state")

    -- Player 2 column (right)
    y = HEADER_Y + LINE_HEIGHT + 4
    gui.text(COL_P2_X, y, "-- P2 --", COLOR_LABEL)
    y = y + LINE_HEIGHT
    drawEntry(COL_P2_X, y, "Health", state.p2_health, "p2_health"); y = y + LINE_HEIGHT
    drawEntry(COL_P2_X, y, "Ki",     state.p2_ki,     "p2_ki");     y = y + LINE_HEIGHT
    drawEntry(COL_P2_X, y, "X",      state.p2_x,      "p2_x");     y = y + LINE_HEIGHT
    drawEntry(COL_P2_X, y, "Y",      state.p2_y,      "p2_y");     y = y + LINE_HEIGHT
    drawEntry(COL_P2_X, y, "State",  state.p2_state,  "p2_state")

    -- Match state (bottom row)
    drawEntry(COL_P1_X,  COL_MATCH_Y, "Round", state.round_state, "round_state")
    drawEntry(COL_P2_X,  COL_MATCH_Y, "Timer", state.timer,       "timer")
end

---------------------------------------------------------------------------
-- Console logger (throttled)
---------------------------------------------------------------------------

--- Print a summary line to BizHawk's Lua console.
-- @param state table  {name = value} from mm.readAll()
local function logToConsole(state)
    local line = string.format(
        "P1 Health: %d | P2 Health: %d | P1 Ki: %d | P2 Ki: %d | Timer: %d | Round: %d",
        state.p1_health or 0,
        state.p2_health or 0,
        state.p1_ki     or 0,
        state.p2_ki     or 0,
        state.timer      or 0,
        state.round_state or 0
    )
    console.log(line)
end

---------------------------------------------------------------------------
-- Startup banner
---------------------------------------------------------------------------
console.log("=== Saiyan Trainer Memory Reader ===")
console.log("Loaded memory_map.lua -- reading all game state each frame.")

local unverified = mm.getUnverified()
if #unverified > 0 then
    console.log("WARNING: The following addresses are UNVERIFIED (placeholder values):")
    for _, name in ipairs(unverified) do
        local entry = mm[name]
        console.log(string.format(
            "  %s  addr=%s  type=%s",
            name, utils.formatHex(entry.addr), entry.type
        ))
    end
    console.log("Replace placeholders with real addresses found via BizHawk RAM Search.")
else
    console.log("All addresses verified.")
end
console.log("")

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local frameCount = 0
local LOG_INTERVAL = 60  -- log to console every 60 frames to avoid spam

while true do
    local state = mm.readAll()

    -- Always draw overlay (updates every frame)
    displayOverlay(state)

    -- Throttled console logging
    if frameCount % LOG_INTERVAL == 0 then
        logToConsole(state)
    end

    frameCount = frameCount + 1
    emu.frameadvance()
end
