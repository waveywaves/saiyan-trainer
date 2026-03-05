-- utils.lua
-- Shared utility functions for Saiyan Trainer Lua scripts.
--
-- Usage (BizHawk):
--   local utils = dofile("lua/utils.lua")

local utils = {}

--- Format a number as a "0xNNNN" hex string.
-- @param value number  The numeric value to format.
-- @return string  Hex-formatted string, e.g. "0x002A".
function utils.formatHex(value)
    if value == nil then
        return "nil"
    end
    return string.format("0x%04X", value)
end

--- Format a single game-state entry for display.
-- Produces a string like "p1_health: 85 (0x0055)".
-- @param name  string  The entry name (e.g. "p1_health").
-- @param value number  The current read value.
-- @param entry table   The MemoryMap entry (used for future extensions).
-- @return string  Formatted display string.
function utils.formatState(name, value, entry)
    if value == nil then
        return string.format("%-14s: --", name)
    end
    return string.format("%-14s: %6d (%s)", name, value, utils.formatHex(value))
end

return utils
