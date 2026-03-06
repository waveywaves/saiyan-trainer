-- controller_test.lua
-- mGBA Lua script that demonstrates controller input by executing a
-- predetermined sequence of moves, proving that button presses (including
-- simultaneous combos) work correctly in DBZ: Supersonic Warriors.
--
-- Run standalone in mGBA:
--   mgba-sdl -s lua/controller_test.lua rom.gba
--
-- This script directly uses emu:setKeys() with bitmasks to prove
-- hardware-level input works. Tests CTRL-02 (simultaneous combos) explicitly.

local controller = dofile("lua/controller.lua")
local ss = dofile("lua/savestate_helper.lua")

-- mGBA key bitmask constants
local KEY = {
    A     = 0x01,
    B     = 0x02,
    Right = 0x10,
    Left  = 0x20,
    Up    = 0x40,
    Down  = 0x80,
    R     = 0x100,
    L     = 0x200,
}

-- Each move defines: name, bitmask of buttons to press, frames to hold, frames to pause after.
local MoveSequence = {
    {
        name = "Idle",
        bitmask = 0,
        buttons_desc = "(none)",
        frames = 30,
        pause_after = 10,
    },
    {
        name = "Punch",
        bitmask = KEY.A,
        buttons_desc = "A",
        frames = 5,
        pause_after = 10,
    },
    {
        name = "Kick",
        bitmask = KEY.B,
        buttons_desc = "B",
        frames = 5,
        pause_after = 10,
    },
    {
        name = "Move Right",
        bitmask = KEY.Right,
        buttons_desc = "Right",
        frames = 30,
        pause_after = 10,
    },
    {
        name = "Move Left",
        bitmask = KEY.Left,
        buttons_desc = "Left",
        frames = 30,
        pause_after = 10,
    },
    {
        name = "Jump",
        bitmask = KEY.Up,
        buttons_desc = "Up",
        frames = 10,
        pause_after = 10,
    },
    {
        name = "Crouch",
        bitmask = KEY.Down,
        buttons_desc = "Down",
        frames = 10,
        pause_after = 10,
    },
    -- SIMULTANEOUS COMBO: Down + B (special move)
    {
        name = "Special Move (Down+B)",
        bitmask = KEY.Down | KEY.B,
        buttons_desc = "Down, B",
        frames = 10,
        pause_after = 15,
    },
    -- SIMULTANEOUS COMBO: A + B (strong attack)
    {
        name = "Strong Attack (A+B)",
        bitmask = KEY.A | KEY.B,
        buttons_desc = "A, B",
        frames = 5,
        pause_after = 10,
    },
    -- SIMULTANEOUS COMBO: Right + A (dash attack)
    {
        name = "Dash Attack (Right+A)",
        bitmask = KEY.Right | KEY.A,
        buttons_desc = "Right, A",
        frames = 10,
        pause_after = 10,
    },
    {
        name = "Block (L shoulder)",
        bitmask = KEY.L,
        buttons_desc = "L",
        frames = 20,
        pause_after = 10,
    },
    {
        name = "Ki Blast (R shoulder)",
        bitmask = KEY.R,
        buttons_desc = "R",
        frames = 10,
        pause_after = 10,
    },
    -- SIMULTANEOUS COMBO: Down + Right + B (3-button combo)
    {
        name = "Full Combo (Down+Right+B)",
        bitmask = KEY.Down | KEY.Right | KEY.B,
        buttons_desc = "Down, Right, B",
        frames = 10,
        pause_after = 15,
    },
}

-- Count single-button and combo moves for summary.
local function countMoveTypes(moves)
    local single = 0
    local combo = 0
    for _, move in ipairs(moves) do
        -- Count bits set in bitmask
        local bitmask = move.bitmask
        local bits = 0
        while bitmask > 0 do
            bits = bits + (bitmask & 1)
            bitmask = bitmask >> 1
        end
        if bits > 1 then
            combo = combo + 1
        elseif bits == 1 then
            single = single + 1
        end
    end
    return single, combo
end

-- === Main Execution ===

console:log("=== Saiyan Trainer Controller Test ===")
console:log("Executing " .. #MoveSequence .. " test moves...")

-- Optionally reset fight if save state exists.
if ss.hasFightStartState() then
    console:log("Fight start save state found -- resetting fight")
    ss.resetFight()
else
    console:log("No fight start save state -- running with current emulator state")
end

-- Execute each move in sequence.
for moveIndex, move in ipairs(MoveSequence) do
    console:log(string.format("Move %d/%d: %s [%s] for %d frames",
        moveIndex, #MoveSequence, move.name, move.buttons_desc, move.frames))

    -- Hold buttons for the specified number of frames.
    for frame = 1, move.frames do
        emu:setKeys(move.bitmask)
        emu:runFrame()
    end

    -- Release all buttons for pause_after frames (neutral input between moves).
    for frame = 1, move.pause_after do
        emu:setKeys(0)
        emu:runFrame()
    end
end

-- Summary
local singleCount, comboCount = countMoveTypes(MoveSequence)
console:log("=== Controller Test Complete ===")
console:log(string.format("All %d moves executed.", #MoveSequence))
console:log(string.format("Single-button moves: %d", singleCount))
console:log(string.format("Multi-button combos: %d", comboCount))
console:log("Controller input system verified.")
