-- evaluate_batch.lua
-- Batch training script for Tekton Pipeline integration.
-- Runs N generations of NEAT training, saves checkpoint, and writes
-- results to files for the Pipeline to read.
--
-- Unlike main.lua (which runs indefinitely via frame callbacks),
-- this script runs a fixed number of generations and exits.
--
-- Environment variables:
--   GENERATIONS_PER_BATCH: how many generations to run (default: 5)
--   CHECKPOINT_DIR: where to read/write checkpoints (default: /data/output/checkpoints)
--   RESULTS_DIR: where to write results for Pipeline (default: /data/output/results)
--   BATCH_NUMBER: current batch iteration (from Tekton Loop)
--
-- Usage:
--   mgba-qt --script lua/training/evaluate_batch.lua rom.gba

local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local project_root = script_path:match("^(.*)/lua/training/evaluate_batch%.lua$") or "."
if project_root ~= "." then
    local _dofile = dofile
    dofile = function(path)
        if path:sub(1, 1) ~= "/" then
            return _dofile(project_root .. "/" .. path)
        end
        return _dofile(path)
    end
end

-- Configuration from environment (or defaults)
local GENERATIONS_PER_BATCH = tonumber(os.getenv("GENERATIONS_PER_BATCH") or "5")
local CHECKPOINT_DIR = os.getenv("CHECKPOINT_DIR") or (project_root .. "/output/checkpoints")
local RESULTS_DIR = os.getenv("RESULTS_DIR") or (project_root .. "/output/results")
local BATCH_NUMBER = tonumber(os.getenv("BATCH_NUMBER") or "0")

os.execute("mkdir -p " .. CHECKPOINT_DIR)
os.execute("mkdir -p " .. RESULTS_DIR)

-- Set up logging
local output_dir = project_root .. "/output"
os.execute("mkdir -p " .. output_dir)
local log_file = io.open(output_dir .. "/training.log", "a")

local function log(msg)
    local line = os.date("%Y-%m-%d %H:%M:%S") .. " [batch-" .. BATCH_NUMBER .. "] " .. msg
    print(line)
    if log_file then
        log_file:write(line .. "\n")
        log_file:flush()
    end
end

log("========================================")
log("  Saiyan Trainer - Batch Training Mode")
log("  Batch: " .. BATCH_NUMBER)
log("  Generations per batch: " .. GENERATIONS_PER_BATCH)
log("========================================")

-- Load training modules
local Config = dofile("lua/neat/config.lua")
local Pool = dofile("lua/neat/pool.lua")
local Network = dofile("lua/neat/network.lua")
local Innovation = dofile("lua/neat/innovation.lua")
local GameInputs = dofile("lua/game/inputs.lua")
local Fitness = dofile("lua/game/fitness.lua")
local Controller = dofile("lua/controller.lua")
local SaveState = dofile("lua/savestate_helper.lua")
local Checkpoint = dofile("lua/training/checkpoint.lua")
local ComboLogger = dofile("lua/training/combo_logger.lua")
local Genome = dofile("lua/neat/genome.lua")
local Species = dofile("lua/neat/species.lua")
local Crossover = dofile("lua/neat/crossover.lua")
local Mutation = dofile("lua/neat/mutation.lua")
local MemoryMap = dofile("lua/memory_map.lua")

-- Wire dependencies
Pool.setDependencies(Genome, Species, Crossover, Mutation, Network)
Mutation.setDependencies(Network, Genome)
Crossover.setDependencies(Genome)
Checkpoint.setInnovation(Innovation)

-- State tracking
local pool = nil
local gensDone = 0
local batchStartTime = os.time()

-- Load or create population
local latestCheckpoint = CHECKPOINT_DIR .. "/latest.json"
local f = io.open(latestCheckpoint, "r")
if f then
    f:close()
    log("Resuming from: " .. latestCheckpoint)
    pool = Checkpoint.loadCheckpoint(latestCheckpoint)
else
    log("Creating new population...")
    pool = Pool.newPool(Config, Innovation)
end

log(string.format("Starting at generation %d, running %d generations",
    pool.generation, GENERATIONS_PER_BATCH))

