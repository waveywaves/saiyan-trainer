-- inputs.lua
-- Converts game state from GBA memory into the NEAT input vector.
-- Reads game state via memory_map.lua and normalizes values.
--
-- Usage (mGBA):
--   local inputs = dofile("lua/game/inputs.lua")
--   local vec = inputs.getGameInputs()

local Inputs = {}

-- Constants for normalization (based on old VBA code + address analysis)
local MAX_HEALTH = 255     -- u8 health byte (0-255)
local MAX_KI = 25600       -- CodeBreaker sets 0x6400 = 25600 for 100%
local MAX_DIST = 630       -- old VBA code normalizes distances to 630
local MAX_TIMER = 99
local DIR_MAX = 32         -- polar direction: 32 discrete units = full circle

-- Number of game state inputs (not counting bias)
Inputs.NUM_INPUTS = 8

-- Input labels for visualization
local INPUT_LABELS = {
    "P1HP", "P2HP", "P1Ki", "P2Ki",
    "DistX", "DistY", "Dir", "RoundState",
}

--- Get the normalized game input vector from memory.
-- Reads game state via MemoryMap and normalizes to [0,1].
-- Appends a bias value of 1.0 as the last element.
-- @return table  Array of 9 numbers (8 game state + 1 bias).
function Inputs.getGameInputs()
    local mm = dofile("lua/memory_map.lua")
    local state = mm.readAll()

    local inputs = {}

    -- P1 health normalized to [0, 1]
    inputs[1] = (state.p1_health or 0) / MAX_HEALTH

    -- P2 health normalized to [0, 1]
    inputs[2] = (state.p2_health or 0) / MAX_HEALTH

    -- P1 Ki normalized to [0, 1]
    inputs[3] = (state.p1_ki or 0) / MAX_KI

    -- P2 Ki normalized to [0, 1]
    inputs[4] = (state.p2_ki or 0) / MAX_KI

    -- X distance normalized to [0, 1]
    inputs[5] = (state.dist_x or 0) / MAX_DIST

    -- Y distance normalized to [0, 1]
    inputs[6] = (state.dist_y or 0) / MAX_DIST

    -- Direction normalized to [0, 1]
    inputs[7] = (state.polar_dir or 0) / DIR_MAX

    -- Round state normalized to [0, 1]
    inputs[8] = (state.round_state or 0) / 255

    -- Bias node (always 1.0)
    inputs[9] = 1.0

    return inputs
end

--- Get the input labels for visualization reference.
-- @return table  Array of label strings.
function Inputs.getInputLabels()
    return INPUT_LABELS
end

return Inputs
