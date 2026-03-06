-- memory_map.lua
-- Centralized memory address configuration for DBZ: Supersonic Warriors (USA) on GBA.
--
-- IMPORTANT:
--   * This file is the ONLY place where memory addresses are defined.
--     No other Lua file should contain hardcoded addresses.
--   * All addresses below are PLACEHOLDERS in the 0x03000000 (IWRAM / System Bus)
--     range.  Replace them with real addresses discovered via RAM Search.
--   * mGBA reads use direct GBA memory addresses (no domain parameter needed).
--   * The `verified` field tracks which addresses have been confirmed against
--     the running game.  Set to true after you verify each one.
--   * Refer to docs/MEMORY_MAP.md for discovery instructions and notes.
--
-- Usage (mGBA):
--   local mm = dofile("lua/memory_map.lua")
--   local hp = mm.read(mm.p1_health)

---------------------------------------------------------------------------
-- Memory Map Table
---------------------------------------------------------------------------
local MemoryMap = {

    --------------- Player 1 ---------------
    p1_health = {
        addr     = 0x03002700,
        size     = 2,
        type     = "u16",
        desc     = "P1 Health (expected range 0-100 or 0-1000)",
        verified = false,
    },
    p1_ki = {
        addr     = 0x0300274A,
        size     = 2,
        type     = "u16",
        desc     = "P1 Ki Energy (known seed from CodeBreaker 8300274A)",
        verified = true,  -- cheat-code seed
    },
    p1_x = {
        addr     = 0x03002710,
        size     = 2,
        type     = "s16",
        desc     = "P1 X Position (signed, increases moving right)",
        verified = false,
    },
    p1_y = {
        addr     = 0x03002712,
        size     = 2,
        type     = "s16",
        desc     = "P1 Y Position (signed, changes during jumps/flight)",
        verified = false,
    },
    p1_state = {
        addr     = 0x03002720,
        size     = 1,
        type     = "u8",
        desc     = "P1 Attack/Animation State (state machine byte)",
        verified = false,
    },

    --------------- Player 2 ---------------
    p2_health = {
        addr     = 0x03002800,
        size     = 2,
        type     = "u16",
        desc     = "P2 Health",
        verified = false,
    },
    p2_ki = {
        addr     = 0x03002802,
        size     = 2,
        type     = "u16",
        desc     = "P2 Ki Energy",
        verified = false,
    },
    p2_x = {
        addr     = 0x03002810,
        size     = 2,
        type     = "s16",
        desc     = "P2 X Position",
        verified = false,
    },
    p2_y = {
        addr     = 0x03002812,
        size     = 2,
        type     = "s16",
        desc     = "P2 Y Position",
        verified = false,
    },
    p2_state = {
        addr     = 0x03002820,
        size     = 1,
        type     = "u8",
        desc     = "P2 Attack/Animation State",
        verified = false,
    },

    --------------- Match State ---------------
    round_state = {
        addr     = 0x03002826,
        size     = 1,
        type     = "u8",
        desc     = "Round/match outcome state (known seed from CodeBreaker 33002826)",
        verified = true,  -- cheat-code seed
    },
    timer = {
        addr     = 0x03002830,
        size     = 2,
        type     = "u16",
        desc     = "Match timer countdown value",
        verified = false,
    },
}

---------------------------------------------------------------------------
-- Read helpers (mGBA API)
---------------------------------------------------------------------------

--- Read a single memory entry using the mGBA emu API.
-- Dispatches to emu:read8 / emu:read16 / emu:read32 based on entry.type.
-- For signed types (s16), reads unsigned then converts via two's complement.
-- @param entry table  A MemoryMap entry with .addr and .type fields.
-- @return number  The value at the given address.
function MemoryMap.read(entry)
    if entry.type == "u8" then
        return emu:read8(entry.addr)
    elseif entry.type == "u16" then
        return emu:read16(entry.addr)
    elseif entry.type == "s16" then
        local val = emu:read16(entry.addr)
        if val >= 0x8000 then val = val - 0x10000 end
        return val
    elseif entry.type == "u32" then
        return emu:read32(entry.addr)
    else
        error("MemoryMap.read: unknown type '" .. tostring(entry.type) .. "'")
    end
end

--- Read all memory map entries and return a {name = value} table.
-- Skips non-table entries (functions, etc.).
-- @return table  Keys are entry names, values are read integers.
function MemoryMap.readAll()
    local state = {}
    for name, entry in pairs(MemoryMap) do
        if type(entry) == "table" and entry.addr then
            state[name] = MemoryMap.read(entry)
        end
    end
    return state
end

--- Return a list of entry names whose `verified` field is false.
-- Useful for tracking which placeholder addresses still need real values.
-- @return table  Array of unverified entry name strings.
function MemoryMap.getUnverified()
    local unverified = {}
    for name, entry in pairs(MemoryMap) do
        if type(entry) == "table" and entry.verified == false then
            unverified[#unverified + 1] = name
        end
    end
    table.sort(unverified)
    return unverified
end

return MemoryMap
