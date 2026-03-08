-- evaluate_batch.lua
-- Batch training script for Tekton Pipeline integration.
-- Reuses the training loop state machine from loop.lua.
-- Runs N generations, writes results, then stops.
--
-- Environment variables:
--   GENERATIONS_PER_BATCH: how many generations to run (default: 5)
--   CHECKPOINT_DIR: where to read/write checkpoints (default: /data/output/checkpoints)
--   RESULTS_DIR: where to write results for Pipeline (default: /data/output/results)
--   BATCH_NUMBER: current batch iteration (from Tekton Loop)

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

-- Safe mkdir: validate path contains only safe characters to prevent shell injection.
local function safeMkdir(dir)
    if dir:match("[^%w/%.%-%_]") then
        error("safeMkdir: path contains unsafe characters: " .. dir)
    end
    os.execute("mkdir -p '" .. dir .. "'")
end

local GENERATIONS_PER_BATCH = tonumber(os.getenv("GENERATIONS_PER_BATCH") or "5")
local CHECKPOINT_DIR = os.getenv("CHECKPOINT_DIR") or (project_root .. "/output/checkpoints")
local RESULTS_DIR = os.getenv("RESULTS_DIR") or (project_root .. "/output/results")
local BATCH_NUMBER = tonumber(os.getenv("BATCH_NUMBER") or "0")
local FITNESS_THRESHOLD = tonumber(os.getenv("FITNESS_THRESHOLD") or "3000")

safeMkdir(CHECKPOINT_DIR)
safeMkdir(RESULTS_DIR)

-- Logging
local output_dir = project_root .. "/output"
safeMkdir(output_dir)
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

-- Set up console buffer HUD (same as main.lua)
local hud = console:createBuffer("Saiyan HUD")
hud:setSize(50, 14)

local MemoryMap = dofile("lua/memory_map.lua")
local Config = dofile("lua/neat/config.lua")
local NetworkDisplay = dofile("lua/vis/network_display.lua")

-- Reuse the training loop state machine (same one main.lua uses)
local Trainer = dofile("lua/training/loop.lua")

local trainer = Trainer.new({
    generations = GENERATIONS_PER_BATCH,
    resume = true,
    outputDir = output_dir,
}, log)

local batchStartTime = os.time()
local startGen = nil
local lastLoggedGen = -1
local json = dofile("lua/lib/dkjson.lua")
local MemoryMap = dofile("lua/memory_map.lua")

-- Write per-generation metrics as JSON array to PVC
local metricsFile = RESULTS_DIR .. "/metrics.json"
local allMetrics = {}

-- Try to load existing metrics (from previous batches)
local mf = io.open(metricsFile, "r")
if mf then
    local content = mf:read("*all")
    mf:close()
    local parsed = json.decode(content)
    if parsed then allMetrics = parsed end
end

local function writeMetrics()
    local f = io.open(metricsFile, "w")
    if f then
        f:write(json.encode(allMetrics, {indent = true}))
        f:close()
    end
end

-- HUD + overlay update
local hud_counter = 0
local draw_counter = 0

