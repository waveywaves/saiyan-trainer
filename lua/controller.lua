-- controller.lua
-- Translates NEAT neural network outputs to GBA button presses for mGBA.
-- Supports simultaneous button combinations for fighting game combos.
--
-- Usage:
--   local controller = dofile("lua/controller.lua")
--   local outputs = {0.8, -0.2, 0.1, -0.5, -0.1, 0.9, -0.3, 0.7}
--   controller.applyController(outputs)

local Controller = {}

-- GBA buttons used for fighting game control.
-- Start and Select are excluded from NEAT control (not useful for fighting).
-- Order determines which NEAT output neuron maps to which button.
local ButtonNames = {
    "A",      -- Attack button 1 (punch)
    "B",      -- Attack button 2 (kick)
    "L",      -- Shoulder left (block/guard)
    "R",      -- Shoulder right (ki blast)
    "Up",     -- D-pad up (jump/fly)
    "Down",   -- D-pad down (crouch/dodge)
    "Left",   -- D-pad left (move left)
    "Right",  -- D-pad right (move right)
}

-- mGBA C.GBA_KEY constants mapping (button name -> bitmask value)
-- These map to the GBA key register bits.
local KEY_MAP = {
    A     = 0x01,
    B     = 0x02,
    Select= 0x04,
    Start = 0x08,
    Right = 0x10,
    Left  = 0x20,
    Up    = 0x40,
    Down  = 0x80,
    R     = 0x100,
    L     = 0x200,
}

-- Number of output neurons the NEAT network needs (one per button).
local NUM_OUTPUTS = #ButtonNames

--- Convert NEAT output array to a controller button table.
-- Each output neuron corresponds to one button. Positive values mean pressed.
-- Returns a boolean table for logging/analysis compatibility.
--
-- @param outputs  Array of numbers (length == NUM_OUTPUTS), from NEAT output neurons.
-- @return table   Button names mapped to true/false (e.g., {A=true, B=false, ...}).
function Controller.outputsToController(outputs)
    local controller = {}
    for i = 1, #ButtonNames do
        if outputs[i] > 0 then
            controller[ButtonNames[i]] = true
        else
            controller[ButtonNames[i]] = false
        end
    end
    return controller
end

--- Convert a boolean button table to an mGBA key bitmask.
-- @param buttons table  Button names mapped to true/false.
-- @return integer  Bitmask for emu:setKeys().
function Controller.buttonsToBitmask(buttons)
    local mask = 0
    for name, pressed in pairs(buttons) do
        if pressed and KEY_MAP[name] then
            mask = mask | KEY_MAP[name]
        end
    end
    return mask
end

--- Apply NEAT outputs directly to the emulator joypad.
-- Converts outputs to button table, then to bitmask, then calls emu:setKeys().
--
-- @param outputs  Array of numbers (length == NUM_OUTPUTS).
function Controller.applyController(outputs)
    local buttons = Controller.outputsToController(outputs)
    local mask = Controller.buttonsToBitmask(buttons)
    emu:setKeys(mask)
end

--- Release all buttons (neutral input).
-- Used between evaluations to ensure no buttons are held.
function Controller.clearController()
    emu:setKeys(0)
end

--- Get the ordered list of button names.
-- @return table  Array of button name strings.
function Controller.getButtonNames()
    local copy = {}
    for i, name in ipairs(ButtonNames) do
        copy[i] = name
    end
    return copy
end

--- Get the number of output neurons needed for NEAT configuration.
-- @return integer  Number of buttons (8).
function Controller.getNumOutputs()
    return NUM_OUTPUTS
end

return Controller
