-- memory_map.lua
-- Centralized memory address configuration for DBZ: Supersonic Warriors (USA) on GBA.
--
-- IMPORTANT:
--   * This file is the ONLY place where memory addresses are defined.
--     No other Lua file should contain hardcoded addresses.
--   * mGBA reads use direct GBA memory addresses (no domain parameter needed).
--   * The `verified` field tracks which addresses have been confirmed against
--     the running game.  Set to true after you verify each one.
--   * Sources & methodology:
--       - CodeBreaker raw codes: 8300274A (Ki), 33002826 (Round), 3300273E/3F (HP)
--       - GameShark v1/v2 encrypted codes decrypted via TEA algorithm:
--           B8CE7B32 38AB9D94 -> 0300273F 000000FF (Max HP)
--           3EDD7118 5A58A127 -> 0300273E 000000FF (Infinite HP)
--           CB1E748C 4A108A48 -> 03002738 00000003 (Power Level)
--           DC4B8E1A AF073E65 -> 1300274A 00006400 (Ki 100%)
--           B9298C5C 769EFDFB -> 13004DB4 0000270F (Shop Points)
--           4734D246 90FE8764 -> D4000130 000003FB (Select button check)
--           9E69DA42 35B196E8 -> 03002826 00000000 (Instant Win)
--       - Old VBA code: github.com/waveywaves/VisualBoyAdvance-LUA (tested in-game)
--       - French cheat database (jeuxvideo.com forum): 3300273E, 3300273F codes
--       - Refer to docs/MEMORY_MAP.md for discovery instructions.
--
-- P1 struct appears to be based around 0x03002700 in IWRAM (0x03000000-0x03007FFF).
-- Known offsets from base: +0x38=power_level, +0x3E=current_hp, +0x3F=max_hp,
--                          +0x4A=ki_u16 (low=fractional, high=integer 0-100).
-- P2 struct offset from P1 is NOT YET CONFIRMED. Old VBA code used scattered
-- addresses (P2 HP at 0x03004C30, P2 Ki at 0x03002833) which don't follow a
-- simple struct offset pattern -- they may be correct or may be display/shadow copies.
--
-- Usage (mGBA):
--   local mm = dofile("lua/memory_map.lua")
--   local hp = mm.read(mm.p1_health)

