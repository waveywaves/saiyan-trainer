-- loop.lua
-- Main training loop that drives NEAT evolution across generations.
-- Evaluates each genome by playing fights in mGBA, computes fitness,
-- saves checkpoints, logs combos, and supports multi-opponent rotation.
--
-- Usage:
--   local TrainingLoop = dofile("lua/training/loop.lua")
--   TrainingLoop.runTraining({generations = 100, resume = true})

local TrainingLoop = {}

-- Load all dependencies via dofile
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

-- Load NEAT sub-modules needed by Pool
local Genome = dofile("lua/neat/genome.lua")
local Species = dofile("lua/neat/species.lua")
local Crossover = dofile("lua/neat/crossover.lua")
local Mutation = dofile("lua/neat/mutation.lua")

-- Wire up module dependencies
Pool.setDependencies(Genome, Species, Crossover, Mutation, Network)
Mutation.setDependencies(Network, Genome)
Crossover.setDependencies(Genome)

-- Memory map for direct health reads during evaluation
local MemoryMap = dofile("lua/memory_map.lua")

-- Stub console.log for safety
local function log(msg)
    if console and console.log then
        console:log(msg)
    end
    print(msg)
end

--- Multi-opponent configuration state
local opponentConfig = nil
local currentOpponentIndex = 1

