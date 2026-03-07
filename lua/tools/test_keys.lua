-- test_keys.lua
-- Quick diagnostic to test emu:setKeys() and save state loading.
-- Output goes to /data/output/test_keys.log AND console.

local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local project_root = script_path:match("^(.*)/lua/test_keys%.lua$") or "."

local log_path = project_root .. "/output/test_keys.log"
local f = io.open(log_path, "w")

local function log(msg)
    print(msg)
    if console and console.log then
        console:log(msg)
    end
    if f then
        f:write(msg .. "\n")
        f:flush()
    end
end

log("=== Key and Save State Test ===")

-- Test 1: Check emu object
log("emu type: " .. type(emu))
log("emu.setKeys type: " .. type(emu.setKeys))

-- Test 2: Check C.GBA_KEY constants
local ok1, err1 = pcall(function()
    log("C.GBA_KEY.A = " .. tostring(C.GBA_KEY.A))
    log("C.GBA_KEY.B = " .. tostring(C.GBA_KEY.B))
    log("C.GBA_KEY.L = " .. tostring(C.GBA_KEY.L))
    log("C.GBA_KEY.R = " .. tostring(C.GBA_KEY.R))
    log("C.GBA_KEY.UP = " .. tostring(C.GBA_KEY.UP))
    log("C.GBA_KEY.DOWN = " .. tostring(C.GBA_KEY.DOWN))
    log("C.GBA_KEY.LEFT = " .. tostring(C.GBA_KEY.LEFT))
    log("C.GBA_KEY.RIGHT = " .. tostring(C.GBA_KEY.RIGHT))
end)
if not ok1 then log("C.GBA_KEY error: " .. tostring(err1)) end

-- Test 3: Try setKeys with different values
for _, val in ipairs({0, 1, 2, 3, 0x10, 0x40, 0x100, 0x200, 0xFF, 0x3FF}) do
    local ok, err = pcall(function() emu:setKeys(val) end)
    log(string.format("setKeys(0x%X): %s", val, ok and "OK" or tostring(err)))
end

-- Test 4: Try clearKeys
local ok2, err2 = pcall(function() emu:clearKeys(0x3FF) end)
log("clearKeys(0x3FF): " .. (ok2 and "OK" or tostring(err2)))

-- Test 5: Check save state file
local ss_path = project_root .. "/savestates/fight_start.ss0"
local ss = io.open(ss_path, "r")
log("Save state at " .. ss_path .. ": " .. (ss and "EXISTS" or "NOT FOUND"))
if ss then ss:close() end

-- Test 6: Try loading save state
local ok3, err3 = pcall(function()
    emu:loadStateFile(ss_path)
end)
log("loadStateFile: " .. (ok3 and "OK" or tostring(err3)))

log("=== Test Complete ===")
if f then f:close() end
