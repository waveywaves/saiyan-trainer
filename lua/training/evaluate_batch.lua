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

-- Frame callback drives the state machine (one step per frame)
callbacks:add("frame", function()
    trainer:tick()

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

log("Frame callback registered. Training will start automatically.")
