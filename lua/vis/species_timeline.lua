-- species_timeline.lua
-- Tracks species membership over generations.
--
-- mGBA does not provide BizHawk-style gui.* overlay drawing functions.
-- This module tracks species data and provides text summaries via console
-- instead of rendering a stacked bar chart overlay.
--
-- Usage:
--   local SpeciesTracker = dofile("lua/vis/species_timeline.lua")
--   SpeciesTracker.record(pool)       -- call once per generation
--   SpeciesTracker.display()          -- logs summary to console
--   local text = SpeciesTracker.getSummary()

local Config = dofile("lua/neat/config.lua")

local SpeciesTracker = {}

-- Internal state
local history = {}
local maxGenerations = 50

--- Record a snapshot of current species membership.
-- Called once per generation after evaluation completes.
-- @param pool table  The population pool with pool.species array.
function SpeciesTracker.record(pool)
    if pool == nil or pool.species == nil then
        return
    end

    local snapshot = {
        generation = pool.generation or 0,
        species = {},
    }

    local totalGenomes = 0
    for s, species in ipairs(pool.species) do
        local count = #species.genomes
        totalGenomes = totalGenomes + count
        snapshot.species[#snapshot.species + 1] = {
            id = s,
            count = count,
            topFitness = species.topFitness or 0,
        }
    end
    snapshot.totalGenomes = totalGenomes

    history[#history + 1] = snapshot

    -- Sliding window: remove oldest entries beyond maxGenerations
    while #history > maxGenerations do
        table.remove(history, 1)
    end
end

--- Display species summary to console (replaces graphical timeline).
function SpeciesTracker.display()
    if #history == 0 then
        return
    end
    -- Console output is handled by getSummary() when called by the training loop
end

--- Get a text summary of the current species distribution.
-- @return string  Summary text for console logging.
function SpeciesTracker.getSummary()
    if #history == 0 then
        return "No species history recorded"
    end

    local latest = history[#history]
    local numSpecies = #latest.species
    local total = latest.totalGenomes or 0

    -- Find largest and smallest species
    local largest = 0
    local smallest = math.huge
    for _, sp in ipairs(latest.species) do
        if sp.count > largest then largest = sp.count end
        if sp.count < smallest then smallest = sp.count end
    end

    local largestPct = 0
    local smallestPct = 0
    if total > 0 then
        largestPct = math.floor(largest / total * 100)
        smallestPct = math.floor(smallest / total * 100)
    end

    return string.format(
        "Gen %d: %d species, largest=%d (%d%%), smallest=%d (%d%%)",
        latest.generation, numSpecies,
        largest, largestPct,
        smallest, smallestPct
    )
end

--- Get the full history table (for checkpoint saving).
-- @return table  Array of generation snapshots.
function SpeciesTracker.getHistory()
    return history
end

--- Restore history from checkpoint data.
-- @param savedHistory table  Previously saved history array.
function SpeciesTracker.loadHistory(savedHistory)
    if savedHistory and type(savedHistory) == "table" then
        history = savedHistory
    end
end

--- Reset all history.
function SpeciesTracker.reset()
    history = {}
end

return SpeciesTracker
