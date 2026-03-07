-- innovation.lua
-- Global innovation number tracker for NEAT.
-- Each new structural mutation (new connection or new node) gets a unique
-- innovation number. This enables crossover to align genes correctly.
--
-- Usage:
--   local Innovation = dofile("lua/neat/innovation.lua")
--   local n = Innovation.newInnovation()

local Innovation = {}

-- Current innovation counter (starts at 0)
Innovation.current = 0

-- Per-generation lookup table: "from_to" -> innovation number.
-- Ensures identical structural mutations within the same generation
-- receive the same innovation number, which is required for proper
-- crossover alignment in NEAT.
Innovation.generationInnovations = {}

--- Increment and return a new unique innovation number.
-- @return integer  The new innovation number.
function Innovation.newInnovation()
    Innovation.current = Innovation.current + 1
    return Innovation.current
end

--- Get or create an innovation number for a structural mutation.
-- If the same from->to connection was already mutated this generation,
-- return the existing innovation number. Otherwise allocate a new one.
-- @param from integer  The source neuron ID.
-- @param to   integer  The destination neuron ID.
-- @return integer  The innovation number for this structural change.
function Innovation.getOrCreate(from, to)
    local key = from .. "_" .. to
    if Innovation.generationInnovations[key] then
        return Innovation.generationInnovations[key]
    end
    local n = Innovation.newInnovation()
    Innovation.generationInnovations[key] = n
    return n
end

--- Clear the per-generation innovation lookup table.
-- Must be called at the start of each new generation so that
-- innovation tracking is scoped to one generation at a time.
function Innovation.resetGeneration()
    Innovation.generationInnovations = {}
end

--- Reset the innovation counter to a given value.
-- Used when loading from a checkpoint.
-- @param value integer  The value to set the counter to.
function Innovation.reset(value)
    Innovation.current = value or 0
    Innovation.generationInnovations = {}
end

--- Get the current innovation counter value.
-- @return integer  The current counter value.
function Innovation.getCurrent()
    return Innovation.current
end

return Innovation
