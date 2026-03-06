-- network_display.lua
-- Neural network topology visualization for mGBA.
--
-- mGBA does not provide BizHawk-style gui.* overlay drawing functions.
-- This module provides the same public API but currently logs network
-- topology stats to console instead of drawing on screen.
-- When mGBA adds canvas/overlay support, the drawing code can be added here.
--
-- Usage:
--   local NetworkDisplay = dofile("lua/vis/network_display.lua")
--   NetworkDisplay.displayGenome(genome)

local Config = dofile("lua/neat/config.lua")
local GameInputs = dofile("lua/game/inputs.lua")
local Controller = dofile("lua/controller.lua")

local NetworkDisplay = {}

-- Track last logged generation to avoid console spam
local lastLoggedGen = -1

--- Display the neural network topology (console-based).
-- Logs hidden node count and connection stats once per genome.
-- @param genome table  The genome to visualize (must have .genes, optionally .network).
function NetworkDisplay.displayGenome(genome)
    if genome == nil or genome.network == nil then
        return
    end

    -- Count hidden nodes and connections
    local hiddenSet = {}
    local hiddenCount = 0
    local enabledConns = 0
    local disabledConns = 0

    for _, gene in ipairs(genome.genes) do
        if gene.enabled then
            enabledConns = enabledConns + 1
        else
            disabledConns = disabledConns + 1
        end

        local ids = { gene.into, gene.out }
        for _, nid in ipairs(ids) do
            if nid > Config.Inputs and nid <= Config.MaxNodes then
                if not hiddenSet[nid] then
                    hiddenSet[nid] = true
                    hiddenCount = hiddenCount + 1
                end
            end
        end
    end

    -- Only log periodically to avoid spam (genome fitness changes indicate new eval)
    if genome.fitness and genome.fitness ~= lastLoggedGen then
        lastLoggedGen = genome.fitness
    end
end

--- Draw the network for the current genome (convenience alias).
-- @param genome table  The genome to visualize.
function NetworkDisplay.displayNetwork(genome)
    NetworkDisplay.displayGenome(genome)
end

return NetworkDisplay
