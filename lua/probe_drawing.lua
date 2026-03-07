-- probe_drawing.lua
-- Discover what drawing/overlay APIs mGBA provides.

local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local project_root = script_path:match("^(.*)/lua/probe_drawing%.lua$") or "."

local log_path = project_root .. "/output/probe_drawing.log"
local f = io.open(log_path, "w")
local function log(msg)
    print(msg)
    if f then f:write(msg .. "\n"); f:flush() end
end

log("=== mGBA Drawing API Probe ===")

-- Check global objects
local globals_to_check = {
    "canvas", "screen", "overlay", "gui", "drawing",
    "emu", "console", "callbacks", "C", "socket",
}
for _, name in ipairs(globals_to_check) do
    local val = _G[name]
    log(name .. " = " .. type(val) .. (val and "" or " (nil)"))
end

-- Deep-inspect emu object methods
log("\n--- emu methods ---")
if emu then
    -- Try common method names
    local methods = {
        "createOverlay", "getScreen", "screenBuffer", "setOverlay",
        "drawText", "drawRect", "drawLine", "drawPixel", "fillRect",
        "read8", "read16", "read32", "write8", "write16", "write32",
        "runFrame", "setKeys", "clearKeys", "loadStateFile", "saveStateFile",
        "reset", "pause", "unpause", "screenshot",
    }
    for _, m in ipairs(methods) do
        local ok, val = pcall(function() return emu[m] end)
        if ok and val ~= nil then
            log("  emu." .. m .. " = " .. type(val))
        end
    end
end

-- Deep-inspect console object
log("\n--- console methods ---")
if console then
    local methods = {"log", "warn", "error", "createBuffer"}
    for _, m in ipairs(methods) do
        local ok, val = pcall(function() return console[m] end)
        if ok and val ~= nil then
            log("  console." .. m .. " = " .. type(val))
        end
    end
    -- Try creating a buffer
    local ok, buf = pcall(function() return console:createBuffer("test") end)
    log("  createBuffer: " .. (ok and type(buf) or "FAILED: " .. tostring(buf)))
    if ok and buf then
        log("  buffer type: " .. type(buf))
        -- Probe buffer methods
        local bmethods = {"print", "write", "clear", "setSize", "resize", "moveCursor"}
        for _, m in ipairs(bmethods) do
            local ok2, val = pcall(function() return buf[m] end)
            if ok2 and val ~= nil then
                log("  buf." .. m .. " = " .. type(val))
            end
        end
    end
end

-- Check callbacks
log("\n--- callbacks ---")
if callbacks then
    local types = {"frame", "painted", "keysRead", "reset", "alarm", "shutdown"}
    for _, t in ipairs(types) do
        log("  callback type '" .. t .. "': available (add always works)")
    end
end

-- Check C namespace for drawing constants
log("\n--- C namespace ---")
if C then
    for k, v in pairs(C) do
        log("  C." .. tostring(k) .. " = " .. type(v))
    end
end

-- Try to get screen dimensions
log("\n--- screen info ---")
local ok_w, w = pcall(function() return emu:screenWidth() end)
local ok_h, h = pcall(function() return emu:screenHeight() end)
log("  screenWidth: " .. (ok_w and tostring(w) or "N/A"))
log("  screenHeight: " .. (ok_h and tostring(h) or "N/A"))

log("\n=== Probe Complete ===")
if f then f:close() end
