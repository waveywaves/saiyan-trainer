-- p2_hp_scanner.lua
-- Standalone mGBA script to identify the correct P2 HP memory address.
--
-- Usage: mgba-qt --script lua/tools/p2_hp_scanner.lua rom.gba
--
-- Then play the game via noVNC and attack P2. Watch console output
-- for which candidate address decreases when P2 takes damage.
--
-- The script monitors:
--   1. Six specific candidate addresses (from old VBA code + struct offset hypotheses)
--   2. A broad scan range around P1 HP region (0x03002700-0x03002900)
--   3. A broad scan range around old VBA P2 HP region (0x03004C00-0x03004D00)
--
-- P1 HP (0x0300273E) is shown as a reference. When P1 takes damage,
-- this value should decrease, confirming the script is working.
--
-- After 300 frames, the script prints a recommendation for the most
-- likely P2 HP address based on change patterns.

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------

-- Known/verified P1 HP address (reference for confirming script works)
local P1_HP_ADDR = 0x0300273E

-- Candidate P2 HP addresses from research
local candidates = {
    { addr = 0x03004C30, name = "VBA_P2HP",   note = "old VBA code address" },
    { addr = 0x030027B2, name = "STRUCT_74",   note = "0x74 struct offset from P1 HP" },
    { addr = 0x030027BE, name = "STRUCT_80",   note = "0x80 struct offset" },
    { addr = 0x030027DE, name = "STRUCT_A0",   note = "0xA0 struct offset" },
    { addr = 0x030027FE, name = "STRUCT_C0",   note = "0xC0 struct offset" },
    { addr = 0x0300283E, name = "STRUCT_100",  note = "0x100 struct offset" },
}

-- Broad scan ranges for discovering unknown addresses
local BROAD_RANGES = {
    { start = 0x03002700, stop = 0x03002900, name = "P1_REGION" },
    { start = 0x03004C00, stop = 0x03004D00, name = "P2_REGION" },
}

-- How often to print the summary table (in frames)
local SUMMARY_INTERVAL = 60

-- How many frames before printing the final recommendation
local RECOMMENDATION_FRAME = 300

---------------------------------------------------------------------------
-- State tracking
---------------------------------------------------------------------------

-- Previous values for candidate addresses
local prev_candidates = {}
for _, c in ipairs(candidates) do
    prev_candidates[c.addr] = nil  -- will be initialized on first frame
end

-- Change tracking for candidates
local change_counts = {}
local decrease_counts = {}
for _, c in ipairs(candidates) do
    change_counts[c.addr] = 0
    decrease_counts[c.addr] = 0
end

-- Broad scan previous values and change tracking
local broad_prev = {}
local broad_changes = {}
local broad_decreases = {}

for _, range in ipairs(BROAD_RANGES) do
    for addr = range.start, range.stop - 1 do
        broad_prev[addr] = nil
        broad_changes[addr] = 0
        broad_decreases[addr] = 0
    end
end

-- P1 HP reference tracking
local prev_p1_hp = nil
local p1_hp_changes = 0

-- Frame counter
local frame_count = 0
local recommendation_printed = false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function addrStr(addr)
    return string.format("0x%08X", addr)
end

local function log(msg)
    console:log(msg)
end

---------------------------------------------------------------------------
-- Frame callback
---------------------------------------------------------------------------

