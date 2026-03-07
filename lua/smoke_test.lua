-- smoke_test.lua
-- Diagnostic script that tests the full training pipeline step by step
-- and writes results to /data/output/smoke_test.log.

local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local project_root = script_path:match("^(.*)/lua/smoke_test%.lua$") or "."

-- Patch dofile for project-relative paths (same as main.lua)
if project_root ~= "." then
    local _dofile = dofile
    dofile = function(path)
        if path:sub(1, 1) ~= "/" then
            return _dofile(project_root .. "/" .. path)
        end
        return _dofile(path)
    end
end

local log_path = project_root .. "/output/smoke_test.log"
local f = io.open(log_path, "w")

local function log(msg)
    local line = os.date("%H:%M:%S") .. " " .. msg
    print(line)
    if console and console.log then
        pcall(function() console:log(line) end)
    end
    if f then f:write(line .. "\n"); f:flush() end
end

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        log("[PASS] " .. name)
    else
        log("[FAIL] " .. name .. ": " .. tostring(err))
    end
    return ok
end

log("=== Saiyan Trainer Smoke Test ===")
log("project_root: " .. project_root)

-- Test 1: emu object
test("emu object exists", function()
    assert(type(emu) == "userdata", "emu is " .. type(emu))
end)

-- Test 2: callbacks object
test("callbacks object exists", function()
    assert(callbacks ~= nil, "callbacks is nil")
    assert(callbacks.add ~= nil, "callbacks.add is nil")
end)

-- Test 3: Load memory map
local mm
test("load memory_map.lua", function()
    mm = dofile("lua/memory_map.lua")
    assert(mm.p1_health, "p1_health missing")
end)

-- Test 4: Read memory values
test("read P1 health", function()
    local val = mm.read(mm.p1_health)
    log("  P1 HP = " .. tostring(val))
end)

test("read P1 ki", function()
    local val = mm.read(mm.p1_ki)
    log("  P1 Ki = " .. tostring(val))
end)

test("read round_state", function()
    local val = mm.read(mm.round_state)
    log("  round_state = " .. tostring(val))
end)

test("readAll", function()
    local state = mm.readAll()
    for k, v in pairs(state) do
        log("  " .. k .. " = " .. tostring(v))
    end
end)

-- Test 5: Load save state
local SaveState
test("load savestate_helper", function()
    SaveState = dofile("lua/savestate_helper.lua")
end)

test("fight_start.ss0 exists", function()
    assert(SaveState.hasFightStartState(), "save state not found at " .. SaveState.getFightStartFile())
end)

test("load fight_start save state", function()
    SaveState.resetFight()
end)

-- Test 6: Read memory after save state load
test("read memory after save state load", function()
    local state = mm.readAll()
    log("  Post-load P1 HP = " .. tostring(state.p1_health))
    log("  Post-load P2 HP = " .. tostring(state.p2_health))
    log("  Post-load round_state = " .. tostring(state.round_state))
end)

-- Test 7: Load NEAT modules
test("load neat/config", function()
    dofile("lua/neat/config.lua")
end)

test("load neat/innovation", function()
    dofile("lua/neat/innovation.lua")
end)

test("load neat/genome", function()
    dofile("lua/neat/genome.lua")
end)

test("load neat/network", function()
    dofile("lua/neat/network.lua")
end)

test("load neat/mutation", function()
    dofile("lua/neat/mutation.lua")
end)

test("load neat/crossover", function()
    dofile("lua/neat/crossover.lua")
end)

test("load neat/species", function()
    dofile("lua/neat/species.lua")
end)

test("load neat/pool", function()
    dofile("lua/neat/pool.lua")
end)

-- Test 8: Load game modules
test("load game/inputs", function()
    dofile("lua/game/inputs.lua")
end)

test("load game/fitness", function()
    dofile("lua/game/fitness.lua")
end)

test("load controller", function()
    dofile("lua/controller.lua")
end)

-- Test 9: Load training modules
test("load training/checkpoint", function()
    dofile("lua/training/checkpoint.lua")
end)

test("load training/combo_logger", function()
    dofile("lua/training/combo_logger.lua")
end)

