-- loop.lua
-- State-machine training loop driven by mGBA frame callbacks.
-- Each tick() call processes one frame of work.
--
-- States:
--   waiting    -> Poll for fight_start save state
--   init       -> Create or load NEAT population
--   eval_setup -> Load save state and prepare genome evaluation
--   evaluating -> Per-frame genome evaluation (read inputs, forward pass, apply controller)
--   gen_done   -> Log stats, save checkpoint, breed next generation
--   complete   -> All generations finished
--
-- Usage:
--   local Trainer = dofile("lua/training/loop.lua")
--   local t = Trainer.new({generations = 100, resume = true, outputDir = "output"}, logFn)
--   callbacks:add("frame", function() t:tick() end)

local TrainingLoop = {}

-- Load all dependencies
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

-- Wire up module dependencies
Pool.setDependencies(Genome, Species, Crossover, Mutation, Network)
Mutation.setDependencies(Network, Genome)
Crossover.setDependencies(Genome)
Checkpoint.setInnovation(Innovation)

--- Create a new trainer instance.
-- @param options table  {generations, resume, checkpointFile, outputDir}
-- @param logFn   function  Logging function (receives string).
-- @return table  Trainer instance with tick() method.
function TrainingLoop.new(options, logFn)
    options = options or {}
    local self = {
        -- Configuration
        maxGenerations = options.generations or 100,
        resumeEnabled = options.resume ~= false,
        checkpointFile = options.checkpointFile,
        outputDir = options.outputDir or "output",

        -- State machine
        state = "waiting",

        -- Population
        pool = nil,
        speciesIdx = 1,
        genomeIdx = 1,
        startGen = 0,

        -- Per-evaluation tracking
        frameCount = 0,
        lastDamageFrame = 0,
        startP1HP = 0,
        startP2HP = 0,
        prevP2HP = 0,
        comboLogger = nil,

        -- Waiting state counter
        waitFrames = 0,

        -- Logging
        log = logFn or function(msg) print(msg) end,
    }
    setmetatable(self, { __index = TrainingLoop })
    return self
end

--- Advance the trainer by one frame.
function TrainingLoop:tick()
    local handler = self["tick_" .. self.state]
    if handler then
        handler(self)
    end
end

--- WAITING: poll for fight_start save state.
function TrainingLoop:tick_waiting()
    self.waitFrames = self.waitFrames + 1
    if self.waitFrames == 1 then
        if not SaveState.hasFightStartState() then
            self.log("Waiting for fight start save state...")
            self.log("Save to: " .. SaveState.getFightStartFile())
        end
    end
    if self.waitFrames % 60 ~= 0 then return end

    if SaveState.hasFightStartState() then
        self.log("Save state detected!")
        self.state = "init"
    end
end

--- INIT: create or load population.
function TrainingLoop:tick_init()
    local cpDir = self.outputDir .. "/checkpoints"
    os.execute("mkdir -p " .. cpDir)

    -- Try to load existing checkpoint
    if self.checkpointFile then
        self.log("Resuming from: " .. self.checkpointFile)
        self.pool = Checkpoint.loadCheckpoint(self.checkpointFile)
    elseif self.resumeEnabled then
        local latest = Checkpoint.getLatestCheckpoint(cpDir)
        if latest then
            self.log("Auto-resuming from: " .. latest)
            self.pool = Checkpoint.loadCheckpoint(latest)
        else
            local path = cpDir .. "/latest.json"
            local f = io.open(path, "r")
            if f then
                f:close()
                self.log("Auto-resuming from: " .. path)
                self.pool = Checkpoint.loadCheckpoint(path)
            end
        end
    end

    if not self.pool then
        self.log("Creating new population...")
        self.pool = Pool.newPool(Config, Innovation)
    end

    self.startGen = self.pool.generation

    self.log("=== Training Configuration ===")
    self.log(string.format("  Population: %d", Config.Population))
    self.log(string.format("  Inputs: %d, Outputs: %d", Config.Inputs, Config.Outputs))
    self.log(string.format("  Target: %s generations",
        self.maxGenerations == 0 and "infinite" or tostring(self.maxGenerations)))
    self.log(string.format("  Starting at generation: %d", self.pool.generation))
    self.log("==============================")

    -- Start evaluating first genome
    self.speciesIdx = 1
    self.genomeIdx = 1
    self:findNextGenome()
end

--- Find next unevaluated genome. Sets state to eval_setup or gen_done.
function TrainingLoop:findNextGenome()
    while self.speciesIdx <= #self.pool.species do
        local sp = self.pool.species[self.speciesIdx]
        while self.genomeIdx <= #sp.genomes do
            if sp.genomes[self.genomeIdx].fitness == 0 then
                self.state = "eval_setup"
                return
            end
            self.genomeIdx = self.genomeIdx + 1
        end
        self.speciesIdx = self.speciesIdx + 1
        self.genomeIdx = 1
    end
    self.state = "gen_done"
end

--- EVAL_SETUP: load save state and prepare genome evaluation.
function TrainingLoop:tick_eval_setup()
    local genome = self.pool.species[self.speciesIdx].genomes[self.genomeIdx]

    -- Reset fight to deterministic start
    SaveState.resetFight()

    -- Build neural network from genome
    Network.generateNetwork(genome, Config)

    -- Reset all evaluation tracking
    self.frameCount = 0
    self.lastDamageFrame = 0
    self.comboLogger = ComboLogger.newLogger()
    self.startP1HP = MemoryMap.read(MemoryMap.p1_health)
    self.startP2HP = MemoryMap.read(MemoryMap.p2_health)
    self.prevP2HP = self.startP2HP

    self.state = "evaluating"
