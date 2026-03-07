-- pool.lua
-- Population pool management for NEAT.
-- Handles population initialization, global ranking, breeding,
-- and generation advancement with elitism.
--
-- Usage:
--   local Pool = dofile("lua/neat/pool.lua")
--   local pool = Pool.newPool(config, innovation)

local Pool = {}

-- Lazy-load dependencies
local GenomeMod = nil
local SpeciesMod = nil
local CrossoverMod = nil
local MutationMod = nil
local NetworkMod = nil

--- Set module dependencies.
function Pool.setDependencies(genomeMod, speciesMod, crossoverMod, mutationMod, networkMod)
    GenomeMod = genomeMod
    SpeciesMod = speciesMod
    CrossoverMod = crossoverMod
    MutationMod = mutationMod
    NetworkMod = networkMod
end

--- Create and initialize a new population pool.
-- Creates PopulationSize basic genomes and speciates them.
-- @param config     table  The NEAT config table.
-- @param innovation table  The innovation tracker.
-- @return table  The initialized pool.
function Pool.newPool(config, innovation)
    math.randomseed(os.time())

    local pool = {
        species = {},
        generation = 0,
        maxFitness = -math.huge,
    }

    for _ = 1, config.Population do
        local genome = GenomeMod.basicGenome(config, innovation)
        SpeciesMod.addToSpecies(genome, pool, config)
    end

    return pool
end

--- Assign global rank to all genomes across all species.
-- Flatten all genomes, sort by fitness ascending, assign rank 1..N.
-- Rank N = highest fitness.
-- @param pool table  The population pool.
function Pool.rankGlobally(pool)
    local allGenomes = {}
    for _, species in ipairs(pool.species) do
        for _, genome in ipairs(species.genomes) do
            allGenomes[#allGenomes + 1] = genome
        end
    end

    table.sort(allGenomes, function(a, b)
        return a.fitness < b.fitness
    end)

    for i, genome in ipairs(allGenomes) do
        genome.globalRank = i
    end
end

--- Sum of all species average fitnesses.
-- Used to compute offspring shares.
-- @param pool table  The population pool.
-- @return number  Total average fitness.
function Pool.totalAverageFitness(pool)
    local total = 0
    for _, species in ipairs(pool.species) do
        total = total + species.averageFitness
    end
    return total
end

--- Breed a child from a species.
-- With CrossoverChance probability, crossover two random genomes.
-- Otherwise, copy a random genome. Then mutate the child.
-- @param species    table  The species to breed from.
-- @param pool       table  The population pool (unused but kept for API consistency).
-- @param config     table  The NEAT config table.
-- @param innovation table  The innovation tracker.
-- @return table  The child genome.
function Pool.breedChild(species, pool, config, innovation)
    local child

    if math.random() < config.CrossoverChance and #species.genomes >= 2 then
        local g1 = species.genomes[math.random(#species.genomes)]
        local g2 = species.genomes[math.random(#species.genomes)]
        child = CrossoverMod.crossover(g1, g2, config)
    else
        local g = species.genomes[math.random(#species.genomes)]
        child = GenomeMod.copyGenome(g)
    end

    MutationMod.mutate(child, config, innovation)

    return child
end

--- Count total genomes across all species.
-- @param pool table  The population pool.
-- @return integer  Total genome count.
local function countGenomes(pool)
    local count = 0
    for _, species in ipairs(pool.species) do
        count = count + #species.genomes
    end
    return count
end

--- Advance to the next generation.
-- 1. Cull species (remove bottom half)
-- 2. Remove stale species
-- 3. Rank globally and calculate average fitness
-- 4. Remove weak species
-- 5. Calculate offspring shares
-- 6. Breed children
-- 7. Preserve elites (best genome of each species)
-- 8. Clear old species and re-speciate
-- 9. Increment generation
-- 10. Adjust compatibility threshold
--
-- @param pool       table  The population pool.
-- @param config     table  The NEAT config table.
-- @param innovation table  The innovation tracker.
function Pool.newGeneration(pool, config, innovation)
    -- Reset per-generation innovation tracking so identical structural
    -- mutations within this generation receive the same innovation number
    innovation.resetGeneration()

    -- Cull bottom half of each species
    SpeciesMod.cullSpecies(pool, false)

    -- Remove stale species
    SpeciesMod.removeStaleSpecies(pool, config)

    -- Rank globally and compute average fitness
    Pool.rankGlobally(pool)
    for _, species in ipairs(pool.species) do
        SpeciesMod.calculateAverageFitness(species)
    end

    -- Remove weak species
    SpeciesMod.removeWeakSpecies(pool)

    -- Calculate offspring shares
    local totalAvg = Pool.totalAverageFitness(pool)
    local children = {}

    -- Preserve elites: best genome from each surviving species
    for _, species in ipairs(pool.species) do
        -- Species are already sorted by fitness descending from cullSpecies
        if #species.genomes > 0 then
            children[#children + 1] = GenomeMod.copyGenome(species.genomes[1])
        end
    end

    -- Breed children to fill up to Population size
    for _, species in ipairs(pool.species) do
        local breed = 0
        if totalAvg > 0 then
            breed = math.floor(species.averageFitness / totalAvg * config.Population) - 1
        end
        for _ = 1, breed do
            children[#children + 1] = Pool.breedChild(species, pool, config, innovation)
        end
    end

    -- If we need more children to reach Population size, breed from random species
    while #children < config.Population do
        if #pool.species == 0 then
            break
        end
        local species = pool.species[math.random(#pool.species)]
        if #species.genomes > 0 then
            children[#children + 1] = Pool.breedChild(species, pool, config, innovation)
        end
    end

    -- Clear old species and re-speciate with new children
    pool.species = {}
    for _, child in ipairs(children) do
        SpeciesMod.addToSpecies(child, pool, config)
    end

    pool.generation = pool.generation + 1

    -- Adjust compatibility threshold
    SpeciesMod.adjustCompatibilityThreshold(pool, config)
end

return Pool
