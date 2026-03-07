-- species.lua
-- Species management for NEAT.
-- Handles compatibility distance calculation, speciation, fitness sharing,
-- stagnation detection, and species culling.
--
-- Usage:
--   local Species = dofile("lua/neat/species.lua")
--   local same = Species.sameSpecies(genome1, genome2, config)

local Species = {}

--- Create a new species with an empty genomes list.
-- @return table  A new species.
function Species.newSpecies()
    return {
        genomes = {},
        topFitness = -math.huge,
        staleness = 0,
        averageFitness = 0,
    }
end

--- Count disjoint genes between two gene lists, normalized by max genome size.
-- @param genes1 table  Array of genes from genome 1.
-- @param genes2 table  Array of genes from genome 2.
-- @return number  Normalized disjoint gene count.
function Species.disjoint(genes1, genes2)
    local i1 = {}
    for _, gene in ipairs(genes1) do
        i1[gene.innovation] = true
    end
    local i2 = {}
    for _, gene in ipairs(genes2) do
        i2[gene.innovation] = true
    end

    local disjointGenes = 0
    for _, gene in ipairs(genes1) do
        if not i2[gene.innovation] then
            disjointGenes = disjointGenes + 1
        end
    end
    for _, gene in ipairs(genes2) do
        if not i1[gene.innovation] then
            disjointGenes = disjointGenes + 1
        end
    end

    local n = math.max(#genes1, #genes2)
    if n == 0 then
        return 0
    end
    return disjointGenes / n
end

--- Average weight difference of matching genes (same innovation number).
-- @param genes1 table  Array of genes from genome 1.
-- @param genes2 table  Array of genes from genome 2.
-- @return number  Average absolute weight difference.
function Species.weights(genes1, genes2)
    local i2 = {}
    for _, gene in ipairs(genes2) do
        i2[gene.innovation] = gene
    end

    local sum = 0
    local coincident = 0
    for _, gene in ipairs(genes1) do
        if i2[gene.innovation] then
            sum = sum + math.abs(gene.weight - i2[gene.innovation].weight)
            coincident = coincident + 1
        end
    end

    if coincident == 0 then
        return 0
    end
    return sum / coincident
end

--- Check if two genomes belong to the same species.
-- Uses compatibility distance: DeltaDisjoint * disjoint + DeltaWeights * weights < DeltaThreshold
-- @param genome1 table  First genome.
-- @param genome2 table  Second genome.
-- @param config  table  The NEAT config table.
-- @return boolean  True if genomes are compatible (same species).
function Species.sameSpecies(genome1, genome2, config)
    local dd = config.DeltaDisjoint * Species.disjoint(genome1.genes, genome2.genes)
    local dw = config.DeltaWeights * Species.weights(genome1.genes, genome2.genes)
    return dd + dw < config.DeltaThreshold
end

--- Add a genome to an existing compatible species, or create a new one.
-- @param genome table  The genome to add.
-- @param pool   table  The population pool.
-- @param config table  The NEAT config table.
function Species.addToSpecies(genome, pool, config)
    for _, species in ipairs(pool.species) do
        if #species.genomes > 0 and Species.sameSpecies(genome, species.genomes[1], config) then
            species.genomes[#species.genomes + 1] = genome
            return
        end
    end

    -- No compatible species found; create a new one
    local newSp = Species.newSpecies()
    newSp.genomes[1] = genome
    pool.species[#pool.species + 1] = newSp
end

--- Calculate the average fitness of a species (fitness sharing).
-- @param species table  The species.
function Species.calculateAverageFitness(species)
    local total = 0
    for _, genome in ipairs(species.genomes) do
        total = total + genome.globalRank
    end
    if #species.genomes > 0 then
        species.averageFitness = total / #species.genomes
    else
        species.averageFitness = 0
    end
end

--- Remove bottom half of each species (or all but best if cutToOne).
-- Keeps the top performers.
-- @param pool      table    The population pool.
-- @param cutToOne  boolean  If true, keep only the best genome per species.
function Species.cullSpecies(pool, cutToOne)
    for _, species in ipairs(pool.species) do
        -- Sort by fitness descending
        table.sort(species.genomes, function(a, b)
            return a.fitness > b.fitness
        end)

        local remaining
        if cutToOne then
            remaining = 1
        else
            remaining = math.ceil(#species.genomes / 2)
        end

        while #species.genomes > remaining do
            table.remove(species.genomes)
        end
    end
end

--- Remove species that haven't improved in StaleSpecies generations.
-- Never removes the species containing the global best genome.
-- @param pool   table  The population pool.
-- @param config table  The NEAT config table.
function Species.removeStaleSpecies(pool, config)
    local survived = {}

    -- Find global top fitness across all species
    local globalTopFitness = 0
    for _, species in ipairs(pool.species) do
        -- Sort to find best genome
        table.sort(species.genomes, function(a, b)
            return a.fitness > b.fitness
        end)
        if #species.genomes > 0 and species.genomes[1].fitness > globalTopFitness then
            globalTopFitness = species.genomes[1].fitness
        end
    end

    for _, species in ipairs(pool.species) do
        if #species.genomes > 0 then
            local topGenomeFitness = species.genomes[1].fitness
            if topGenomeFitness > species.topFitness then
                species.topFitness = topGenomeFitness
                species.staleness = 0
            else
                species.staleness = species.staleness + 1
            end

            -- Keep if: not stale OR contains global best
            if species.staleness < config.StaleSpecies or species.topFitness >= globalTopFitness then
                survived[#survived + 1] = species
            end
        end
    end

    pool.species = survived
end

--- Remove species whose share of offspring rounds to 0.
-- These species are too weak to contribute to the next generation.
-- @param pool table  The population pool.
function Species.removeWeakSpecies(pool)
    local survived = {}

    local totalAvgFitness = 0
    for _, species in ipairs(pool.species) do
        totalAvgFitness = totalAvgFitness + species.averageFitness
    end

    for _, species in ipairs(pool.species) do
        local breed = 0
        if totalAvgFitness > 0 then
            breed = math.floor(species.averageFitness / totalAvgFitness * #pool.species)
        end
        if breed >= 1 then
            survived[#survived + 1] = species
        end
    end

    -- Safety: if all species were removed, keep the best one
    if #survived == 0 and #pool.species > 0 then
        local best = pool.species[1]
        for _, species in ipairs(pool.species) do
            if species.averageFitness > best.averageFitness then
                best = species
            end
        end
        survived[#survived + 1] = best
    end

    pool.species = survived
end

--- Adjust the compatibility threshold to maintain target species count.
-- @param pool   table  The population pool.
-- @param config table  The NEAT config table.
function Species.adjustCompatibilityThreshold(pool, config)
    local speciesCount = #pool.species
    if speciesCount < config.TargetSpecies then
        config.DeltaThreshold = config.DeltaThreshold - config.ThresholdStep
    elseif speciesCount > config.TargetSpecies then
        config.DeltaThreshold = config.DeltaThreshold + config.ThresholdStep
    end
    if config.DeltaThreshold < config.ThresholdFloor then
        config.DeltaThreshold = config.ThresholdFloor
    end
    -- Upper bound prevents runaway threshold growth that would collapse
    -- all genomes into a single species, eliminating diversity pressure.
    if config.DeltaThreshold > 5.0 then
        config.DeltaThreshold = 5.0
    end
end

return Species
