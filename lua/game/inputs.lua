-- inputs.lua
-- Converts game state from GBA memory into the NEAT input vector.
-- Reads game state via memory_map.lua and normalizes values.
--
-- Usage (mGBA):
--   local inputs = dofile("lua/game/inputs.lua")
--   local vec = inputs.getGameInputs()

local Inputs = {}

-- Load memory map once at module level (not per-frame)
local mm = dofile("lua/memory_map.lua")

-- Constants for normalization
-- Only using verified/working addresses to avoid feeding noise to NEAT.
local MAX_HEALTH = 255     -- u8 health byte (0-255)
local MAX_KI_INT = 100     -- p1_ki_int is 0-100 (integer percentage)
local MAX_POWER = 3        -- power level 0=base, 3=max

-- Number of game state inputs (not counting bias)
-- Removed: P2 Ki (unverified), dist_x/dist_y/polar_dir (unverified),
--          round_state (0=instant win cheat trigger, useless as input)
Inputs.NUM_INPUTS = 4

-- Input labels for visualization
local INPUT_LABELS = {
    "P1HP", "P2HP", "P1Ki", "P1Pwr",
}

--- Get the normalized game input vector from memory.
-- Reads only verified/working game state and normalizes to [0,1].
-- Appends a bias value of 1.0 as the last element.
-- @return table  Array of 5 numbers (4 game state + 1 bias).
function Inputs.getGameInputs()
    local state = mm.readAll()

    local inputs = {}

    -- P1 health normalized to [0, 1] (verified)
    inputs[1] = (state.p1_health or 0) / MAX_HEALTH

    -- P2 health normalized to [0, 1] (working from old VBA code)
    inputs[2] = (state.p2_health or 0) / MAX_HEALTH

    -- P1 Ki integer percentage normalized to [0, 1] (verified)
    inputs[3] = (state.p1_ki_int or 0) / MAX_KI_INT

    -- P1 power level normalized to [0, 1] (verified)
    inputs[4] = (state.p1_power_level or 0) / MAX_POWER

    -- Bias node (always 1.0)
    inputs[5] = 1.0

    return inputs
end

--- Get the input labels for visualization reference.
-- @return table  Array of label strings.
function Inputs.getInputLabels()
    return INPUT_LABELS
end

return Inputs
