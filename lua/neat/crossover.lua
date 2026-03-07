-- crossover.lua
-- Crossover operator for NEAT.
-- Combines two parent genomes into a child genome by aligning genes
-- on innovation numbers.
--
-- Usage:
--   local Crossover = dofile("lua/neat/crossover.lua")
--   local child = Crossover.crossover(g1, g2, config)

local Crossover = {}

-- Lazy-load dependencies
local GenomeMod = nil

--- Set module dependencies.
-- @param genomeMod table  The genome module.
function Crossover.setDependencies(genomeMod)
    GenomeMod = genomeMod
end

--- Crossover two genomes to produce a child.
-- For matching innovation numbers: randomly pick gene from either parent.
-- For disjoint/excess genes: take from the fitter parent (g1 after swap).
-- @param g1     table  First parent genome.
-- @param g2     table  Second parent genome.
-- @param config table  The NEAT config table.
-- @return table  Child genome.
function Crossover.crossover(g1, g2, config)
    -- Ensure g1 is the fitter parent
    if g2.fitness > g1.fitness then
        g1, g2 = g2, g1
    end

    local child = GenomeMod.newGenome(config)

    -- Index g2 genes by innovation number for fast lookup
    local innovations2 = {}
    for _, gene in ipairs(g2.genes) do
        innovations2[gene.innovation] = gene
    end

    -- Build child genes
    for _, gene1 in ipairs(g1.genes) do
        local gene2 = innovations2[gene1.innovation]
        if gene2 and math.random(2) == 1 then
            -- Matching gene: randomly pick from either parent (regardless of enabled state)
            child.genes[#child.genes + 1] = GenomeMod.copyGene(gene2)
        else
            -- Disjoint/excess or randomly picked g1: take from fitter parent
            child.genes[#child.genes + 1] = GenomeMod.copyGene(gene1)
        end
    end

    child.maxneuron = math.max(g1.maxneuron, g2.maxneuron)

    -- Inherit mutation rates from fitter parent
    for key, value in pairs(g1.mutationRates) do
        child.mutationRates[key] = value
    end

    return child
end

return Crossover
