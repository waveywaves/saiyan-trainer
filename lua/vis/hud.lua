-- hud.lua
-- Training statistics heads-up display overlay for BizHawk.
-- Shows generation, species count, genome progress, fitness,
-- and a visual fitness bar.
--
-- Usage:
--   local HUD = dofile("lua/vis/hud.lua")
--   HUD.displayHUD(pool, currentGenome, fps)
--   HUD.displayFitnessBar(fitness, maxFitness)

local HUD = {}

-- Layout constants (positioned in top-right corner, outside network display area)
local HUD_X = 140
local HUD_Y = 2
local HUD_WIDTH = 96
local LINE_HEIGHT = 10
local FONT_SIZE = 8

-- Colors
local BG_COLOR = 0x80000000
local BG_BORDER = 0x80444444
local TEXT_COLOR = 0xFFFFFFFF
local TEXT_DIM = 0xFFAAAAAA
local FITNESS_BAR_BG = 0xFF333333
local FITNESS_BAR_FG = 0xFF00CC00
local FITNESS_BAR_MAX = 0xFF00FF00

--- Display the training statistics HUD overlay.
-- Renders generation, species count, genome progress, fitness, and max fitness.
-- @param pool          table   The population pool.
-- @param currentGenome table   The genome currently being evaluated (optional).
-- @param fps           number  Current frames per second (optional).
function HUD.displayHUD(pool, currentGenome, fps)
    if pool == nil then
        return
    end

    local lines = {}

    -- Generation
    lines[#lines + 1] = { text = "Gen: " .. (pool.generation or 0), color = TEXT_COLOR }

    -- Species count
    local speciesCount = 0
    if pool.species then
        speciesCount = #pool.species
    end
    lines[#lines + 1] = { text = "Species: " .. speciesCount, color = TEXT_COLOR }

    -- Current genome progress
    local currentIdx = 0
    local totalGenomes = 0
    if pool.species then
        for s = 1, #pool.species do
            local species = pool.species[s]
            for g = 1, #species.genomes do
                totalGenomes = totalGenomes + 1
                if species.genomes[g] == currentGenome then
                    currentIdx = totalGenomes
                end
            end
        end
    end
    if currentIdx > 0 then
        lines[#lines + 1] = { text = "Genome: " .. currentIdx .. "/" .. totalGenomes, color = TEXT_COLOR }
    else
        lines[#lines + 1] = { text = "Genomes: " .. totalGenomes, color = TEXT_DIM }
    end

    -- Current fitness
    local fitness = 0
    if currentGenome and currentGenome.fitness then
        fitness = currentGenome.fitness
    end
    lines[#lines + 1] = { text = "Fitness: " .. math.floor(fitness), color = TEXT_COLOR }

    -- Max fitness
    local maxFitness = pool.maxFitness or 0
    lines[#lines + 1] = { text = "Max: " .. math.floor(maxFitness), color = FITNESS_BAR_MAX }

    -- Staleness of current species
    local staleness = 0
    if pool.species then
        for _, species in ipairs(pool.species) do
            for _, genome in ipairs(species.genomes) do
                if genome == currentGenome then
                    staleness = species.staleness or 0
                    break
                end
            end
            if staleness > 0 then break end
        end
    end
    lines[#lines + 1] = { text = "Stale: " .. staleness, color = TEXT_DIM }

    -- FPS (optional)
    if fps and fps > 0 then
        lines[#lines + 1] = { text = "FPS: " .. math.floor(fps), color = TEXT_DIM }
    end

    -- Calculate HUD height
    local hudHeight = #lines * LINE_HEIGHT + 6

    -- Draw background
    gui.drawBox(HUD_X, HUD_Y, HUD_X + HUD_WIDTH, HUD_Y + hudHeight, BG_BORDER, BG_COLOR)

    -- Draw text lines
    for i, line in ipairs(lines) do
        gui.drawText(
            HUD_X + 4, HUD_Y + 2 + (i - 1) * LINE_HEIGHT,
            line.text, line.color, FONT_SIZE
        )
    end
end

--- Display a horizontal fitness bar showing current fitness relative to max.
-- Positioned directly below the HUD text area.
-- @param fitness    number  Current fitness value.
-- @param maxFitness number  Maximum fitness achieved (for scale).
function HUD.displayFitnessBar(fitness, maxFitness)
    if maxFitness == nil or maxFitness <= 0 then
        return
    end

    local barX = HUD_X + 4
    local barY = HUD_Y + 78   -- Below HUD text (approximately 7 lines * 10px + padding)
    local barWidth = HUD_WIDTH - 8
    local barHeight = 6

    -- Background bar
    gui.drawBox(barX, barY, barX + barWidth, barY + barHeight, 0xFF555555, FITNESS_BAR_BG)

    -- Fill bar proportional to fitness/maxFitness
    local ratio = math.max(0, math.min(1, fitness / maxFitness))
    local fillWidth = math.floor(ratio * barWidth)
    if fillWidth > 0 then
        gui.drawBox(barX, barY, barX + fillWidth, barY + barHeight, FITNESS_BAR_FG, FITNESS_BAR_FG)
    end

    -- Label
    local pct = math.floor(ratio * 100)
    gui.drawText(barX + barWidth + 3, barY - 1, pct .. "%", TEXT_COLOR, 7)
end

return HUD
