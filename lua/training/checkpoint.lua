-- checkpoint.lua
-- Full NEAT population state serialization using dkjson.
-- Saves and loads species, genomes, genes, mutationRates, and innovation counter.
--
-- Usage:
--   local Checkpoint = dofile("lua/training/checkpoint.lua")
--   Checkpoint.saveCheckpoint(pool, "checkpoints/gen_42.json")
--   local pool = Checkpoint.loadCheckpoint("checkpoints/gen_42.json")

local Checkpoint = {}

-- Load dependencies
local json = dofile("lua/lib/dkjson.lua")
local Innovation = dofile("lua/neat/innovation.lua")

-- Stub console.log for non-BizHawk environments
local function log(msg)
    if console and console.log then
        console.log(msg)
    else
        print(msg)
    end
end

--- Save a full NEAT pool state to a JSON file.
-- Serializes generation, innovation counter, maxFitness, and the complete
-- species/genome/gene hierarchy.
-- @param pool     table   The NEAT population pool.
-- @param filename string  Path to write the JSON file.
function Checkpoint.saveCheckpoint(pool, filename)
    local data = {
        generation = pool.generation,
        innovation = Innovation.getCurrent(),
        maxFitness = pool.maxFitness,
        species = {},
    }

    for _, species in ipairs(pool.species) do
        local speciesData = {
            topFitness = species.topFitness,
            staleness = species.staleness,
            genomes = {},
        }
        for _, genome in ipairs(species.genomes) do
            local genomeData = {
                maxneuron = genome.maxneuron,
                fitness = genome.fitness,
                mutationRates = {},
                genes = {},
            }
            -- Copy all mutation rates
            if genome.mutationRates then
                for k, v in pairs(genome.mutationRates) do
                    genomeData.mutationRates[k] = v
                end
            end
            -- Copy all genes with their 5 critical fields
            for _, gene in ipairs(genome.genes) do
                genomeData.genes[#genomeData.genes + 1] = {
                    into = gene.into,
                    out = gene.out,
                    weight = gene.weight,
                    enabled = gene.enabled,
                    innovation = gene.innovation,
                }
            end
            speciesData.genomes[#speciesData.genomes + 1] = genomeData
        end
        data.species[#data.species + 1] = speciesData
    end

    local jsonStr = json.encode(data, {indent = true})

    -- Ensure parent directory exists
    local dir = filename:match("(.+)/[^/]+$")
    if dir then
        os.execute("mkdir -p " .. dir)
    end

    local file, err = io.open(filename, "w")
    if not file then
        log("ERROR: Cannot write checkpoint: " .. tostring(err))
        return false
    end
    file:write(jsonStr)
    file:close()

    log(string.format("Checkpoint saved: generation %d, %d species, fitness %.1f",
        pool.generation, #pool.species, pool.maxFitness))
    return true
end

--- Load a NEAT pool state from a JSON checkpoint file.
-- Reconstructs the full pool with proper types and restores the innovation counter.
-- CRITICAL: Validates innovation counter against max innovation in loaded genes (Pitfall 2).
-- @param filename string  Path to the JSON checkpoint file.
-- @return table  The reconstructed pool.
function Checkpoint.loadCheckpoint(filename)
    local file, err = io.open(filename, "r")
    if not file then
        error("Cannot read checkpoint: " .. tostring(err))
    end
    local jsonStr = file:read("*all")
    file:close()

    local data = json.decode(jsonStr)

    -- Reconstruct pool
    local pool = {
        generation = data.generation,
        maxFitness = data.maxFitness,
        species = {},
    }

    local maxInnovInGenes = 0
    local totalGenomes = 0

    for _, speciesData in ipairs(data.species) do
        local species = {
            topFitness = speciesData.topFitness,
            staleness = speciesData.staleness,
            genomes = {},
            averageFitness = 0,
        }
        for _, genomeData in ipairs(speciesData.genomes) do
            local genome = {
                maxneuron = genomeData.maxneuron,
                fitness = genomeData.fitness,
                globalRank = 0,
                mutationRates = {},
                genes = {},
                network = nil,
            }
            -- Restore mutation rates
            if genomeData.mutationRates then
                for k, v in pairs(genomeData.mutationRates) do
                    genome.mutationRates[k] = v
                end
            end
            -- Restore genes with correct types
            for _, geneData in ipairs(genomeData.genes) do
                local gene = {
                    into = math.floor(geneData.into),
                    out = math.floor(geneData.out),
                    weight = geneData.weight + 0.0,  -- ensure float
                    enabled = geneData.enabled,
                    innovation = math.floor(geneData.innovation),
                }
                genome.genes[#genome.genes + 1] = gene
                if gene.innovation > maxInnovInGenes then
                    maxInnovInGenes = gene.innovation
                end
            end
            species.genomes[#species.genomes + 1] = genome
            totalGenomes = totalGenomes + 1
        end
        pool.species[#pool.species + 1] = species
    end

    -- CRITICAL (Pitfall 2): Restore innovation counter
    Innovation.reset(data.innovation)

    -- Validate: innovation counter must be >= max innovation in any gene
    if Innovation.getCurrent() < maxInnovInGenes then
        log(string.format("WARNING: Innovation counter (%d) < max gene innovation (%d). Correcting to %d.",
            Innovation.getCurrent(), maxInnovInGenes, maxInnovInGenes + 1))
        Innovation.reset(maxInnovInGenes + 1)
    end

    log(string.format("Checkpoint loaded: generation %d, %d species, %d genomes",
        pool.generation, #pool.species, totalGenomes))

    return pool
end

--- Generate a standard checkpoint filename for a generation.
-- @param generation number  The generation number.
-- @return string  Filename like "checkpoints/gen_42.json".
function Checkpoint.getCheckpointFilename(generation)
    return "checkpoints/gen_" .. tostring(generation) .. ".json"
end

--- Find the latest checkpoint file in a directory.
-- Scans for gen_*.json files and returns the one with the highest generation number.
-- @param dir string  Directory to scan (default: "checkpoints").
-- @return string|nil  Path to latest checkpoint, or nil if none found.
function Checkpoint.getLatestCheckpoint(dir)
    dir = dir or "checkpoints"
    local latestGen = -1
    local latestFile = nil

    -- Try to list files using ls (works on Unix/Mac)
    local handle = io.popen("ls " .. dir .. "/gen_*.json 2>/dev/null")
    if handle then
        for line in handle:lines() do
            local gen = line:match("gen_(%d+)%.json")
            if gen then
                local genNum = tonumber(gen)
                if genNum and genNum > latestGen then
                    latestGen = genNum
                    latestFile = line
                end
            end
        end
        handle:close()
    end

    return latestFile
end

return Checkpoint