-- Evaluate a single genome (blocking — uses emu:runFrame)
local function evaluateGenome(genome)
    SaveState.resetFight()
    Network.generateNetwork(genome, Config)

    local frameCount = 0
    local lastDamageFrame = 0
    local comboLogger = ComboLogger.newLogger()
    local startP1HP = MemoryMap.read(MemoryMap.p1_health)
    local startP2HP = MemoryMap.read(MemoryMap.p2_health)
    local prevP2HP = startP2HP

    while true do
        local inputs = GameInputs.getGameInputs()
        local outputs = Network.evaluateNetwork(genome.network, inputs, Config)
        Controller.applyController(outputs)
        ComboLogger.record(comboLogger, Controller.outputsToController(outputs))

        local currentP2HP = MemoryMap.read(MemoryMap.p2_health)
        if currentP2HP < prevP2HP then
            lastDamageFrame = frameCount
        end
        prevP2HP = currentP2HP

        frameCount = frameCount + 1

        local endP1HP = MemoryMap.read(MemoryMap.p1_health)
        local endP2HP = currentP2HP
        local roundResult = Fitness.IN_PROGRESS

        if endP2HP <= 0 and endP1HP > 0 then
            roundResult = Fitness.KO
        elseif endP1HP <= 0 and endP2HP > 0 then
            roundResult = Fitness.LOSE
        elseif endP1HP <= 0 and endP2HP <= 0 then
            roundResult = Fitness.DRAW
        end

        if roundResult == Fitness.IN_PROGRESS and frameCount <= Config.TimeoutConstant then
            emu:runFrame()
        else
            if roundResult == Fitness.IN_PROGRESS then
                if endP1HP > endP2HP then roundResult = Fitness.WIN
                elseif endP2HP > endP1HP then roundResult = Fitness.LOSE
                else roundResult = Fitness.DRAW end
            end

            Controller.clearController()

            genome.fitness = Fitness.calculateFitness({
                startP1HP = startP1HP, endP1HP = endP1HP,
                startP2HP = startP2HP, endP2HP = endP2HP,
                roundResult = roundResult,
                frameCount = frameCount,
                timeoutConstant = Config.TimeoutConstant,
                lastDamageFrame = lastDamageFrame,
            })
            return
        end
    end
end

-- Main batch loop (runs via frame callback)
local state = "evaluating"
local speciesIdx = 1
local genomeIdx = 1

local function findNextGenome()
    while speciesIdx <= #pool.species do
        local sp = pool.species[speciesIdx]
        while genomeIdx <= #sp.genomes do
            if sp.genomes[genomeIdx].fitness == 0 then
                return true
            end
            genomeIdx = genomeIdx + 1
        end
        speciesIdx = speciesIdx + 1
        genomeIdx = 1
    end
    return false
end

callbacks:add("frame", function()
    if state == "done" then return end

    if state == "evaluating" then
        if findNextGenome() then
            local genome = pool.species[speciesIdx].genomes[genomeIdx]
            evaluateGenome(genome)
            genomeIdx = genomeIdx + 1
        else
            -- Generation complete
            local bestFitness = -math.huge
            local totalGenomes = 0
            for _, sp in ipairs(pool.species) do
                for _, genome in ipairs(sp.genomes) do
                    totalGenomes = totalGenomes + 1
                    if genome.fitness > bestFitness then
                        bestFitness = genome.fitness
                    end
                end
            end

            if bestFitness > pool.maxFitness then
                pool.maxFitness = bestFitness
            end

            log(string.format("Gen %d: best=%.1f (all-time=%.1f), species=%d, genomes=%d",
                pool.generation, bestFitness, pool.maxFitness, #pool.species, totalGenomes))

            -- Save checkpoint
            Checkpoint.saveCheckpoint(pool, CHECKPOINT_DIR .. "/gen_" .. pool.generation .. ".json")
            Checkpoint.saveCheckpoint(pool, latestCheckpoint)

            gensDone = gensDone + 1

            if gensDone >= GENERATIONS_PER_BATCH then
                -- Batch complete — write results for Tekton Pipeline
                local elapsed = os.time() - batchStartTime
                local resultsFile = RESULTS_DIR .. "/batch_" .. BATCH_NUMBER .. ".txt"
                local rf = io.open(resultsFile, "w")
                if rf then
                    rf:write("best-fitness=" .. tostring(pool.maxFitness) .. "\n")
                    rf:write("generation=" .. tostring(pool.generation) .. "\n")
                    rf:write("species=" .. tostring(#pool.species) .. "\n")
                    rf:write("elapsed=" .. tostring(elapsed) .. "\n")
                    rf:write("converged=" .. (pool.maxFitness > 5000 and "true" or "false") .. "\n")
                    rf:close()
                end

                log(string.format("Batch %d complete: %d generations in %ds, best=%.1f",
                    BATCH_NUMBER, gensDone, elapsed, pool.maxFitness))

                state = "done"
                return
            end

            -- Breed next generation
            Pool.newGeneration(pool, Config, Innovation)
            speciesIdx = 1
            genomeIdx = 1
        end
    end
end)