end

--- EVALUATING: run one frame of genome evaluation.
function TrainingLoop:tick_evaluating()
    local genome = self.pool.species[self.speciesIdx].genomes[self.genomeIdx]

    -- Forward pass: read game state -> neural network -> controller output
    local inputs = GameInputs.getGameInputs()
    local outputs = Network.evaluateNetwork(genome.network, inputs, Config)
    Controller.applyController(outputs)

    -- Record button state for combo analysis
    ComboLogger.record(self.comboLogger, Controller.outputsToController(outputs))

    -- Track damage dealt to opponent
    local currentP2HP = MemoryMap.read(MemoryMap.p2_health)
    if currentP2HP < self.prevP2HP then
        self.lastDamageFrame = self.frameCount
    end
    self.prevP2HP = currentP2HP

    self.frameCount = self.frameCount + 1

    -- Check termination: HP-based or timeout.
    -- NOTE: round_state address semantics are inverted (0=instant win trigger,
    -- non-zero=normal gameplay), so we use HP to detect round end instead.
    local endP1HP = MemoryMap.read(MemoryMap.p1_health)
    local endP2HP = currentP2HP
    local roundResult = Fitness.IN_PROGRESS

    if endP1HP <= 0 and endP2HP > 0 then
        roundResult = Fitness.LOSE
    elseif endP2HP <= 0 and endP1HP > 0 then
        roundResult = Fitness.WIN
    elseif endP1HP <= 0 and endP2HP <= 0 then
        roundResult = Fitness.DRAW
    end

    -- Continue evaluating if nobody is KO'd and not timed out
    if roundResult == Fitness.IN_PROGRESS and self.frameCount <= Config.TimeoutConstant then
        return
    end

    -- Timed out: determine result from final HP comparison
    if roundResult == Fitness.IN_PROGRESS then
        if endP1HP > endP2HP then roundResult = Fitness.WIN
        elseif endP2HP > endP1HP then roundResult = Fitness.LOSE
        else roundResult = Fitness.DRAW end
    end

    Controller.clearController()

    genome.fitness = Fitness.calculateFitness({
        startP1HP = self.startP1HP, endP1HP = endP1HP,
        startP2HP = self.startP2HP, endP2HP = endP2HP,
        roundResult = roundResult,
        frameCount = self.frameCount,
        lastDamageFrame = self.lastDamageFrame,
    })

    genome.comboAnalysis = ComboLogger.analyzeInputLog(self.comboLogger.log)

    -- Store HP deltas for debugging
    genome.hpDelta = {
        p1Start = self.startP1HP, p1End = endP1HP,
        p2Start = self.startP2HP, p2End = endP2HP,
        frames = self.frameCount,
    }

    -- Advance to next unevaluated genome
    self.genomeIdx = self.genomeIdx + 1
    self:findNextGenome()
end

--- GEN_DONE: log stats, save checkpoint, breed next generation.
function TrainingLoop:tick_gen_done()
    local pool = self.pool
    local cpDir = self.outputDir .. "/checkpoints"

    -- Find best genome in this generation (start at -math.huge to capture negative fitness)
    local bestFitness = -math.huge
    local bestGenome = nil
    local totalGenomes = 0
    for _, sp in ipairs(pool.species) do
        for _, genome in ipairs(sp.genomes) do
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

    -- Track for HUD display
    self.lastGenBest = bestFitness

    self.log(string.format("Gen %d: best=%.1f (all-time=%.1f), species=%d, genomes=%d",
        pool.generation, bestFitness, pool.maxFitness, #pool.species, totalGenomes))

    if bestGenome and bestGenome.comboAnalysis then
        local ca = bestGenome.comboAnalysis
        self.log(string.format("  Combo: entropy=%.2f, unique=%d, mashing=%s",
            ca.entropy, ca.uniquePatterns, tostring(ca.isButtonMashing)))
    end

    -- Log HP deltas for best genome to diagnose P2 HP address validity
    if bestGenome and bestGenome.hpDelta then
        local hp = bestGenome.hpDelta
        self.log(string.format("  HP: P1 %d->%d (%+d), P2 %d->%d (%+d), frames=%d",
            hp.p1Start, hp.p1End, hp.p1End - hp.p1Start,
            hp.p2Start, hp.p2End, hp.p2End - hp.p2Start,
            hp.frames))
    end

    -- Save checkpoints
    Checkpoint.saveCheckpoint(pool, cpDir .. "/gen_" .. pool.generation .. ".json")
    Checkpoint.saveCheckpoint(pool, cpDir .. "/latest.json")

    -- Check if all generations complete
    local targetGen = self.maxGenerations == 0 and math.huge or (self.startGen + self.maxGenerations)
    if pool.generation + 1 >= targetGen then
        self.log("Training complete!")
        Checkpoint.saveCheckpoint(pool, cpDir .. "/final.json")
        self.state = "complete"
        return
    end

    -- Breed next generation
    Pool.newGeneration(pool, Config, Innovation)

    local progress = pool.generation - self.startGen
    self.log(string.format("Starting generation %d/%d (%d%%)",
        pool.generation, self.maxGenerations,
        math.floor(progress / self.maxGenerations * 100)))

    -- Begin evaluating new generation
    self.speciesIdx = 1
    self.genomeIdx = 1
    self:findNextGenome()
end

return TrainingLoop
