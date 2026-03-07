-- mem_overlay.lua
-- On-screen memory address viewer for mGBA (Qt frontend, 0.11+).
--
-- Draws a translucent overlay on the emulated screen showing live values
-- of all addresses from memory_map.lua.  Used to verify placeholder
-- addresses during RAM discovery:  load the ROM, load this script via
-- --script, play the game, and watch the values change.
--
-- Requires:
--   * mGBA built with USE_FREETYPE (text drawing) and USE_LUA
--   * A TrueType/OpenType font (defaults to the bundled SourceSans3)
--   * canvas, image, callbacks globals (provided by mGBA scripting env)
--
-- Standalone usage (from mgba-qt):
--   mgba-qt --script /data/lua/vis/mem_overlay.lua /data/roms/game.gba
--
-- Or loaded from main.lua:
--   dofile("lua/vis/mem_overlay.lua")

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------
local FONT_PATH  = "/opt/mgba/share/mgba/scripts/demos/SourceSans3-Regular.otf"
local FONT_SIZE  = 8
local BG_COLOR   = 0xC0000000  -- semi-transparent black  (ARGB)
local TEXT_COLOR  = 0xFF00FF00  -- bright green
local LABEL_COLOR = 0xFFFFFF00  -- yellow for labels
local WARN_COLOR  = 0xFFFF4444  -- red for unverified markers
local LINE_HEIGHT = 10          -- pixels between rows
local PAD_X       = 2
local PAD_Y       = 2

---------------------------------------------------------------------------
-- Fallback font search (try several locations)
---------------------------------------------------------------------------
local function findFont()
    local candidates = {
        FONT_PATH,
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    }
    for _, path in ipairs(candidates) do
        local f = io.open(path, "r")
        if f then
            f:close()
            return path
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Detect whether we're running inside mGBA or standalone testing
---------------------------------------------------------------------------
if canvas == nil then
    -- Not running inside mGBA scripting environment.  Print a message
    -- and exit gracefully so require/dofile doesn't crash unit tests.
    print("[mem_overlay] canvas not available -- skipping overlay init")
    print("[mem_overlay] This script must be loaded inside mGBA-Qt")
    return
end

---------------------------------------------------------------------------
-- Memory map -- load inline or from file
---------------------------------------------------------------------------
local MemoryMap
local ok, result = pcall(function()
    return dofile("/data/lua/memory_map.lua")
end)
if ok then
    MemoryMap = result
else
    -- Try relative path (local development)
    ok, result = pcall(function()
        return dofile("lua/memory_map.lua")
    end)
    if ok then
        MemoryMap = result
    end
end

---------------------------------------------------------------------------
-- Build sorted list of addresses to display
---------------------------------------------------------------------------
local entries = {}
if MemoryMap then
    for name, entry in pairs(MemoryMap) do
        if type(entry) == "table" and entry.addr then
            entries[#entries + 1] = {
                name     = name,
                addr     = entry.addr,
                type     = entry.type or "u16",
                size     = entry.size or 2,
                verified = entry.verified or false,
                desc     = entry.desc or "",
            }
        end
    end
    -- Sort by address for consistent display order
    table.sort(entries, function(a, b) return a.addr < b.addr end)
end

---------------------------------------------------------------------------
-- If no memory map loaded, show a default set of test addresses
---------------------------------------------------------------------------
if #entries == 0 then
    console:log("[mem_overlay] No memory_map found; showing sample addresses")
    entries = {
        { name = "p1_ki",       addr = 0x0300274A, type = "u16", verified = true,  desc = "P1 Ki" },
        { name = "round_state", addr = 0x03002826, type = "u8",  verified = true,  desc = "Round" },
        { name = "p1_health",   addr = 0x03002700, type = "u16", verified = false, desc = "P1 HP?" },
        { name = "p2_health",   addr = 0x03002800, type = "u16", verified = false, desc = "P2 HP?" },
    }
end