-- Test 10: Create a population and evaluate one genome
test("create NEAT population", function()
    local Config = dofile("lua/neat/config.lua")
    local Pool = dofile("lua/neat/pool.lua")
    local Innovation = dofile("lua/neat/innovation.lua")
    local Genome = dofile("lua/neat/genome.lua")
    local Species = dofile("lua/neat/species.lua")
    local Crossover = dofile("lua/neat/crossover.lua")
    local Mutation = dofile("lua/neat/mutation.lua")
    local Network = dofile("lua/neat/network.lua")

    Pool.setDependencies(Genome, Species, Crossover, Mutation, Network)
    Mutation.setDependencies(Network, Genome)
    Crossover.setDependencies(Genome)

    local pool = Pool.newPool(Config, Innovation)
    log("  Population created: " .. #pool.species .. " species")
    local totalGenomes = 0
    for _, sp in ipairs(pool.species) do
        totalGenomes = totalGenomes + #sp.genomes
    end
    log("  Total genomes: " .. totalGenomes)
end)

-- Test 11: Evaluate a single genome (5 frames only)
test("evaluate single genome (5 frames)", function()
    local Config = dofile("lua/neat/config.lua")
    local Network = dofile("lua/neat/network.lua")
    local Genome = dofile("lua/neat/genome.lua")
    local GameInputs = dofile("lua/game/inputs.lua")
    local Controller = dofile("lua/controller.lua")
    local Fitness = dofile("lua/game/fitness.lua")

    -- Create a minimal genome
    local genome = Genome.newGenome(Config)
    Network.generateNetwork(genome, Config)

    -- Load save state
    SaveState.resetFight()

    local startP1HP = mm.read(mm.p1_health)
    local startP2HP = mm.read(mm.p2_health)
    log("  Start P1 HP: " .. startP1HP .. ", P2 HP: " .. startP2HP)

    -- Run 5 frames
    for frame = 1, 5 do
        local inputs = GameInputs.getGameInputs()
        local outputs = Network.evaluateNetwork(genome.network, inputs, Config)
        Controller.applyController(outputs)
        -- Use the real emu:runFrame (not yielding version)
        emu:runFrame()
    end

    Controller.clearController()
    local endP1HP = mm.read(mm.p1_health)
    local endP2HP = mm.read(mm.p2_health)
    log("  End P1 HP: " .. endP1HP .. ", P2 HP: " .. endP2HP)

    local fitness = Fitness.calculateFitness({
        startP1HP = startP1HP, endP1HP = endP1HP,
        startP2HP = startP2HP, endP2HP = endP2HP,
        roundResult = Fitness.IN_PROGRESS,
        frameCount = 5, lastDamageFrame = 0,
    })
    log("  Fitness after 5 frames: " .. tostring(fitness))
end)

-- Test 12: Checkpoint I/O
test("checkpoint save/load", function()
    local Config = dofile("lua/neat/config.lua")
    local Pool = dofile("lua/neat/pool.lua")
    local Innovation = dofile("lua/neat/innovation.lua")
    local Genome = dofile("lua/neat/genome.lua")
    local Species = dofile("lua/neat/species.lua")
    local Crossover = dofile("lua/neat/crossover.lua")
    local Mutation = dofile("lua/neat/mutation.lua")
    local Network = dofile("lua/neat/network.lua")
    local Checkpoint = dofile("lua/training/checkpoint.lua")

    Pool.setDependencies(Genome, Species, Crossover, Mutation, Network)
    Mutation.setDependencies(Network, Genome)
    Crossover.setDependencies(Genome)

    local pool = Pool.newPool(Config, Innovation)

    local cp_path = project_root .. "/output/smoke_checkpoint.json"
    os.execute("mkdir -p " .. project_root .. "/output")
    Checkpoint.saveCheckpoint(pool, cp_path)
    log("  Saved checkpoint to: " .. cp_path)

    local loaded = Checkpoint.loadCheckpoint(cp_path)
    log("  Loaded checkpoint: gen=" .. loaded.generation .. " species=" .. #loaded.species)
end)

log("=== Smoke Test Complete ===")
if f then f:close() end
