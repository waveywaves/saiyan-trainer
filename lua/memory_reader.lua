-- memory_reader.lua
-- Diagnostic mGBA Lua script for DBZ: Supersonic Warriors (USA).
--
-- Reads ALL game state from memory via memory_map.lua and logs it
-- to the console.  Load this script in mGBA during a fight to verify
-- that memory addresses are returning correct values.
--
-- Usage:
--   mGBA: mgba-sdl -s lua/memory_reader.lua rom.gba
--   Or: Load from mGBA scripting window (Tools > Scripting)

---------------------------------------------------------------------------
-- Module loading
---------------------------------------------------------------------------
local mm    = dofile("lua/memory_map.lua")
local utils = dofile("lua/utils.lua")

---------------------------------------------------------------------------
-- Console logger (throttled)
---------------------------------------------------------------------------

--- Print a summary line to mGBA's console.
-- @param state table  {name = value} from mm.readAll()
local function logToConsole(state)
    local line = string.format(
        "P1 Health: %d | P2 Health: %d | P1 Ki: %d | P2 Ki: %d | Timer: %d | Round: %d",
        state.p1_health or 0,
        state.p2_health or 0,
        state.p1_ki     or 0,
        state.p2_ki     or 0,
        state.timer      or 0,
        state.round_state or 0
    )
    console:log(line)
end

---------------------------------------------------------------------------
-- Startup banner
---------------------------------------------------------------------------
console:log("=== Saiyan Trainer Memory Reader ===")
console:log("Loaded memory_map.lua -- reading all game state each frame.")

local unverified = mm.getUnverified()
if #unverified > 0 then
    console:log("WARNING: The following addresses are UNVERIFIED (placeholder values):")
    for _, name in ipairs(unverified) do
        local entry = mm[name]
        console:log(string.format(
            "  %s  addr=%s  type=%s",
            name, utils.formatHex(entry.addr), entry.type
        ))
    end
    console:log("Replace placeholders with real addresses found via RAM Search.")
else
    console:log("All addresses verified.")
end
console:log("")

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local frameCount = 0
local LOG_INTERVAL = 60  -- log to console every 60 frames to avoid spam

while true do
    local state = mm.readAll()

    -- Throttled console logging
    if frameCount % LOG_INTERVAL == 0 then
        logToConsole(state)
    end

    frameCount = frameCount + 1
    emu:runFrame()
end