---------------------------------------------------------------------------
-- Memory Map Table
---------------------------------------------------------------------------
local MemoryMap = {

    --------------- Player 1 ---------------
    -- Confirmed via GameShark TEA decryption + CodeBreaker raw codes.
    -- HP is stored as a u8 (0-255), NOT as a percentage.
    -- Ki is stored as u16: high byte = integer 0-100, low byte = fractional.

    p1_health = {
        addr     = 0x0300273E,
        size     = 1,
        type     = "u8",
        desc     = "P1 Current HP (0-255). Confirmed by GS decryption + CB 3300273E + old VBA code.",
        verified = true,   -- GS decrypt: 3EDD7118 5A58A127 -> 0300273E 000000FF
    },
    p1_health_max = {
        addr     = 0x0300273F,
        size     = 1,
        type     = "u8",
        desc     = "P1 Max HP (0-255). GS 'Max Vie' writes 0xFF here once; game caps current HP at this.",
        verified = true,   -- GS decrypt: B8CE7B32 38AB9D94 -> 0300273F 000000FF
    },
    p1_ki = {
        addr     = 0x0300274A,
        size     = 2,
        type     = "u16",
        desc     = "P1 Ki as u16 (high byte=integer 0-100%, low byte=fractional). CB 8300274A 6400.",
        verified = true,   -- CodeBreaker 8300274A + GS decrypt DC4B8E1A -> 1300274A 00006400
    },
    p1_ki_int = {
        addr     = 0x0300274B,
        size     = 1,
        type     = "u8",
        desc     = "P1 Ki integer only (0-100 = 0%-100%). Read this for simpler Ki percentage.",
        verified = true,   -- high byte of Ki u16; 0x64=100 confirmed by cheat code
    },
    p1_power_level = {
        addr     = 0x03002738,
        size     = 1,
        type     = "u8",
        desc     = "P1 Power Level / transformation form (0=base, 3=max). GS 'All Chars Stronger'.",
        verified = true,   -- GS decrypt: CB1E748C 4A108A48 -> 03002738 00000003
    },

    --------------- Player 2 ---------------
    -- P2 struct at P1_base + 0xE8 stride = 0x030027E8.
    -- Evidence: P2 Ki int at 0x03002833 (old VBA code, tested in-game) matches
    -- P1 Ki int (0x0300274B) + 0xE8. Applying same stride to all P1 offsets:
    --   P2 power_level: 0x030027E8 + 0x38 = 0x03002820
    --   P2 HP:          0x030027E8 + 0x3E = 0x03002826
    --   P2 max_hp:      0x030027E8 + 0x3F = 0x03002827
    --   P2 ki_u16:      0x030027E8 + 0x4A = 0x03002832
    --   P2 ki_int:      0x030027E8 + 0x4B = 0x03002833 (confirmed by VBA code)
    -- The "instant win" cheat (CB 33002826 00) writes 0 to P2 HP = KO.
    -- Previous address 0x03004C30 (old VBA) read constant 72, never changed.

    p2_health = {
        addr     = 0x03002826,
        size     = 1,
        type     = "u8",
        desc     = "P2 Current HP (0-255). Derived: P2 struct base 0x030027E8 + offset 0x3E. Cheat code 33002826 00 (instant win) confirms: writing 0 here = KO.",
        verified = false,  -- derived from struct stride + cheat code correlation; needs visual confirmation
    },
    p2_health_max = {
        addr     = 0x03002827,
        size     = 1,
        type     = "u8",
        desc     = "P2 Max HP (0-255). Derived: P2 struct base + 0x3F (same offset as P1 max HP).",
        verified = false,
    },
    p2_power_level = {
        addr     = 0x03002820,
        size     = 1,
        type     = "u8",
        desc     = "P2 Power Level (0-3). Derived: P2 struct base + 0x38.",
        verified = false,
    },
    p2_ki = {
        addr     = 0x03002832,
        size     = 2,
        type     = "u16",
        desc     = "P2 Ki as u16 (high byte=integer 0-100%). Derived: P2 struct base + 0x4A.",
        verified = false,
    },
    p2_ki_int = {
        addr     = 0x03002833,
        size     = 1,
        type     = "u8",
        desc     = "P2 Ki integer (0-100). From old VBA code, confirmed in-game. Used to derive P2 struct stride.",
        verified = false,  -- from old VBA code, tested in-game
    },

    --------------- Spatial (relative distances) ---------------
    -- These come from old VBA code. The game may pre-compute relative distances
    -- rather than storing absolute X/Y per player.

    dist_x = {
        addr     = 0x03002CD4,
        size     = 2,
        type     = "u16",
        desc     = "X distance between players (0-630 range, from old VBA code)",
        verified = false,  -- from old VBA code, needs visual confirmation
    },
    dist_y = {
        addr     = 0x03002CD8,
        size     = 2,
        type     = "u16",
        desc     = "Y distance between players (0-630 range, from old VBA code)",
        verified = false,  -- from old VBA code, needs visual confirmation
    },
    polar_dir = {
        addr     = 0x0300288C,
        size     = 1,
        type     = "u8",
        desc     = "Direction quadrant (0-8=NE, 8-16=SE, 16-24=SW, 24-32=NW, from old VBA code)",
        verified = false,  -- from old VBA code, needs visual confirmation
    },

    --------------- Match State ---------------
    -- round_state was previously mapped to 0x03002826, but struct stride analysis
    -- shows this address is P2 HP (see p2_health above). The "instant win" cheat
    -- (writing 0x00) works because it sets P2 HP to 0 = KO, not because it's a
    -- separate round state flag. Removed to avoid address collision with p2_health.
    timer = {
        addr     = 0x03002830,
        size     = 2,
        type     = "u16",
        desc     = "Match timer countdown value -- PLACEHOLDER, needs RAM search",
        verified = false,
    },

    --------------- Shop / Unlock State (not used during fights) ---------------
    shop_points = {
        addr     = 0x03004DB4,
        size     = 2,
        type     = "u16",
        desc     = "Shop points (0-9999). GS decrypt: B9298C5C 769EFDFB -> 13004DB4 0000270F.",
        verified = true,   -- GS decrypted
    },
    unlock_flags = {
        addr     = 0x03004D58,
        size     = 2,  -- first of 4 consecutive u16 entries (4D58, 4D5A, 4D5C, 4D5E)
        type     = "u16",
        desc     = "Unlock flags base addr. CB slide 43004D58 FFFF x4 inc2 unlocks everything.",
        verified = true,   -- CodeBreaker 43004D58 FFFF 00000004 0002
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

--- Read only the 4 addresses used by training (p1_health, p2_health, p1_ki_int, p1_power_level).
-- More efficient than readAll() which reads every address including unverified ones.
-- @return table  Keys are entry names, values are read integers.
function MemoryMap.readTraining()
    return {
        p1_health      = MemoryMap.read(MemoryMap.p1_health),
        p2_health      = MemoryMap.read(MemoryMap.p2_health),
        p1_ki_int      = MemoryMap.read(MemoryMap.p1_ki_int),
        p1_power_level = MemoryMap.read(MemoryMap.p1_power_level),
    }
end

--- Read all memory map entries and return a {name = value} table.
-- Skips non-table entries (functions, etc.).
-- Useful for debugging; prefer readTraining() for the hot path.
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
