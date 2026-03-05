-- genome.lua
-- Genome and Gene data structures for NEAT.
-- A Genome represents a neural network topology as a list of Genes (connections).
--
-- Usage:
--   local Genome = dofile("lua/neat/genome.lua")
--   local g = Genome.newGenome(config)

local Genome = {}

--- Create a new gene (connection between two neurons).
-- @return table  A gene with default values.
function Genome.newGene()
    return {
        into = 0,
        out = 0,
        weight = 0.0,
        enabled = true,
        innovation = 0,
    }
end

--- Shallow copy of a gene.
-- @param gene table  The gene to copy.
-- @return table  A new gene table with the same values.
function Genome.copyGene(gene)
    return {
        into = gene.into,
        out = gene.out,
        weight = gene.weight,
        enabled = gene.enabled,
        innovation = gene.innovation,
    }
end

--- Create a new genome with empty genes and default mutation rates.
-- @param config table  The NEAT config table.
-- @return table  A new genome.
function Genome.newGenome(config)
    return {
        genes = {},
        fitness = 0,
        maxneuron = 0,
        globalRank = 0,
        mutationRates = {
            connections = config.MutateConnectionsChance,
            link = config.LinkMutationChance,
            node = config.NodeMutationChance,
            bias = config.BiasMutationChance,
            step = config.StepSize,
            disable = config.DisableMutationChance,
            enable = config.EnableMutationChance,
        },
        network = nil,
    }
end

--- Deep copy a genome (genes and mutationRates, NOT network).
-- @param genome table  The genome to copy.
-- @return table  An independent deep copy.
function Genome.copyGenome(genome)
    local copy = {
        genes = {},
        fitness = genome.fitness,
        maxneuron = genome.maxneuron,
        globalRank = genome.globalRank,
        mutationRates = {},
        network = nil,
    }
    for _, gene in ipairs(genome.genes) do
        copy.genes[#copy.genes + 1] = Genome.copyGene(gene)
    end
    for k, v in pairs(genome.mutationRates) do
        copy.mutationRates[k] = v
    end
    return copy
end

--- Create a minimal genome with direct input-to-output connections.
-- This is the seed genome for population initialization.
-- @param config table       The NEAT config table.
-- @param innovation table   The innovation tracker module.
-- @return table  A basic genome with Inputs*Outputs random connections.
function Genome.basicGenome(config, innovation)
    local genome = Genome.newGenome(config)
    genome.maxneuron = config.Inputs

    for o = 1, config.Outputs do
        for i = 1, config.Inputs do
            local gene = Genome.newGene()
            gene.into = i
            gene.out = config.MaxNodes + o
            gene.weight = math.random() * 4 - 2
            gene.innovation = innovation.newInnovation()
            gene.enabled = true
            genome.genes[#genome.genes + 1] = gene
        end
    end

    return genome
end

return Genome
