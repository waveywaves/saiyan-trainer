-- check_states.lua
-- Quick diagnostic: load each save state and report key memory values.

local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local project_root = script_path:match("^(.*)/lua/check_states%.lua$") or "."
if project_root ~= "." then
    local _dofile = dofile
    dofile = function(path)
        if path:sub(1, 1) ~= "/" then return _dofile(project_root .. "/" .. path) end
        return _dofile(path)
    end
end

local mm = dofile("lua/memory_map.lua")
local log_path = project_root .. "/output/check_states.log"
local f = io.open(log_path, "w")

local function log(msg)
    print(msg)
    if f then f:write(msg .. "\n"); f:flush() end
end

local states_dir = project_root .. "/savestates/"
local files = {"fight_start.ss0", "no_cpu_training_state.ss0"}

for _, filename in ipairs(files) do
    local path = states_dir .. filename
    local fh = io.open(path, "r")
    if fh then
        fh:close()
        emu:loadStateFile(path)
        log("=== " .. filename .. " ===")
        log("  P1 HP:        " .. mm.read(mm.p1_health) .. " / " .. mm.read(mm.p1_health_max))
        log("  P2 HP:        " .. mm.read(mm.p2_health))
        log("  P1 Ki:        " .. mm.read(mm.p1_ki) .. " (int: " .. mm.read(mm.p1_ki_int) .. ")")
        log("  P2 Ki:        " .. mm.read(mm.p2_ki))
        log("  P1 Power:     " .. mm.read(mm.p1_power_level))
        log("  Round State:  " .. mm.read(mm.round_state))
        log("  Timer:        " .. mm.read(mm.timer))
        log("  Dist X:       " .. mm.read(mm.dist_x))
        log("  Dist Y:       " .. mm.read(mm.dist_y))
        log("  Polar Dir:    " .. mm.read(mm.polar_dir))
        log("")
    else
        log("=== " .. filename .. " === NOT FOUND")
    end
end

log("Done.")
if f then f:close() end
