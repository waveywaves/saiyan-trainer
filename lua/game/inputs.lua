-- inputs.lua
-- Converts game state from GBA memory into the NEAT input vector.
-- Reads game state via memory_map.lua and normalizes values.
--
-- Usage (BizHawk):
--   local inputs = dofile("lua/game/inputs.lua")
--   local vec = inputs.getGameInputs()

local Inputs = {}

-- Constants for normalization (best guesses, may need tuning after Phase 1 RAM discovery)
local MAX_HEALTH = 1000
local MAX_KI = 100
local SCREEN_WIDTH = 240
local SCREEN_HEIGHT = 160
local MAX_TIMER = 99

-- Number of game state inputs (not counting bias)
Inputs.NUM_INPUTS = 10

-- Input labels for visualization
local INPUT_LABELS = {
    "P1HP", "P2HP", "P1Ki", "P2Ki",
    "DistX", "DistY",
    "P1Atk", "P2Atk",
    "RoundState", "Timer",
}

--- Get the normalized game input vector from memory.
-- Reads game state via MemoryMap and normalizes to [0,1] or [-1,1].
-- Appends a bias value of 1.0 as the 11th element.
-- @return table  Array of 11 numbers (10 game state + 1 bias).
function Inputs.getGameInputs()
    -- Load memory map module (BizHawk dofile)
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

    -- Signed distance X normalized to [-1, 1]
    local p1x = state.p1_x or 0
    local p2x = state.p2_x or 0
    inputs[5] = (p2x - p1x) / SCREEN_WIDTH

    -- Signed distance Y normalized to [-1, 1]
    local p1y = state.p1_y or 0
    local p2y = state.p2_y or 0
    inputs[6] = (p2y - p1y) / SCREEN_HEIGHT

    -- P1 attack state normalized to [0, 1]
    inputs[7] = (state.p1_state or 0) / 255

    -- P2 attack state normalized to [0, 1]
    inputs[8] = (state.p2_state or 0) / 255

    -- Round state normalized to [0, 1]
    inputs[9] = (state.round_state or 0) / 255

    -- Timer normalized to [0, 1]
    inputs[10] = (state.timer or 0) / MAX_TIMER

    -- Bias node (always 1.0)
    inputs[11] = 1.0

    return inputs
end

--- Get the input labels for visualization reference.
-- @return table  Array of label strings.
function Inputs.getInputLabels()
    return INPUT_LABELS
end

return Inputs