callbacks:add("frame", function()
    frame_count = frame_count + 1

    -- Read P1 HP as reference
    local p1_hp = emu:read8(P1_HP_ADDR)
    if prev_p1_hp == nil then
        prev_p1_hp = p1_hp
        log("[INIT] P1 HP reference: " .. p1_hp .. " at " .. addrStr(P1_HP_ADDR))
    elseif p1_hp ~= prev_p1_hp then
        p1_hp_changes = p1_hp_changes + 1
        log(string.format("[REF] P1 HP: %d -> %d  [frame %d]", prev_p1_hp, p1_hp, frame_count))
        prev_p1_hp = p1_hp
    end

    -- Monitor candidate addresses
    for _, c in ipairs(candidates) do
        local val = emu:read8(c.addr)
        if prev_candidates[c.addr] == nil then
            prev_candidates[c.addr] = val
        elseif val ~= prev_candidates[c.addr] then
            local old = prev_candidates[c.addr]
            change_counts[c.addr] = change_counts[c.addr] + 1
            if val < old then
                decrease_counts[c.addr] = decrease_counts[c.addr] + 1
            end
            log(string.format("CHANGED: %s (%s)  %d -> %d  [frame %d]",
                c.name, addrStr(c.addr), old, val, frame_count))
            prev_candidates[c.addr] = val
        end
    end

    -- Broad scan: check all addresses in scan ranges
    for _, range in ipairs(BROAD_RANGES) do
        for addr = range.start, range.stop - 1 do
            local val = emu:read8(addr)
            if broad_prev[addr] == nil then
                broad_prev[addr] = val
            elseif val ~= broad_prev[addr] then
                local old = broad_prev[addr]
                broad_changes[addr] = broad_changes[addr] + 1
                if val < old then
                    broad_decreases[addr] = broad_decreases[addr] + 1
                end
                -- Only log broad scan changes if they look HP-like (value in 0-255, reasonable)
                -- Avoid spamming; only log first 3 changes per address
                if broad_changes[addr] <= 3 then
                    log(string.format("[BROAD %s] %s  %d -> %d  [frame %d]",
                        range.name, addrStr(addr), old, val, frame_count))
                end
                broad_prev[addr] = val
            end
        end
    end

    -- Periodic summary table
    if frame_count % SUMMARY_INTERVAL == 0 then
        log("========================================")
        log(string.format("=== SUMMARY at frame %d ===", frame_count))
        log("========================================")
        log(string.format("  P1 HP (ref): %d  (changes: %d)", p1_hp, p1_hp_changes))
        log("--- Candidate Addresses ---")
        log(string.format("  %-12s  %-12s  %5s  %5s  %5s", "Name", "Address", "Value", "Chng", "Decr"))
        for _, c in ipairs(candidates) do
            local val = emu:read8(c.addr)
            log(string.format("  %-12s  %s  %5d  %5d  %5d",
                c.name, addrStr(c.addr), val, change_counts[c.addr], decrease_counts[c.addr]))
        end

        -- Broad scan: show top changers (addresses with most changes)
        local top_changers = {}
        for _, range in ipairs(BROAD_RANGES) do
            for addr = range.start, range.stop - 1 do
                if broad_changes[addr] > 0 then
                    -- Skip addresses that are already in the candidate list
                    local is_candidate = false
                    for _, c in ipairs(candidates) do
                        if c.addr == addr then is_candidate = true; break end
                    end
                    if not is_candidate and addr ~= P1_HP_ADDR then
                        table.insert(top_changers, {
                            addr = addr,
                            changes = broad_changes[addr],
                            decreases = broad_decreases[addr],
                            value = emu:read8(addr),
                        })
                    end
                end
            end
        end
        -- Sort by decrease count (most HP-like behavior)
        table.sort(top_changers, function(a, b) return a.decreases > b.decreases end)
        if #top_changers > 0 then
            log("--- Broad Scan: Top Changers (by decreases) ---")
            log(string.format("  %-12s  %5s  %5s  %5s", "Address", "Value", "Chng", "Decr"))
            for i = 1, math.min(10, #top_changers) do
                local tc = top_changers[i]
                log(string.format("  %s  %5d  %5d  %5d",
                    addrStr(tc.addr), tc.value, tc.changes, tc.decreases))
            end
        else
            log("--- Broad Scan: No changes detected yet ---")
        end
        log("========================================")
    end

    -- Final recommendation after RECOMMENDATION_FRAME frames
    if frame_count >= RECOMMENDATION_FRAME and not recommendation_printed then
        recommendation_printed = true
        log("")
        log("########################################")
        log("### P2 HP ADDRESS RECOMMENDATION ###")
        log("########################################")
        log("")

        if p1_hp_changes == 0 then
            log("[WARNING] P1 HP never changed! The game may not be in an active fight.")
            log("[WARNING] Load a save state during active combat and restart this script.")
            log("")
        end

        -- Score candidates: prefer addresses that decreased and had a reasonable number of changes
        local best_candidate = nil
        local best_score = -1

        for _, c in ipairs(candidates) do
            -- Score = decreases * 2 + changes (reward decreasing more than just changing)
            local score = decrease_counts[c.addr] * 2 + change_counts[c.addr]
            local val = emu:read8(c.addr)
            log(string.format("  %s (%s): changes=%d, decreases=%d, current=%d, score=%d",
                c.name, addrStr(c.addr), change_counts[c.addr], decrease_counts[c.addr], val, score))
            if score > best_score then
                best_score = score
                best_candidate = c
            end
        end

        -- Also check broad scan for any address that outscores all candidates
        local broad_best_addr = nil
        local broad_best_score = -1
        for _, range in ipairs(BROAD_RANGES) do
            for addr = range.start, range.stop - 1 do
                if broad_changes[addr] > 0 then
                    local is_candidate = false
                    for _, c in ipairs(candidates) do
                        if c.addr == addr then is_candidate = true; break end
                    end
                    if not is_candidate and addr ~= P1_HP_ADDR then
                        local score = broad_decreases[addr] * 2 + broad_changes[addr]
                        if score > broad_best_score then
                            broad_best_score = score
                            broad_best_addr = addr
                        end
                    end
                end
            end
        end

        log("")
        if best_score > 0 and best_candidate then
            log(string.format("RECOMMENDATION: Best candidate is %s (%s) with score %d",
                best_candidate.name, addrStr(best_candidate.addr), best_score))
            log(string.format("  Total changes: %d, Decreases: %d",
                change_counts[best_candidate.addr], decrease_counts[best_candidate.addr]))
        else
            log("RECOMMENDATION: No candidate showed HP-like behavior.")
            log("  Make sure you are in an active fight and attacking P2.")
        end

        if broad_best_score > best_score and broad_best_addr then
            log("")
            log(string.format("NOTE: A non-candidate address %s scored higher (%d)!",
                addrStr(broad_best_addr), broad_best_score))
            log("  This address may be the actual P2 HP. Investigate manually.")
        end

        log("")
        log("To use the recommended address, update lua/memory_map.lua:")
        log("  p2_health.addr = <recommended address>")
        log("  p2_health.verified = true")
        log("")
        log("########################################")
        log("### Scanner will continue running... ###")
        log("########################################")
    end
end)

-- Startup message
log("====================================")
log("P2 HP RAM Scanner v1.0")
log("====================================")
log("Monitoring " .. #candidates .. " candidate addresses")
log("Broad scan: 0x03002700-0x03002900 and 0x03004C00-0x03004D00")
log("P1 HP reference: " .. addrStr(P1_HP_ADDR))
log("")
log("INSTRUCTIONS:")
log("  1. Make sure the game is in an active fight")
log("  2. Attack P2 (the enemy) using noVNC controls")
log("  3. Watch for CHANGED messages -- the P2 HP address")
log("     will decrease when P2 takes damage")
log("  4. After " .. RECOMMENDATION_FRAME .. " frames, a recommendation will be printed")
log("")
log("Summary every " .. SUMMARY_INTERVAL .. " frames. Starting scan...")
log("====================================")
