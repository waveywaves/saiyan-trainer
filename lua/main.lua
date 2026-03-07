-- main.lua
-- Saiyan Trainer - NEAT Fighting Game AI
-- Entry point script loaded by mGBA.
--
-- Usage:
--   mGBA: mgba-qt --script lua/main.lua rom.gba
--   Or: Load this script from mGBA's scripting window (Tools > Scripting)

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

print("========================================")
print("  Saiyan Trainer - NEAT Fighting Game AI")
print("  Neuroevolution for DBZ: Supersonic Warriors")
print("  v0.2.0 - mGBA Edition")
print("========================================")
print("")

-- Load the save state helper to check prerequisites
local SaveState = dofile("lua/savestate_helper.lua")

-- Patch emu:runFrame() to yield instead of blocking.
-- mGBA advances frames automatically; our frame callback resumes
-- the training coroutine each frame. This keeps Qt's event loop
-- alive so the display updates during training.
local _emu_runFrame = emu.runFrame
function emu:runFrame()
    coroutine.yield()
end

local training_co = nil
local frame_count = 0

callbacks:add("frame", function()
    -- If training coroutine is running, resume it
    if training_co and coroutine.status(training_co) ~= "dead" then
        local ok, err = coroutine.resume(training_co)
        if not ok then
            console:log("[ERROR] " .. tostring(err))
            training_co = nil
        end
        return
    end

    -- Otherwise, wait for save state
    frame_count = frame_count + 1
    if frame_count % 60 ~= 1 then return end

    if not SaveState.hasFightStartState() then
        if frame_count == 1 then
            console:log("Waiting for fight start save state...")
            console:log("Create one via: Tools > Save State File")
            console:log("  Save to: " .. SaveState.getFightStartFile())
        end
        return
    end

    -- Save state found — start training in a coroutine
    console:log("Save state detected! Starting training...")

    local TrainingLoop = dofile("lua/training/loop.lua")

    local options = {
        generations = 100,
        resume = true,
        opponents = nil,
        opponentRotation = 10,
    }

    console:log("Starting NEAT training...")
    training_co = coroutine.create(function()
        TrainingLoop.runTraining(options)
    end)

    -- First resume to kick it off
    local ok, err = coroutine.resume(training_co)
    if not ok then
        console:log("[ERROR] " .. tostring(err))
        training_co = nil
    end
end)
