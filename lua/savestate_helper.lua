-- savestate_helper.lua
-- Save state management for deterministic NEAT training evaluations.
-- Provides fight-start reset so every genome evaluation begins from
-- an identical game state.
--
-- Usage:
--   local ss = dofile("lua/savestate_helper.lua")
--   -- First time: navigate to VS Mode fight start, then call:
--   ss.createFightStartState()
--   -- Before each evaluation:
--   ss.resetFight()

local SaveStateHelper = {}

-- Resolve project root from this script's location
local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local project_root = script_path:match("^(.*)/lua/savestate_helper%.lua$") or "."

-- Directory where save state files are stored.
local SAVE_STATE_DIR = project_root .. "/savestates/"

-- File path for the fight-start save state.
-- This state should capture the exact frame where a fight begins:
-- both characters at full health, timer started, player has control.
local FIGHT_START_FILE = SAVE_STATE_DIR .. "fight_start.ss0"

--- Check whether the fight-start save state file exists.
-- @return boolean  true if the file exists and can be opened.
function SaveStateHelper.hasFightStartState()
    local f = io.open(FIGHT_START_FILE, "r")
    if f then
        f:close()
        return true
    end
    return false
end

--- Reset the fight by loading the fight-start save state.
-- Call this before each genome evaluation to ensure deterministic starting conditions.
-- Emulator state (RAM, registers, VRAM) is fully restored; Lua script variables
-- are NOT affected by save state loads.
--
-- @return boolean  true if the state loaded successfully.
-- @return string|nil  Error message if the state file is missing.
function SaveStateHelper.resetFight()
    if not SaveStateHelper.hasFightStartState() then
        local msg = "Fight start save state not found at: " .. FIGHT_START_FILE
        pcall(function() console:log(msg) end)
        return false, msg
    end
    emu:loadStateFile(FIGHT_START_FILE)
    return true
end

--- Create the fight-start save state at the current emulator frame.
-- Instructions:
--   1. Launch ROM in mGBA
--   2. Navigate to: Main Menu -> VS Mode -> Select Characters -> Start Fight
--   3. Wait for the fight countdown to finish and control is given to the player
--   4. Call this function (e.g., via Lua console or a trigger script)
--
-- The saved state captures the entire emulator state at that frame.
function SaveStateHelper.createFightStartState()
    emu:saveStateFile(FIGHT_START_FILE)
    pcall(function() console:log("Fight start save state created at: " .. FIGHT_START_FILE) end)
end

--- Get the path to the fight-start save state file.
-- @return string  File path.
function SaveStateHelper.getFightStartFile()
    return FIGHT_START_FILE
end

return SaveStateHelper