local function updateHUD()
    hud_counter = hud_counter + 1
    if hud_counter % 15 ~= 0 then return end
    hud:clear()
    hud:moveCursor(0, 0)
    local pool = trainer.pool
    if not pool then
        hud:print("  SAIYAN TRAINER - Initializing...\n")
        return
    end
    hud:print("========== SAIYAN TRAINER ==========\n")
    hud:print(string.format(" Batch: %d  Gen: %d\n", BATCH_NUMBER, pool.generation))
    hud:print(string.format(" Best: %.1f  Species: %d\n", pool.maxFitness, #pool.species))
    hud:print(string.format(" State: %s\n", trainer.state))
    if trainer.state == "evaluating" then
        local p1hp = MemoryMap.read(MemoryMap.p1_health)
        local p2hp = MemoryMap.read(MemoryMap.p2_health)
        hud:print(string.format(" Frame: %d/%d\n", trainer.frameCount, Config.TimeoutConstant))
        hud:print(string.format(" P1 HP: %d  P2 HP: %d\n", p1hp, p2hp))
    end
    hud:print("====================================\n")
end

-- Frame callback drives the state machine (one step per frame)
callbacks:add("frame", function()
    trainer:tick()
    updateHUD()

    -- Draw network overlay every 5 frames
    draw_counter = draw_counter + 1
    if draw_counter % 5 == 0 and trainer.state == "evaluating" and trainer.pool then
        local sp = trainer.pool.species[trainer.speciesIdx]
        if sp then
            local genome = sp.genomes[trainer.genomeIdx]
            if genome then
                NetworkDisplay.displayGenome(genome, trainer.pool)
            end
        end
    end

    -- Track starting generation
    if startGen == nil and trainer.pool then
        startGen = trainer.pool.generation
    end

    -- Log per-generation metrics when a new generation completes
    if trainer.pool and trainer.state == "gen_done" or
       (trainer.pool and trainer.pool.generation > lastLoggedGen and lastLoggedGen >= 0) then
        local pool = trainer.pool
        if pool.generation > lastLoggedGen then
            lastLoggedGen = pool.generation

            -- Collect metrics for this generation
            local bestFitness = -math.huge
            local totalFitness = 0
            local totalGenomes = 0
            local bestGenome = nil
            for _, sp in ipairs(pool.species) do
                for _, g in ipairs(sp.genomes) do
                    totalGenomes = totalGenomes + 1
                    totalFitness = totalFitness + g.fitness
                    if g.fitness > bestFitness then
                        bestFitness = g.fitness
                        bestGenome = g
                    end
                end
            end

            local genMetrics = {
                batch = BATCH_NUMBER,
                generation = pool.generation,
                timestamp = os.date("%Y-%m-%dT%H:%M:%SZ"),
                elapsed = os.time() - batchStartTime,
                bestFitness = bestFitness,
                avgFitness = totalGenomes > 0 and totalFitness / totalGenomes or 0,
                maxFitness = pool.maxFitness,
                species = #pool.species,
                genomes = totalGenomes,
                geneCount = bestGenome and #bestGenome.genes or 0,
                hiddenNodes = bestGenome and math.max(0, (bestGenome.maxneuron or 0) - 5) or 0,
            }

            -- Add HP deltas if available
            if bestGenome and bestGenome.hpDelta then
                genMetrics.p1HpStart = bestGenome.hpDelta.p1Start
                genMetrics.p1HpEnd = bestGenome.hpDelta.p1End
                genMetrics.p2HpStart = bestGenome.hpDelta.p2Start
                genMetrics.p2HpEnd = bestGenome.hpDelta.p2End
                genMetrics.frames = bestGenome.hpDelta.frames
            end

            allMetrics[#allMetrics + 1] = genMetrics
            writeMetrics()
        end
    end

    -- Track gen changes
    if trainer.pool and trainer.pool.generation > lastLoggedGen and lastLoggedGen == -1 then
        lastLoggedGen = trainer.pool.generation
    end

    -- Check if training is complete
    if trainer.state == "complete" and trainer.pool then
        local elapsed = os.time() - batchStartTime
        local resultsFile = RESULTS_DIR .. "/batch_" .. BATCH_NUMBER .. ".txt"
        local rf = io.open(resultsFile, "w")
        if rf then
            rf:write("best-fitness=" .. tostring(trainer.pool.maxFitness) .. "\n")
            rf:write("generation=" .. tostring(trainer.pool.generation) .. "\n")
            rf:write("species=" .. tostring(#trainer.pool.species) .. "\n")
            rf:write("elapsed=" .. tostring(elapsed) .. "\n")
            rf:write("converged=" .. (trainer.pool.maxFitness > FITNESS_THRESHOLD and "true" or "false") .. "\n")
            rf:close()
        end

        -- Final metrics write
        writeMetrics()

        log(string.format("Batch %d complete: %d generations in %ds, best=%.1f",
            BATCH_NUMBER, GENERATIONS_PER_BATCH, elapsed, trainer.pool.maxFitness))

        trainer.state = "batch_done"
    end
end)

-- Diagnostic: log P2 HP address values at startup to verify the new address
local function logP2Diagnostic()
    local old_addr = 0x03004C30  -- old (broken) P2 HP address
    local new_addr = 0x03002826  -- new (struct-stride derived) P2 HP address
    local p1_hp = emu:read8(0x0300273E)
    local old_p2 = emu:read8(old_addr)
    local new_p2 = emu:read8(new_addr)
    log(string.format("P2 HP DIAG: P1_HP=%d, old_addr(0x4C30)=%d, new_addr(0x2826)=%d",
        p1_hp, old_p2, new_p2))
end

-- Run diagnostic after a few frames (let save state settle)
local diag_counter = 0
local diag_done = false
callbacks:add("frame", function()
    if diag_done then return end
    diag_counter = diag_counter + 1
    if diag_counter == 30 then
        logP2Diagnostic()
        diag_done = true
    end
end)

log("Frame callback registered. Training will start automatically.")
