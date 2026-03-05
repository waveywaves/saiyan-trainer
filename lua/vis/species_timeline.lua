-- species_timeline.lua
-- Tracks species membership over generations and renders a stacked bar chart
-- timeline visualization on the BizHawk screen.
--
-- Usage:
--   local SpeciesTracker = dofile("lua/vis/species_timeline.lua")
--   SpeciesTracker.record(pool)       -- call once per generation
--   SpeciesTracker.display()          -- call each frame to draw overlay
--   local text = SpeciesTracker.getSummary()

local Config = dofile("lua/neat/config.lua")

local SpeciesTracker = {}

-- Internal state
local history = {}
local maxGenerations = 50

-- Color palette: 16 distinct colors for species identification
local colorPalette = {
    0xFFFF0000,  -- red
    0xFF00FF00,  -- green
    0xFF0000FF,  -- blue
    0xFFFFFF00,  -- yellow
    0xFFFF00FF,  -- magenta
    0xFF00FFFF,  -- cyan
    0xFFFF8800,  -- orange
    0xFF88FF00,  -- lime
    0xFF0088FF,  -- sky blue
    0xFFFF0088,  -- pink
    0xFF88FF88,  -- light green
    0xFFFF8888,  -- light red
    0xFF8888FF,  -- light blue
    0xFFFFCC00,  -- gold
    0xFF00CC88,  -- teal
    0xFFCC00FF,  -- purple
}

-- Track species color assignments for consistency across generations
local speciesColors = {}
local nextColorIndex = 1

--- Assign a consistent color to a species index.
-- Species keep their color across generations for visual tracking.
-- @param speciesIdx number  The species index in the pool.
-- @return number  ARGB color value.
local function getSpeciesColor(speciesIdx)
    if not speciesColors[speciesIdx] then
        speciesColors[speciesIdx] = colorPalette[((nextColorIndex - 1) % #colorPalette) + 1]
        nextColorIndex = nextColorIndex + 1
    end
    return speciesColors[speciesIdx]
end

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
            color = getSpeciesColor(s),
        }
    end
    snapshot.totalGenomes = totalGenomes

    history[#history + 1] = snapshot

    -- Sliding window: remove oldest entries beyond maxGenerations
    while #history > maxGenerations do
        table.remove(history, 1)
    end
end

-- Display layout constants (right side of screen, below or beside network)
local TIMELINE_X = 140
local TIMELINE_Y = 82
local TIMELINE_WIDTH = 96
local TIMELINE_HEIGHT = 74

local LABEL_COLOR = 0xFFCCCCCC
local BG_COLOR = 0x80000000
local BG_BORDER = 0x80444444
local AXIS_COLOR = 0xFF666666

--- Render the species timeline as a stacked bar chart on the BizHawk screen.
-- Each column represents one generation. Each segment in the column represents
-- one species, with height proportional to genome count and color from palette.
function SpeciesTracker.display()
    if #history == 0 then
        return
    end

    -- Draw background
    gui.drawBox(TIMELINE_X, TIMELINE_Y, TIMELINE_X + TIMELINE_WIDTH, TIMELINE_Y + TIMELINE_HEIGHT, BG_BORDER, BG_COLOR)

    -- Title label
    gui.drawText(TIMELINE_X + 2, TIMELINE_Y + 1, "Species", LABEL_COLOR, 7)

    -- Chart area (inside padding)
    local chartX = TIMELINE_X + 2
    local chartY = TIMELINE_Y + 10
    local chartWidth = TIMELINE_WIDTH - 4
    local chartHeight = TIMELINE_HEIGHT - 18

    -- Column width based on number of generations to display
    local numCols = math.min(#history, maxGenerations)
    local colWidth = chartWidth / numCols

    -- Find max total genomes for consistent scaling
    local maxTotal = 1
    for _, snap in ipairs(history) do
        if snap.totalGenomes and snap.totalGenomes > maxTotal then
            maxTotal = snap.totalGenomes
        end
    end

    -- Draw each generation column as stacked segments
    for i, snap in ipairs(history) do
        local x = chartX + (i - 1) * colWidth
        local total = snap.totalGenomes or 1
        local yOffset = 0

        for _, sp in ipairs(snap.species) do
            -- Height proportional to genome count relative to max population
            local segHeight = (sp.count / maxTotal) * chartHeight
            local y1 = chartY + chartHeight - yOffset - segHeight
            local y2 = chartY + chartHeight - yOffset

            if segHeight >= 1 then
                gui.drawBox(
                    math.floor(x), math.floor(y1),
                    math.floor(x + colWidth), math.floor(y2),
                    sp.color, sp.color
                )
            end

            yOffset = yOffset + segHeight
        end
    end

    -- Draw generation numbers along the bottom (every 10th generation)
    for i, snap in ipairs(history) do
        if snap.generation % 10 == 0 then
            local x = chartX + (i - 1) * colWidth
            gui.drawText(
                math.floor(x), chartY + chartHeight + 1,
                tostring(snap.generation), AXIS_COLOR, 7
            )
        end
    end
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

        -- Restore color assignments from loaded history
        speciesColors = {}
        nextColorIndex = 1
        for _, snap in ipairs(history) do
            for _, sp in ipairs(snap.species) do
                if not speciesColors[sp.id] then
                    speciesColors[sp.id] = sp.color
                    nextColorIndex = nextColorIndex + 1
                end
            end
        end
    end
end

--- Reset all history and color assignments.
function SpeciesTracker.reset()
    history = {}
    speciesColors = {}
    nextColorIndex = 1
end

return SpeciesTracker