--- Set the opponent rotation configuration.
-- @param opponents table  Array of {file=string, desc=string} save state entries.
function TrainingLoop.setOpponentConfig(opponents)
    opponentConfig = opponents
    currentOpponentIndex = 1
    if opponents and #opponents > 0 then
        log("Multi-opponent configured with " .. #opponents .. " opponents:")
        for i, opp in ipairs(opponents) do
            log("  " .. i .. ". " .. opp.desc .. " (" .. opp.file .. ")")
        end
    end
end

--- Rotate to the appropriate opponent for the current generation.
-- Uses rotation formula: index = floor(generation / rotationInterval) % numOpponents + 1
-- @param generation      number  Current generation number.
-- @param rotationInterval number  Rotate every N generations.
local function rotateOpponent(generation, rotationInterval)
    if not opponentConfig or #opponentConfig == 0 then
        return
    end
    local newIndex = (math.floor(generation / rotationInterval) % #opponentConfig) + 1
    if newIndex ~= currentOpponentIndex then
        currentOpponentIndex = newIndex
        log(string.format("Rotating opponent to: %s (%s)",
            opponentConfig[newIndex].desc,
            opponentConfig[newIndex].file))
    end
end

--- Get the current save state file for fight reset.
-- If multi-opponent is configured, returns the current opponent's file.
-- Otherwise returns nil (SaveState uses its default).
-- @return string|nil  Path to save state file, or nil for default.
local function getCurrentSaveStateFile()
    if opponentConfig and #opponentConfig > 0 then
        return opponentConfig[currentOpponentIndex].file
    end
    return nil
end

--- Evaluate a single genome by playing a fight.
-- 1. Loads save state for deterministic start
-- 2. Runs frame-by-frame: read inputs -> forward pass -> apply controller
-- 3. Tracks damage, stalls, and logs combos
-- 4. Computes fitness after fight ends or timeout
--
-- IMPORTANT (Pitfall 5): All Lua tracking variables are explicitly reset here.
-- Save state load does NOT reset Lua script variables.
--
-- @param genome table  The genome to evaluate.
-- @param pool   table  The population pool (for context).
function TrainingLoop.evaluateGenome(genome, pool)
    -- Step 1: Load save state (reset fight)
    local saveFile = getCurrentSaveStateFile()
    if saveFile then
        emu:loadStateFile(saveFile)
    else
        SaveState.resetFight()
    end

    -- Step 2: Build network from genome
    Network.generateNetwork(genome, Config)

    -- Step 3-5: Explicitly reset ALL Lua tracking variables (Pitfall 5)
    local frameCount = 0
    local lastDamageFrame = 0
    local comboLogger = ComboLogger.newLogger()

    -- Read starting health values
    local startP1HP = MemoryMap.read(MemoryMap.p1_health)
    local startP2HP = MemoryMap.read(MemoryMap.p2_health)
    local prevP2HP = startP2HP

    -- Step 6: Per-frame evaluation loop
    while true do
        -- 6a: Read game inputs (11-element normalized array)
        local inputs = GameInputs.getGameInputs()

        -- 6b: Forward pass through neural network
        local outputs = Network.evaluateNetwork(genome.network, inputs, Config)

        -- 6c: Apply outputs to controller (all buttons in ONE setKeys call)
        Controller.applyController(outputs)

        -- 6d: Record buttons in combo logger
        local buttonState = Controller.outputsToController(outputs)
        ComboLogger.record(comboLogger, buttonState)

        -- 6e: Track damage dealt
        local currentP2HP = MemoryMap.read(MemoryMap.p2_health)
        if currentP2HP < prevP2HP then
            lastDamageFrame = frameCount
        end
        prevP2HP = currentP2HP

        -- 6f: Check termination conditions
        frameCount = frameCount + 1

        -- Check round state from memory
        local roundState = MemoryMap.read(MemoryMap.round_state)

        -- Determine round result
        local endP1HP = MemoryMap.read(MemoryMap.p1_health)
        local endP2HP = currentP2HP
        local roundResult = Fitness.IN_PROGRESS

        if roundState ~= 0 then
            -- Round is over; determine outcome from health
            if endP2HP <= 0 and endP1HP > 0 then
                roundResult = Fitness.WIN
            elseif endP1HP <= 0 and endP2HP > 0 then
                roundResult = Fitness.LOSE
            elseif endP1HP <= 0 and endP2HP <= 0 then
                roundResult = Fitness.DRAW
            else
                -- Some other end state (timer, etc)
                if endP1HP > endP2HP then
                    roundResult = Fitness.WIN
                elseif endP2HP > endP1HP then
                    roundResult = Fitness.LOSE
                else
                    roundResult = Fitness.DRAW
                end
            end
        end

        -- 6g: Break on round over or timeout
        if roundResult ~= Fitness.IN_PROGRESS or frameCount > Config.TimeoutConstant then
            -- If timed out, determine result from health
            if roundResult == Fitness.IN_PROGRESS then
                local finalP1HP = MemoryMap.read(MemoryMap.p1_health)
                local finalP2HP = MemoryMap.read(MemoryMap.p2_health)
                if finalP1HP > finalP2HP then
                    roundResult = Fitness.WIN
                elseif finalP2HP > finalP1HP then
                    roundResult = Fitness.LOSE
                else
                    roundResult = Fitness.DRAW
                end
                endP1HP = finalP1HP
                endP2HP = finalP2HP
            end

            -- Step 7: Clear controller
            Controller.clearController()

            -- Step 8: Calculate fitness
            local fitness = Fitness.calculateFitness({
                startP1HP = startP1HP,
                endP1HP = endP1HP,
                startP2HP = startP2HP,
                endP2HP = endP2HP,
                roundResult = roundResult,
                frameCount = frameCount,
                lastDamageFrame = lastDamageFrame,
            })

            -- Step 9: Set genome fitness
            genome.fitness = fitness

            -- Step 10: Store combo analysis
            genome.comboAnalysis = ComboLogger.analyzeInputLog(comboLogger.log)

            return
        end

        -- 6h-6i: Continue to next frame
        emu:runFrame()
    end
end

--- Evaluate all unevaluated genomes in the population.
-- Iterates through all species and genomes, evaluating those with fitness == 0.
-- @param pool table  The population pool.
function TrainingLoop.evaluatePopulation(pool)
    local genomeCount = 0
    local bestFitness = 0

    for _, species in ipairs(pool.species) do
        for _, genome in ipairs(species.genomes) do
            if genome.fitness == 0 then
                TrainingLoop.evaluateGenome(genome, pool)
                genomeCount = genomeCount + 1
            end
            if genome.fitness > bestFitness then
                bestFitness = genome.fitness
            end
        end
    end

    log(string.format("Evaluated %d genomes, best fitness: %.1f, species: %d",
        genomeCount, bestFitness, #pool.species))
end

--- Run a single generation: evaluate, checkpoint, and breed.
-- @param pool table  The population pool.
function TrainingLoop.runGeneration(pool)
    -- 1. Evaluate all genomes
    TrainingLoop.evaluatePopulation(pool)

    -- 2. Track best fitness
    local bestFitness = 0
    local bestGenome = nil
    local totalGenomes = 0
    for _, species in ipairs(pool.species) do
        for _, genome in ipairs(species.genomes) do
            totalGenomes = totalGenomes + 1
            if genome.fitness > bestFitness then
                bestFitness = genome.fitness
                bestGenome = genome
            end
        end
    end

    if bestFitness > pool.maxFitness then
        pool.maxFitness = bestFitness
    end

    -- 3. Log generation stats
    log(string.format("Gen %d: best=%.1f (all-time=%.1f), species=%d, genomes=%d",
        pool.generation, bestFitness, pool.maxFitness, #pool.species, totalGenomes))

    -- 4. Save checkpoint every generation
    Checkpoint.saveCheckpoint(pool, Checkpoint.getCheckpointFilename(pool.generation))

    -- 5. Also save "latest" checkpoint for easy resume
    Checkpoint.saveCheckpoint(pool, "checkpoints/latest.json")

    -- 6. Log combo analysis for best genome
    if bestGenome and bestGenome.comboAnalysis then
        local ca = bestGenome.comboAnalysis
        log(string.format("  Best genome combo analysis: entropy=%.2f, unique=%d, mashing=%s",
            ca.entropy, ca.uniquePatterns, tostring(ca.isButtonMashing)))
        if ca.topPatterns and #ca.topPatterns > 0 then
            log("  Top pattern: " .. ca.topPatterns[1].buttons ..
                " (x" .. ca.topPatterns[1].count .. ")")
        end
    end

    -- 7. Breed next generation
    Pool.newGeneration(pool, Config, Innovation)
end

--- Main entry point: run the full NEAT training loop.
-- @param options table  Training options:
--   generations      number  How many generations to run (0 = infinite).
--   resume           boolean Attempt to load latest checkpoint on start.
--   checkpointFile   string  Specific checkpoint file to resume from.
--   opponents        table   Array of {file=string, desc=string} for multi-opponent.
--   opponentRotation number  Rotate opponent every N generations (default 10).
function TrainingLoop.runTraining(options)
    options = options or {}
    local maxGenerations = options.generations or 100
    local rotationInterval = options.opponentRotation or 10

    -- 1. Create checkpoints directory
    os.execute("mkdir -p checkpoints")

    -- Configure multi-opponent if provided
    if options.opponents then
        TrainingLoop.setOpponentConfig(options.opponents)
    end

    -- 2-3. Load or create pool
    local pool = nil

    if options.checkpointFile then
        -- Resume from specific checkpoint
        log("Resuming from checkpoint: " .. options.checkpointFile)
        pool = Checkpoint.loadCheckpoint(options.checkpointFile)
    elseif options.resume then
        -- Try to load latest checkpoint
        local latest = Checkpoint.getLatestCheckpoint("checkpoints")
        if latest then
            log("Auto-resuming from: " .. latest)
            pool = Checkpoint.loadCheckpoint(latest)
        else
            -- Also try latest.json
            local f = io.open("checkpoints/latest.json", "r")
            if f then
                f:close()
                log("Auto-resuming from: checkpoints/latest.json")
                pool = Checkpoint.loadCheckpoint("checkpoints/latest.json")
            end
        end
    end

    if not pool then
        log("Creating new population...")
        pool = Pool.newPool(Config, Innovation)
    end

    -- 4. Log training configuration
    log("=== Training Configuration ===")
    log(string.format("  Population: %d", Config.Population))
    log(string.format("  Inputs: %d, Outputs: %d", Config.Inputs, Config.Outputs))
    log(string.format("  Target generations: %s", maxGenerations == 0 and "infinite" or tostring(maxGenerations)))
    log(string.format("  Starting generation: %d", pool.generation))
    if opponentConfig then
        log(string.format("  Opponents: %d, rotation every %d generations",
            #opponentConfig, rotationInterval))
    end
    log("==============================")

    -- 5. Generation loop
    local startGen = pool.generation
    local targetGen = maxGenerations == 0 and math.huge or (startGen + maxGenerations)

    while pool.generation < targetGen do
        -- 5a. Rotate opponent if multi-opponent configured
        if opponentConfig then
            rotateOpponent(pool.generation, rotationInterval)
        end

        -- 5b. Run one generation
        TrainingLoop.runGeneration(pool)

        -- 5c. Log progress
        if maxGenerations > 0 then
            local progress = pool.generation - startGen
            log(string.format("Generation %d/%d complete (%d%%)",
                progress, maxGenerations, math.floor(progress / maxGenerations * 100)))
        end
    end

    -- 6. Final save
    log("Training complete. Final checkpoint saved.")
    Checkpoint.saveCheckpoint(pool, "checkpoints/final.json")
end

return TrainingLoop
