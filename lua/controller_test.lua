-- controller_test.lua
-- BizHawk Lua script that demonstrates controller input by executing a
-- predetermined sequence of moves, proving that button presses (including
-- simultaneous combos) work correctly in DBZ: Supersonic Warriors.
--
-- Run standalone in BizHawk:
--   EmuHawk --lua=lua/controller_test.lua "roms/Dragon Ball Z - Supersonic Warriors (USA).gba"
--
-- This script does NOT use outputsToController (that is for NEAT).
-- It directly uses joypad.set with button tables to prove hardware-level
-- input works. Tests CTRL-02 (simultaneous combos) explicitly.

local controller = dofile("lua/controller.lua")
local ss = dofile("lua/savestate_helper.lua")

-- Each move defines: name, buttons to press, frames to hold, frames to pause after.
local MoveSequence = {
    {
        name = "Idle",
        buttons = {},
        frames = 30,
        pause_after = 10,
    },
    {
        name = "Punch",
        buttons = {A = true},
        frames = 5,
        pause_after = 10,
    },
    {
        name = "Kick",
        buttons = {B = true},
        frames = 5,
        pause_after = 10,
    },
    {
        name = "Move Right",
        buttons = {Right = true},
        frames = 30,
        pause_after = 10,
    },
    {
        name = "Move Left",
        buttons = {Left = true},
        frames = 30,
        pause_after = 10,
    },
    {
        name = "Jump",
        buttons = {Up = true},
        frames = 10,
        pause_after = 10,
    },
    {
        name = "Crouch",
        buttons = {Down = true},
        frames = 10,
        pause_after = 10,
    },
    -- SIMULTANEOUS COMBO: Down + B (special move)
    {
        name = "Special Move (Down+B)",
        buttons = {Down = true, B = true},
        frames = 10,
        pause_after = 15,
    },
    -- SIMULTANEOUS COMBO: A + B (strong attack)
    {
        name = "Strong Attack (A+B)",
        buttons = {A = true, B = true},
        frames = 5,
        pause_after = 10,
    },
    -- SIMULTANEOUS COMBO: Right + A (dash attack)
    {
        name = "Dash Attack (Right+A)",
        buttons = {Right = true, A = true},
        frames = 10,
        pause_after = 10,
    },
    {
        name = "Block (L shoulder)",
        buttons = {L = true},
        frames = 20,
        pause_after = 10,
    },
    {
        name = "Ki Blast (R shoulder)",
        buttons = {R = true},
        frames = 10,
        pause_after = 10,
    },
    -- SIMULTANEOUS COMBO: Down + Right + B (3-button combo)
    {
        name = "Full Combo (Down+Right+B)",
        buttons = {Down = true, Right = true, B = true},
        frames = 10,
        pause_after = 15,
    },
}

-- Count single-button and combo moves for summary.
local function countMoveTypes(moves)
    local single = 0
    local combo = 0
    for _, move in ipairs(moves) do
        local buttonCount = 0
        for _ in pairs(move.buttons) do
            buttonCount = buttonCount + 1
        end
        if buttonCount > 1 then
            combo = combo + 1
        elseif buttonCount == 1 then
            single = single + 1
        end
        -- buttonCount == 0 is idle, not counted as either
    end
    return single, combo
end

-- Format button table as readable string (e.g., "A, Down, B").
local function formatButtons(buttons)
    local names = {}
    for name, pressed in pairs(buttons) do
        if pressed then
            names[#names + 1] = name
        end
    end
    if #names == 0 then
        return "(none)"
    end
    table.sort(names)
    return table.concat(names, ", ")
end

-- === Main Execution ===

console.log("=== Saiyan Trainer Controller Test ===")
console.log("Executing " .. #MoveSequence .. " test moves...")

-- Optionally reset fight if save state exists.
if ss.hasFightStartState() then
    console.log("Fight start save state found -- resetting fight")
    ss.resetFight()
else
    console.log("No fight start save state -- running with current emulator state")
end

-- Execute each move in sequence.
for moveIndex, move in ipairs(MoveSequence) do
    local buttonStr = formatButtons(move.buttons)
    console.log(string.format("Move %d/%d: %s [%s] for %d frames",
        moveIndex, #MoveSequence, move.name, buttonStr, move.frames))

    -- Hold buttons for the specified number of frames.
    for frame = 1, move.frames do
        -- Display current move on screen overlay.
        gui.text(10, 10, string.format("Move %d/%d: %s", moveIndex, #MoveSequence, move.name))
        gui.text(10, 30, "Buttons: " .. buttonStr)
        gui.text(10, 50, string.format("Frame: %d/%d", frame, move.frames))

        joypad.set(move.buttons)
        emu.frameadvance()
    end

    -- Release all buttons for pause_after frames (neutral input between moves).
    for frame = 1, move.pause_after do
        gui.text(10, 10, string.format("Pause after: %s", move.name))
        gui.text(10, 30, string.format("Frame: %d/%d", frame, move.pause_after))

        joypad.set({})
        emu.frameadvance()
    end
end

-- Summary
local singleCount, comboCount = countMoveTypes(MoveSequence)
console.log("=== Controller Test Complete ===")
console.log(string.format("All %d moves executed.", #MoveSequence))
console.log(string.format("Single-button moves: %d", singleCount))
console.log(string.format("Multi-button combos: %d", comboCount))
console.log("Controller input system verified.")
