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

local GENERATIONS_PER_BATCH = tonumber(os.getenv("GENERATIONS_PER_BATCH") or "5")
local CHECKPOINT_DIR = os.getenv("CHECKPOINT_DIR") or (project_root .. "/output/checkpoints")
local RESULTS_DIR = os.getenv("RESULTS_DIR") or (project_root .. "/output/results")
local BATCH_NUMBER = tonumber(os.getenv("BATCH_NUMBER") or "0")

os.execute("mkdir -p " .. CHECKPOINT_DIR)
os.execute("mkdir -p " .. RESULTS_DIR)

-- Logging
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

-- Reuse the training loop state machine (same one main.lua uses)
local Trainer = dofile("lua/training/loop.lua")

local trainer = Trainer.new({
    generations = GENERATIONS_PER_BATCH,
    resume = true,
    outputDir = output_dir,
}, log)

-- Override checkpoint dir
-- The trainer uses outputDir for checkpoints already

local batchStartTime = os.time()
local startGen = nil

-- Frame callback drives the state machine (one step per frame)
callbacks:add("frame", function()
    trainer:tick()

    -- Track starting generation
    if startGen == nil and trainer.pool then
        startGen = trainer.pool.generation
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
            rf:write("converged=" .. (trainer.pool.maxFitness > 5000 and "true" or "false") .. "\n")
            rf:close()
        end

        log(string.format("Batch %d complete: %d generations in %ds, best=%.1f",
            BATCH_NUMBER, GENERATIONS_PER_BATCH, elapsed, trainer.pool.maxFitness))

        -- Prevent repeated writes
        trainer.state = "batch_done"
    end
end)

log("Frame callback registered. Training will start automatically.")
