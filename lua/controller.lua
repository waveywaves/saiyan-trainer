-- controller.lua
-- Translates NEAT neural network outputs to GBA button presses for BizHawk.
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

-- Number of output neurons the NEAT network needs (one per button).
local NUM_OUTPUTS = #ButtonNames

--- Convert NEAT output array to a controller button table.
-- Each output neuron corresponds to one button. Positive values mean pressed.
-- Naturally supports simultaneous combos: if multiple outputs are positive,
-- multiple buttons are pressed on the same frame.
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

--- Apply NEAT outputs directly to the emulator joypad.
-- Convenience wrapper: converts outputs then calls joypad.set().
--
-- @param outputs  Array of numbers (length == NUM_OUTPUTS).
function Controller.applyController(outputs)
    local controller = Controller.outputsToController(outputs)
    joypad.set(controller)
end

--- Release all buttons (neutral input).
-- Used between evaluations to ensure no buttons are held.
function Controller.clearController()
    joypad.set({})
end

--- Get the ordered list of button names.
-- @return table  Array of button name strings.
function Controller.getButtonNames()
    return ButtonNames
end

--- Get the number of output neurons needed for NEAT configuration.
-- @return integer  Number of buttons (8).
function Controller.getNumOutputs()
    return NUM_OUTPUTS
end

return Controller
