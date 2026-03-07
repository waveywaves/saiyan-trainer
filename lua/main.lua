-- main.lua
-- Saiyan Trainer - NEAT Fighting Game AI
-- Entry point script loaded by mGBA.
--
-- Architecture: Frame-callback state machine. mGBA calls our frame callback
-- once per emulated frame. Each call advances the trainer by one step.
-- The emu userdata is sealed (no __newindex), so we cannot patch emu:runFrame()
-- or use coroutines. Instead, the training loop is inverted into a state machine.
--
-- Usage:
--   mGBA: mgba-qt --script lua/main.lua rom.gba

-- Resolve the project root from this script's location so that
-- dofile("lua/...") works regardless of the emulator's working directory.
local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local project_root = script_path:match("^(.*)/lua/main%.lua$") or "."
if project_root ~= "." then
    local _dofile = dofile
    dofile = function(path)
        if path:sub(1,1) ~= "/" then
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

-- Set up file-based logging (mGBA print/console:log don't reach docker stdout)
local output_dir = project_root .. "/output"
safeMkdir(output_dir)
local log_file = io.open(output_dir .. "/training.log", "a")

local function log(msg)
    local line = os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg
    print(line)
    if console and console.log then
        pcall(function() console:log(msg) end)
    end
    if log_file then
        log_file:write(line .. "\n")
        log_file:flush()
    end
end

log("========================================")
log("  Saiyan Trainer - NEAT Fighting Game AI")
log("  Neuroevolution for DBZ: Supersonic Warriors")
log("  v0.3.0 - mGBA State Machine Edition")
log("========================================")

-- Set up console buffer HUD (text panel in mGBA scripting window)
local hud = console:createBuffer("Saiyan HUD")
hud:setSize(50, 14)

local MemoryMap = dofile("lua/memory_map.lua")
local Config = dofile("lua/neat/config.lua")
local NetworkDisplay = dofile("lua/vis/network_display.lua")

-- Load the training loop state machine
local Trainer = dofile("lua/training/loop.lua")

local trainer = Trainer.new({
    generations = 100,
    resume = true,
    outputDir = output_dir,
}, log)

-- Training timer
local training_start = os.time()
local gen_start = os.time()
local total_frames = 0

local function formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%dh %02dm %02ds", h, m, s)
    elseif m > 0 then
        return string.format("%dm %02ds", m, s)
    else
        return string.format("%ds", s)
    end
end

-- Track generation changes for timing
local last_gen = -1

-- HUD update (called every N frames to avoid overhead)
local hud_counter = 0
local function updateHUD()
    hud_counter = hud_counter + 1
    total_frames = total_frames + 1
    if hud_counter % 15 ~= 0 then return end

    hud:clear()
    hud:moveCursor(0, 0)

    local st = trainer.state
    local pool = trainer.pool
    local now = os.time()
    local elapsed = now - training_start

    if st == "waiting" then
        hud:print("  SAIYAN TRAINER - Waiting for save state\n")
        return
    end

    if not pool then
        hud:print("  SAIYAN TRAINER - Initializing...\n")
        return
    end

    local gen = pool.generation
    local species = #pool.species
    local best = pool.maxFitness

    -- Detect generation change for timing
    if gen ~= last_gen then
        gen_start = now
        last_gen = gen
    end

    local gen_elapsed = now - gen_start
    local fps = 0
    if elapsed > 0 then fps = math.floor(total_frames / elapsed) end

    hud:print("========== SAIYAN TRAINER ==========\n")
    hud:print(string.format(" Gen: %-4d  Species: %-3d\n", gen, species))
    hud:print(string.format(" Best: %.1f  All-time: %.1f\n",
        trainer.lastGenBest or 0, best))
    hud:print(string.format(" Timer: %s  (gen: %s)\n",
        formatTime(elapsed), formatTime(gen_elapsed)))
    hud:print(string.format(" FPS: %d\n", fps))

    if st == "evaluating" then
        local p1hp = MemoryMap.read(MemoryMap.p1_health)
        local p2hp = MemoryMap.read(MemoryMap.p2_health)
        local frame = trainer.frameCount
        local pct = math.floor(frame / Config.TimeoutConstant * 100)
        hud:print(string.format(" Frame: %d/%d (%d%%)\n",
            frame, Config.TimeoutConstant, pct))
        hud:print(string.format(" P1 HP: %-3d  P2 HP: %-3d\n", p1hp, p2hp))

        -- Count total genomes and current position
        local totalGenomes = 0
        local currentGenome = 0
        for si, sp in ipairs(pool.species) do
            for gi, _ in ipairs(sp.genomes) do
                totalGenomes = totalGenomes + 1
                if si < trainer.speciesIdx or
                   (si == trainer.speciesIdx and gi <= trainer.genomeIdx) then
                    currentGenome = currentGenome + 1
                end
            end
        end
        hud:print(string.format(" Genome: %d/%d\n", currentGenome, totalGenomes))
    elseif st == "gen_done" or st == "eval_setup" then
        hud:print(string.format(" State: %s\n", st))
    elseif st == "complete" then
        hud:print(" TRAINING COMPLETE!\n")
    end

    hud:print("====================================\n")
end

-- Register frame callback to drive the training state machine.
-- mGBA calls this once per emulated frame.
local draw_counter = 0
local DRAW_INTERVAL = 5  -- update overlay every 5 frames (~12 FPS visual update)

callbacks:add("frame", function()
    trainer:tick()
    updateHUD()
    draw_counter = draw_counter + 1
    if draw_counter % DRAW_INTERVAL == 0 then
        -- Get current genome being evaluated
        local genome = nil
        if trainer.state == "evaluating" and trainer.pool then
            local sp = trainer.pool.species[trainer.speciesIdx]
            if sp then
                genome = sp.genomes[trainer.genomeIdx]
            end
        end
        if genome then
            NetworkDisplay.displayGenome(genome, trainer.pool)
        end
    end
end)

log("Frame callback registered. Training will start automatically.")
