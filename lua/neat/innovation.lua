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

--- Increment and return a new unique innovation number.
-- @return integer  The new innovation number.
function Innovation.newInnovation()
    Innovation.current = Innovation.current + 1
    return Innovation.current
end

--- Reset the innovation counter to a given value.
-- Used when loading from a checkpoint.
-- @param value integer  The value to set the counter to.
function Innovation.reset(value)
    Innovation.current = value or 0
end

--- Get the current innovation counter value.
-- @return integer  The current counter value.
function Innovation.getCurrent()
    return Innovation.current
end

return Innovation