---------------------------------------------------------------------------
-- Create overlay layer
---------------------------------------------------------------------------
local screenW = canvas:screenWidth()
local screenH = canvas:screenHeight()

-- Overlay covers the right portion of the screen
local overlayW = math.min(180, math.floor(screenW * 0.75))
local overlayH = math.min(PAD_Y * 2 + (#entries + 1) * LINE_HEIGHT, screenH)
local overlayX = screenW - overlayW

local overlay = canvas:newLayer(overlayW, overlayH)
overlay:setPosition(overlayX, 0)

local painter = image.newPainter(overlay.image)

-- Try to load a font for text rendering
local font = findFont()
local hasText = false
if font then
    local fontOk, fontErr = pcall(function()
        painter:loadFont(font)
        painter:setFontSize(FONT_SIZE)
    end)
    if fontOk then
        hasText = true
        console:log("[mem_overlay] Font loaded: " .. font)
    else
        console:log("[mem_overlay] Font load failed: " .. tostring(fontErr))
    end
else
    console:log("[mem_overlay] No font found -- text overlay disabled, using console fallback")
end

---------------------------------------------------------------------------
-- Reading helpers (same logic as memory_map.lua but standalone)
---------------------------------------------------------------------------
local function readAddr(entry)
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
        return emu:read16(entry.addr)
    end
end

---------------------------------------------------------------------------
-- Format a value for display
---------------------------------------------------------------------------
local function fmtValue(val, entry)
    if entry.type == "u8" then
        return string.format("0x%02X (%3d)", val, val)
    elseif entry.type == "s16" then
        if val < 0 then
            return string.format("0x%04X (%d)", val + 0x10000, val)
        else
            return string.format("0x%04X (%d)", val, val)
        end
    elseif entry.type == "u32" then
        return string.format("0x%08X", val)
    else
        return string.format("0x%04X (%5d)", val, val)
    end
end

---------------------------------------------------------------------------
-- Frame update: read memory and redraw overlay
---------------------------------------------------------------------------
local frameCount = 0

local function updateOverlay()
    frameCount = frameCount + 1

    if hasText then
        -- Clear the overlay
        painter:setBlend(false)
        painter:setFill(true)
        painter:setFillColor(BG_COLOR)
        painter:drawRectangle(0, 0, overlayW, overlayH)
        painter:setBlend(true)

        -- Title bar
        painter:setFillColor(LABEL_COLOR)
        painter:setStrokeWidth(0)
        painter:drawText("MEM WATCH  [f:" .. frameCount .. "]", PAD_X, PAD_Y)

        -- Draw each entry
        for i, entry in ipairs(entries) do
            local y = PAD_Y + i * LINE_HEIGHT
            local val = readAddr(entry)
            local vstr = fmtValue(val, entry)

            -- Label color: yellow if verified, red if not
            if entry.verified then
                painter:setFillColor(LABEL_COLOR)
            else
                painter:setFillColor(WARN_COLOR)
            end
            painter:drawText(entry.name .. ":", PAD_X, y)

            -- Value in green
            painter:setFillColor(TEXT_COLOR)
            painter:drawText(vstr, PAD_X + 72, y)
        end

        overlay:update()
    else
        -- Fallback: log to console every 60 frames
        if frameCount % 60 == 0 then
            local lines = {"[mem_overlay] === Frame " .. frameCount .. " ==="}
            for _, entry in ipairs(entries) do
                local val = readAddr(entry)
                local mark = entry.verified and " [OK]" or " [??]"
                lines[#lines + 1] = string.format(
                    "  %-14s @0x%08X = %s%s",
                    entry.name, entry.addr, fmtValue(val, entry), mark
                )
            end
            console:log(table.concat(lines, "\n"))
        end
    end
end

---------------------------------------------------------------------------
-- Register callback
---------------------------------------------------------------------------
callbacks:add("frame", updateOverlay)

console:log("[mem_overlay] Overlay initialized -- watching " .. #entries .. " addresses")
console:log("[mem_overlay] Unverified addresses shown in RED")
