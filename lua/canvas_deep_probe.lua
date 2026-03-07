-- canvas_deep_probe.lua
-- Exhaustive probe of every possible way to draw pixels on the mGBA game screen overlay.
-- Writes results to /data/output/canvas_deep_probe.log (or project_root/output/...).

local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local project_root = script_path:match("^(.*)/lua/canvas_deep_probe%.lua$") or "."

-- Patch dofile for project-relative paths
if project_root ~= "." then
    local _dofile = dofile
    dofile = function(path)
        if path:sub(1, 1) ~= "/" then
            return _dofile(project_root .. "/" .. path)
        end
        return _dofile(path)
    end
end

os.execute("mkdir -p " .. project_root .. "/output")
local log_path = project_root .. "/output/canvas_deep_probe.log"
local f = io.open(log_path, "w")

local section_count = 0
local pass_count = 0
local fail_count = 0
local discovery_count = 0

local function log(msg)
    local line = msg or ""
    print(line)
    if f then f:write(line .. "\n"); f:flush() end
end

local function section(title)
    section_count = section_count + 1
    log("")
    log(string.format("=== [%02d] %s ===", section_count, title))
end

local function try(label, fn)
    local ok, result = pcall(fn)
    if ok then
        pass_count = pass_count + 1
        local msg = "  [OK]   " .. label
        if result ~= nil then
            msg = msg .. " => " .. tostring(result)
        end
        log(msg)
        return true, result
    else
        fail_count = fail_count + 1
        log("  [FAIL] " .. label .. " => " .. tostring(result))
        return false, result
    end
end

local function discovery(msg)
    discovery_count = discovery_count + 1
    log("  [DISCOVERY] " .. msg)
end

-- Helper: enumerate all keys of a userdata/table via pairs, ipairs, and brute-force
local function enumerate_keys(obj, label)
    log("  Enumerating keys of " .. label .. " (type=" .. type(obj) .. "):")

    -- Try pairs
    local pairs_ok, pairs_err = pcall(function()
        local count = 0
        for k, v in pairs(obj) do
            log("    pairs: " .. tostring(k) .. " = " .. type(v) .. " (" .. tostring(v) .. ")")
            count = count + 1
        end
        if count == 0 then
            log("    pairs: (empty)")
        end
    end)
    if not pairs_ok then
        log("    pairs() failed: " .. tostring(pairs_err))
    end

    -- Try ipairs
    local ipairs_ok, _ = pcall(function()
        local count = 0
        for i, v in ipairs(obj) do
            log("    ipairs[" .. i .. "] = " .. type(v) .. " (" .. tostring(v) .. ")")
            count = count + 1
            if count > 20 then log("    ipairs: (truncated)"); break end
        end
    end)
    if not ipairs_ok then
        log("    ipairs() not supported")
    end
end

-- Helper: dump metatable
local function dump_metatable(obj, label)
    log("  Metatable of " .. label .. ":")
    local mt = getmetatable(obj)
    if mt == nil then
        log("    (no metatable)")
        return nil
    end
    log("    metatable type: " .. type(mt))
    if type(mt) == "table" then
        for k, v in pairs(mt) do
            log("    mt." .. tostring(k) .. " = " .. type(v))
            if type(v) == "table" then
                for k2, v2 in pairs(v) do
                    log("      ." .. tostring(k2) .. " = " .. type(v2))
                end
            end
        end
    elseif type(mt) == "string" then
        log("    metatable is string: " .. mt)
    else
        log("    metatable is: " .. tostring(mt))
    end
    return mt
end

log("############################################################")
log("#  mGBA Canvas Deep Probe - Exhaustive Overlay Investigation")
log("#  " .. os.date("%Y-%m-%d %H:%M:%S"))
log("#  project_root: " .. project_root)
log("############################################################")

------------------------------------------------------------------------
section("Canvas object existence and type")
------------------------------------------------------------------------
local has_canvas = false
try("canvas exists", function()
    assert(canvas ~= nil, "canvas is nil")
    has_canvas = true
    return type(canvas)
end)

if has_canvas then
    try("canvas type", function() return type(canvas) end)
    try("tostring(canvas)", function() return tostring(canvas) end)
end

------------------------------------------------------------------------
section("Canvas metatable deep inspection")
------------------------------------------------------------------------
if has_canvas then
    dump_metatable(canvas, "canvas")

    -- Try to get the metatable's __index (common pattern for C++ userdata)
    try("getmetatable(canvas).__index", function()
        local mt = getmetatable(canvas)
        if mt and mt.__index then
            log("    __index type: " .. type(mt.__index))
            if type(mt.__index) == "table" then
                for k, v in pairs(mt.__index) do
                    log("      __index." .. tostring(k) .. " = " .. type(v))
                    discovery("canvas has method via __index: " .. tostring(k))
                end
            end
            return tostring(mt.__index)
        end
        return "no __index"
    end)

    -- Try debug.getmetatable (bypasses __metatable)
    try("debug.getmetatable(canvas)", function()
        local mt = debug.getmetatable(canvas)
        if mt and type(mt) == "table" then
            for k, v in pairs(mt) do
                log("      debug_mt." .. tostring(k) .. " = " .. type(v))
            end
        end
        return tostring(mt)
    end)

    enumerate_keys(canvas, "canvas")
end

------------------------------------------------------------------------
section("Canvas known methods: width, height, screenWidth, screenHeight, update")
------------------------------------------------------------------------
if has_canvas then
    try("canvas:width()", function() return canvas:width() end)
    try("canvas:height()", function() return canvas:height() end)
    try("canvas:screenWidth()", function() return canvas:screenWidth() end)
    try("canvas:screenHeight()", function() return canvas:screenHeight() end)
    try("canvas:update()", function() canvas:update(); return "called" end)
end

------------------------------------------------------------------------
section("Canvas drawing method probes (drawImage, drawText, drawRect, etc.)")
------------------------------------------------------------------------
if has_canvas then
    local draw_methods = {
        "drawImage", "drawPixel", "drawText", "drawRect", "drawRectangle",
        "drawLine", "drawCircle", "drawEllipse", "drawArc", "drawPolygon",
        "drawPoint", "drawPath", "drawPicture",
        "fillRect", "fillRectangle", "fillCircle", "fillEllipse",
        "fill", "clear", "clearRect",
        "setPixel", "putPixel", "plot",
        "blit", "bitBlt", "copyFrom", "paste", "stamp",
        "setImage", "putImage", "blitImage", "pasteImage", "overlayImage",
        "render", "compose", "composite",
        "setOverlay", "addOverlay", "overlay",
        "newLayer", "addLayer", "createLayer", "getLayer", "layer",
        "setPen", "setBrush", "setFont", "setColor", "setBackground",
        "begin", "beginPaint", "endPaint",
        "paint", "repaint", "requestPaint", "requestUpdate",
        "flush", "sync", "present", "show", "display",
        "setOpacity", "setAlpha", "setTransparency",
        "resize", "setSize", "scale",
        "save", "restore", "reset",
        "lock", "unlock",
        "toImage", "fromImage", "getImage",
        "grab", "snapshot", "capture",
        "setAttribute", "setProperty",
        "paintEngine", "paintDevice",
    }
    for _, m in ipairs(draw_methods) do
        local ok, val = pcall(function() return canvas[m] end)
        if ok and val ~= nil then
            discovery("canvas." .. m .. " exists (" .. type(val) .. ")")
            log("  [FOUND] canvas." .. m .. " = " .. type(val))
        end
    end
end

------------------------------------------------------------------------
section("Canvas as image: try setPixel directly")
------------------------------------------------------------------------
if has_canvas then
    -- Various color formats
    local colors = {0xFFFF0000, 0xFF0000, 0xFF00FF00, 1, 255}
    for _, color in ipairs(colors) do
        try(string.format("canvas:setPixel(10, 10, 0x%X)", color), function()
            canvas:setPixel(10, 10, color)
            return "called"
        end)
    end

    try("canvas:drawPixel(10, 10, 0xFFFF0000)", function()
        canvas:drawPixel(10, 10, 0xFFFF0000)
        return "called"
    end)

    try("canvas:plot(10, 10, 0xFFFF0000)", function()
        canvas:plot(10, 10, 0xFFFF0000)
        return "called"
    end)
end

------------------------------------------------------------------------
section("Canvas property probes (image, layer, overlay, buffer, etc.)")
------------------------------------------------------------------------
if has_canvas then
    local props = {
        "image", "layer", "overlay", "buffer", "surface",
        "pixmap", "bitmap", "backBuffer", "frontBuffer",
        "screen", "display", "framebuffer", "fb",
        "painter", "context", "gc",
        "data", "pixels", "raw",
        "parent", "widget", "window",
        "opacity", "alpha", "visible", "enabled",
        "format", "depth", "bpp",
        "stride", "pitch", "rowBytes",
    }
    for _, p in ipairs(props) do
        local ok, val = pcall(function() return canvas[p] end)
        if ok and val ~= nil then
            discovery("canvas." .. p .. " = " .. type(val) .. " (" .. tostring(val) .. ")")
        end
    end
end

------------------------------------------------------------------------
section("Canvas setAttribute / setProperty probes")
------------------------------------------------------------------------
if has_canvas then
    -- Try setAttribute with an image
    local img_ok, img = pcall(function() return image.new(240, 160) end)
    if img_ok and img then
        try("canvas:setAttribute('image', img)", function()
            canvas:setAttribute("image", img)
            return "called"
        end)
        try("canvas:setProperty('image', img)", function()
            canvas:setProperty("image", img)
            return "called"
        end)
        try("canvas:setImage(img)", function()
            canvas:setImage(img)
            return "called"
        end)
        try("canvas:setOverlay(img)", function()
            canvas:setOverlay(img)
            return "called"
        end)
        try("canvas:drawImage(img, 0, 0)", function()
            canvas:drawImage(img, 0, 0)
            return "called"
        end)
        try("canvas:drawImage(img)", function()
            canvas:drawImage(img)
            return "called"
        end)
        try("canvas:blit(img, 0, 0)", function()
            canvas:blit(img, 0, 0)
            return "called"
        end)
        try("canvas:bitBlt(img, 0, 0)", function()
            canvas:bitBlt(img, 0, 0)
            return "called"
        end)
        try("canvas:paste(img, 0, 0)", function()
            canvas:paste(img, 0, 0)
            return "called"
        end)
        try("canvas:stamp(img, 0, 0)", function()
            canvas:stamp(img, 0, 0)
            return "called"
        end)
        try("canvas:composite(img, 0, 0)", function()
            canvas:composite(img, 0, 0)
            return "called"
        end)
    end
end

------------------------------------------------------------------------
section("Image module deep probe")
------------------------------------------------------------------------
local img = nil
try("image global exists", function()
    assert(image ~= nil, "image is nil")
    return type(image)
end)

if image then
    log("  Enumerating image module:")
    local img_ok
    img_ok, _ = pcall(function()
        for k, v in pairs(image) do
            log("    image." .. tostring(k) .. " = " .. type(v))
            discovery("image module has: " .. tostring(k))
        end
    end)
    if not img_ok then
        log("    pairs(image) failed")
    end

    -- Try different constructors
    local constructors = {"new", "create", "load", "open", "fromFile", "fromData", "blank"}
    for _, c in ipairs(constructors) do
        local ok, val = pcall(function() return image[c] end)
        if ok and val ~= nil then
            log("  [FOUND] image." .. c .. " = " .. type(val))
        end
    end

    -- Create an image
    try("image.new(240, 160)", function()
        img = image.new(240, 160)
        return type(img) .. " " .. tostring(img)
    end)

    -- Try other sizes
    try("image.new(1, 1)", function()
        local tiny = image.new(1, 1)
        return type(tiny)
    end)
end

------------------------------------------------------------------------
section("Image object method exhaustive probe")
------------------------------------------------------------------------
if img then
    dump_metatable(img, "image object")
    enumerate_keys(img, "image object")

    local img_methods = {
        -- Pixel access
        "setPixel", "getPixel", "putPixel", "pixel",
        -- Drawing primitives
        "drawText", "drawString", "text", "print",
        "drawRect", "drawRectangle", "rect", "rectangle",
        "drawLine", "line",
        "drawCircle", "circle", "drawEllipse", "ellipse",
        "drawArc", "arc",
        "drawPolygon", "polygon",
        "drawPoint", "point",
        "drawImage", "blit", "bitBlt", "paste", "stamp", "composite",
        "fillRect", "fillRectangle", "fillCircle", "fillEllipse",
        "fill", "floodFill",
        "clear",
        -- Dimension
        "width", "height", "size", "getSize",
        -- I/O
        "save", "load", "tostring", "export",
        -- QPainter-style
        "begin", "end", "setPen", "setBrush", "setFont", "setColor",
        "setBackground", "setOpacity", "setAlpha",
        -- Conversion
        "toCanvas", "toOverlay", "toScreen",
        "copy", "clone", "duplicate", "scaled", "resize",
        "data", "raw", "pixels", "buffer",
        "format", "depth", "bpp",
        -- Misc
        "setAttribute", "setProperty",
        "lock", "unlock",
    }
    for _, m in ipairs(img_methods) do
        local ok, val = pcall(function() return img[m] end)
        if ok and val ~= nil then
            discovery("image." .. m .. " exists (" .. type(val) .. ")")
            log("  [FOUND] img." .. m .. " = " .. type(val))
        end
    end

    -- Test actual pixel operations
    try("img:setPixel(0, 0, 0xFFFF0000)", function()
        img:setPixel(0, 0, 0xFFFF0000)
        return "called"
    end)

    try("img:getPixel(0, 0) after setPixel", function()
        local px = img:getPixel(0, 0)
        return string.format("0x%08X", px)
    end)

    -- Paint a visible rectangle via setPixel
    try("paint 10x10 red block via setPixel", function()
        for y = 0, 9 do
            for x = 0, 9 do
                img:setPixel(x, y, 0xFFFF0000)
            end
        end
        return "painted"
    end)

    try("img:width()", function() return img:width() end)
    try("img:height()", function() return img:height() end)

    -- Try saving to verify image works
    try("img:save(png path)", function()
        img:save(project_root .. "/output/canvas_probe_test.png")
        return "saved"
    end)
end

------------------------------------------------------------------------
section("Pushing image to canvas (all known approaches)")
------------------------------------------------------------------------
if has_canvas and img then
    -- Paint the full image red so any display would be visible
    pcall(function()
        for y = 0, 19 do
            for x = 0, 29 do
                img:setPixel(x, y, 0xFFFF0000)
            end
        end
    end)

    -- Approach 1: canvas:drawImage variants
    local draw_variants = {
        {"canvas:drawImage(img, 0, 0)", function() canvas:drawImage(img, 0, 0) end},
        {"canvas:drawImage(img, 0, 0, 240, 160)", function() canvas:drawImage(img, 0, 0, 240, 160) end},
        {"canvas:drawImage(img)", function() canvas:drawImage(img) end},
        {"canvas:setImage(img)", function() canvas:setImage(img) end},
        {"canvas:putImage(img, 0, 0)", function() canvas:putImage(img, 0, 0) end},
        {"canvas:blitImage(img, 0, 0)", function() canvas:blitImage(img, 0, 0) end},
        {"canvas:overlayImage(img, 0, 0)", function() canvas:overlayImage(img, 0, 0) end},
        {"canvas:compose(img, 0, 0)", function() canvas:compose(img, 0, 0) end},
        {"canvas:render(img, 0, 0)", function() canvas:render(img, 0, 0) end},
    }
    for _, v in ipairs(draw_variants) do
        try(v[1], v[2])
    end

    -- Approach 2: update after each attempt
    try("canvas:update() after draw attempts", function()
        canvas:update()
        return "called"
    end)
end

------------------------------------------------------------------------
section("Canvas as layer / multi-canvas probes")
------------------------------------------------------------------------
if has_canvas then
    local layer_methods = {
        {"canvas:newLayer()", function() return canvas:newLayer() end},
        {"canvas:addOverlay()", function() return canvas:addOverlay() end},
        {"canvas:createOverlay()", function() return canvas:createOverlay() end},
        {"canvas:createCanvas()", function() return canvas:createCanvas() end},
        {"canvas:addLayer()", function() return canvas:addLayer() end},
        {"canvas:addLayer('overlay')", function() return canvas:addLayer("overlay") end},
        {"canvas:getLayer(0)", function() return canvas:getLayer(0) end},
        {"canvas:getLayer(1)", function() return canvas:getLayer(1) end},
        {"canvas:layer(0)", function() return canvas:layer(0) end},
    }
    for _, v in ipairs(layer_methods) do
        local ok, result = try(v[1], v[2])
        if ok and result ~= nil then
            discovery("layer/overlay creation returned: " .. type(result) .. " = " .. tostring(result))
            -- Probe the returned object
            dump_metatable(result, v[1] .. " result")
        end
    end
end

------------------------------------------------------------------------
section("emu:screenshot() probe")
------------------------------------------------------------------------
local screenshot = nil
try("emu:screenshot()", function()
    screenshot = emu:screenshot()
    return type(screenshot) .. " " .. tostring(screenshot)
end)

if screenshot then
    log("  screenshot returned a " .. type(screenshot))
    dump_metatable(screenshot, "screenshot result")
    enumerate_keys(screenshot, "screenshot result")

    -- Is it an image we can draw on?
    local ss_methods = {
        "setPixel", "getPixel", "width", "height", "save",
        "drawText", "drawRect", "drawLine",
        "data", "buffer", "pixels",
    }
    for _, m in ipairs(ss_methods) do
        local ok, val = pcall(function() return screenshot[m] end)
        if ok and val ~= nil then
            discovery("screenshot." .. m .. " = " .. type(val))
        end
    end

    try("screenshot:width()", function() return screenshot:width() end)
    try("screenshot:height()", function() return screenshot:height() end)
    try("screenshot:getPixel(0, 0)", function()
        local px = screenshot:getPixel(0, 0)
        return string.format("0x%08X", px)
    end)

    -- Can we modify and push back?
    try("screenshot:setPixel(0, 0, 0xFFFF0000)", function()
        screenshot:setPixel(0, 0, 0xFFFF0000)
        return "called"
    end)

    -- Try to push modified screenshot back to canvas
    if has_canvas then
        try("canvas:drawImage(screenshot, 0, 0)", function()
            canvas:drawImage(screenshot, 0, 0)
            return "called"
        end)
        try("canvas:setImage(screenshot)", function()
            canvas:setImage(screenshot)
            return "called"
        end)
        try("canvas:update() after screenshot push", function()
            canvas:update()
            return "called"
        end)
    end

    -- Save screenshot to verify
    try("screenshot:save(png path)", function()
        screenshot:save(project_root .. "/output/canvas_probe_screenshot.png")
        return "saved"
    end)
end

------------------------------------------------------------------------
section("Painted callback probe")
------------------------------------------------------------------------
-- Register a painted callback and try drawing inside it
local painted_log_lines = {}
local painted_fired = false

try("callbacks:add('painted', fn)", function()
    callbacks:add("painted", function()
        if painted_fired then return end
        painted_fired = true

        local results = {}
        local function plog(msg)
            table.insert(results, msg)
        end

        plog("painted callback FIRED")

        -- Inside painted callback, try drawing to canvas
        if has_canvas then
            local ok1, err1 = pcall(function() canvas:update() end)
            plog("  canvas:update() inside painted: " .. (ok1 and "OK" or tostring(err1)))

            local ok2, err2 = pcall(function() canvas:setPixel(5, 5, 0xFFFF0000) end)
            plog("  canvas:setPixel inside painted: " .. (ok2 and "OK" or tostring(err2)))

            local ok3, err3 = pcall(function() canvas:drawImage(img, 0, 0) end)
            plog("  canvas:drawImage inside painted: " .. (ok3 and "OK" or tostring(err3)))

            -- Try all canvas methods again in painted context
            local paint_methods = {
                "drawText", "drawRect", "drawLine", "drawPixel",
                "fillRect", "clear", "blit", "paste",
                "setImage", "putImage", "overlayImage",
            }
            for _, m in ipairs(paint_methods) do
                local ok_m, val_m = pcall(function() return canvas[m] end)
                if ok_m and val_m ~= nil then
                    plog("  canvas." .. m .. " available in painted: " .. type(val_m))
                end
            end
        end

        -- Try to get a QPainter or similar context in the callback
        local ok_p, painter = pcall(function() return canvas:begin() end)
        plog("  canvas:begin() in painted: " .. (ok_p and type(painter) or "FAIL"))
        if ok_p and painter then
            plog("  PAINTER OBJECT FOUND IN PAINTED CALLBACK!")
            dump_metatable(painter, "painter from painted callback")
        end

        painted_log_lines = results
    end)
    return "registered"
end)

------------------------------------------------------------------------
section("Frame callback with canvas draw attempts")
------------------------------------------------------------------------
local frame_draw_tested = false

try("callbacks:add('frame', draw-test fn)", function()
    callbacks:add("frame", function()
        if frame_draw_tested then return end
        frame_draw_tested = true

        local results = {}
        local function flog(msg)
            table.insert(results, msg)
        end

        flog("frame callback FIRED - attempting draws")

        if has_canvas then
            local draw_tests = {
                {"setPixel(50,50,red)", function() canvas:setPixel(50, 50, 0xFFFF0000) end},
                {"drawPixel(50,50,red)", function() canvas:drawPixel(50, 50, 0xFFFF0000) end},
                {"drawText(10,10,'HI')", function() canvas:drawText(10, 10, "HI") end},
                {"drawRect(10,10,50,30)", function() canvas:drawRect(10, 10, 50, 30) end},
                {"drawLine(0,0,100,100)", function() canvas:drawLine(0, 0, 100, 100) end},
                {"fillRect(10,10,50,30)", function() canvas:fillRect(10, 10, 50, 30) end},
                {"clear()", function() canvas:clear() end},
                {"update()", function() canvas:update() end},
            }
            for _, t in ipairs(draw_tests) do
                local ok, err = pcall(t[2])
                flog("  " .. t[1] .. ": " .. (ok and "OK" or tostring(err)))
            end

            -- If we have an image, try drawing it in frame callback
            if img then
                local ok, err = pcall(function() canvas:drawImage(img, 0, 0) end)
                flog("  drawImage in frame: " .. (ok and "OK" or tostring(err)))
                pcall(function() canvas:update() end)
            end
        end

        -- Write frame callback results to log after a delay
        -- (We can't use the log function directly since the file handle
        --  might have issues, so we store and flush later)
        local ff = io.open(log_path, "a")
        if ff then
            ff:write("\n=== [DEFERRED] Frame callback draw results ===\n")
            for _, line in ipairs(results) do
                ff:write(line .. "\n")
            end

            -- Also write painted callback results if available
            if #painted_log_lines > 0 then
                ff:write("\n=== [DEFERRED] Painted callback results ===\n")
                for _, line in ipairs(painted_log_lines) do
                    ff:write(line .. "\n")
                end
            end
            ff:flush()
            ff:close()
        end
    end)
    return "registered"
end)

------------------------------------------------------------------------
section("Global namespace scan for drawing-related objects")
------------------------------------------------------------------------
local interesting_globals = {
    "canvas", "screen", "overlay", "gui", "drawing", "gfx", "graphics",
    "painter", "render", "renderer", "display", "video", "vram",
    "image", "sprite", "texture", "surface", "pixmap", "bitmap",
    "emu", "console", "callbacks", "C", "socket", "util",
    "mGBA", "mgba", "core", "gba", "arm",
}
for _, name in ipairs(interesting_globals) do
    local val = _G[name]
    if val ~= nil then
        log("  _G." .. name .. " = " .. type(val))
        discovery("Global object exists: " .. name)
    end
end

-- Also scan ALL globals
log("")
log("  Full _G scan (non-standard entries):")
local standard = {
    "string", "table", "math", "io", "os", "debug", "coroutine", "package",
    "print", "type", "tostring", "tonumber", "pairs", "ipairs", "next",
    "select", "unpack", "pcall", "xpcall", "error", "assert",
    "rawget", "rawset", "rawequal", "rawlen",
    "setmetatable", "getmetatable",
    "require", "dofile", "loadfile", "load", "loadstring",
    "collectgarbage", "gcinfo",
    "_VERSION", "_G", "arg",
    "setfenv", "getfenv", "newproxy", "module",
}
local standard_set = {}
for _, s in ipairs(standard) do standard_set[s] = true end

local ok_g, _ = pcall(function()
    for k, v in pairs(_G) do
        if not standard_set[tostring(k)] then
            log("    _G." .. tostring(k) .. " = " .. type(v))
        end
    end
end)
if not ok_g then
    log("    (could not enumerate _G)")
end

------------------------------------------------------------------------
section("C namespace deep scan for drawing/overlay constants")
------------------------------------------------------------------------
if C then
    local ok_c, _ = pcall(function()
        for k, v in pairs(C) do
            log("  C." .. tostring(k) .. " = " .. type(v))
            if type(v) == "table" then
                local count = 0
                for k2, v2 in pairs(v) do
                    if count < 10 then
                        log("    C." .. tostring(k) .. "." .. tostring(k2) .. " = " .. tostring(v2))
                    end
                    count = count + 1
                end
                if count > 10 then
                    log("    ... (" .. count .. " entries total)")
                end
            end
        end
    end)
    if not ok_c then
        log("  (could not enumerate C)")
    end
end

------------------------------------------------------------------------
section("emu object deep method scan")
------------------------------------------------------------------------
if emu then
    dump_metatable(emu, "emu")

    local emu_methods = {
        -- Known working
        "read8", "read16", "read32", "write8", "write16", "write32",
        "runFrame", "setKeys", "clearKeys",
        "loadStateFile", "saveStateFile", "reset", "screenshot",
        -- Drawing / overlay candidates
        "createOverlay", "getOverlay", "setOverlay", "overlay",
        "getScreen", "getCanvas", "getDisplay",
        "screenBuffer", "frameBuffer",
        "drawText", "drawRect", "drawLine", "drawPixel",
        "fillRect", "clear",
        "setOverlayImage", "getScreenImage",
        "setPixel", "getPixel",
        -- Video / rendering
        "getVideoBuffer", "setVideoBuffer",
        "getFrameBuffer", "setFrameBuffer",
        "refreshScreen", "updateScreen",
        "pause", "unpause", "isPaused",
        -- State
        "saveState", "loadState",
        "memory", "getMemory",
    }
    for _, m in ipairs(emu_methods) do
        local ok, val = pcall(function() return emu[m] end)
        if ok and val ~= nil then
            log("  [FOUND] emu." .. m .. " = " .. type(val))
            if type(val) == "function" and m ~= "runFrame" and m ~= "reset" then
                discovery("emu." .. m .. " is callable")
            end
        end
    end
end

------------------------------------------------------------------------
section("emu:screenshot() -> modify -> display pipeline")
------------------------------------------------------------------------
-- Full pipeline test: screenshot, modify, try to display
try("full screenshot pipeline", function()
    local ss = emu:screenshot()
    assert(ss, "screenshot returned nil")

    local w = ss:width()
    local h = ss:height()
    log("    screenshot dimensions: " .. w .. "x" .. h)

    -- Draw a red border on the screenshot
    for x = 0, w - 1 do
        ss:setPixel(x, 0, 0xFFFF0000)
        ss:setPixel(x, h - 1, 0xFFFF0000)
    end
    for y = 0, h - 1 do
        ss:setPixel(0, y, 0xFFFF0000)
        ss:setPixel(w - 1, y, 0xFFFF0000)
    end

    -- Try every known method to push it to display
    local push_methods = {
        function() canvas:drawImage(ss, 0, 0) end,
        function() canvas:setImage(ss) end,
        function() canvas:blit(ss, 0, 0) end,
        function() canvas:paste(ss, 0, 0) end,
        function() canvas:overlayImage(ss, 0, 0) end,
        function() emu:setOverlay(ss) end,
        function() emu:setOverlayImage(ss) end,
        function() emu:setVideoBuffer(ss) end,
    }
    local any_worked = false
    for i, fn in ipairs(push_methods) do
        local ok, err = pcall(fn)
        if ok then
            any_worked = true
            log("    push method " .. i .. " succeeded!")
        end
    end

    pcall(function() canvas:update() end)
    ss:save(project_root .. "/output/canvas_probe_modified_ss.png")

    if any_worked then
        return "at least one push method worked!"
    else
        return "no push methods worked, but screenshot was captured and saved"
    end
end)

------------------------------------------------------------------------
section("Image -> canvas pixel-copy brute force")
------------------------------------------------------------------------
-- If canvas:setPixel works, we could manually copy image pixels to canvas
if has_canvas and img then
    try("brute force: copy image pixels to canvas via setPixel", function()
        -- Paint a small test pattern on the image
        for y = 0, 4 do
            for x = 0, 4 do
                img:setPixel(x, y, 0xFFFF0000)
            end
        end

        -- Try to copy pixel by pixel to canvas
        local copied = false
        for y = 0, 4 do
            for x = 0, 4 do
                local px = img:getPixel(x, y)
                canvas:setPixel(x, y, px) -- will throw if not supported
                copied = true
            end
        end
        canvas:update()
        return copied and "copied 25 pixels!" or "no pixels copied"
    end)
end

------------------------------------------------------------------------
section("Alternate global image/canvas constructors")
------------------------------------------------------------------------
-- Maybe there are other factory functions
local factory_attempts = {
    {"canvas.new(240,160)", function() return canvas.new(240, 160) end},
    {"canvas.create(240,160)", function() return canvas.create(240, 160) end},
    {"Canvas(240,160)", function() return Canvas(240, 160) end},
    {"Overlay(240,160)", function() return Overlay(240, 160) end},
    {"Surface(240,160)", function() return Surface(240, 160) end},
    {"Painter(canvas)", function() return Painter(canvas) end},
    {"image.load(path)", function() return image.load(project_root .. "/output/canvas_probe_test.png") end},
    {"image.fromCanvas(canvas)", function() return image.fromCanvas(canvas) end},
}
for _, v in ipairs(factory_attempts) do
    local ok, result = try(v[1], v[2])
    if ok and result ~= nil then
        discovery("Factory " .. v[1] .. " returned " .. type(result))
        dump_metatable(result, v[1] .. " result")
    end
end

------------------------------------------------------------------------
section("image.new -> canvas-sized, paint, save for verification")
------------------------------------------------------------------------
if image then
    try("create canvas-sized image (240x160), paint checkerboard, save", function()
        local test_img = image.new(240, 160)
        -- Paint a checkerboard pattern
        for y = 0, 159 do
            for x = 0, 239 do
                if (math.floor(x / 16) + math.floor(y / 16)) % 2 == 0 then
                    test_img:setPixel(x, y, 0xFFFF0000) -- red
                else
                    test_img:setPixel(x, y, 0xFF0000FF) -- blue
                end
            end
        end
        test_img:save(project_root .. "/output/canvas_probe_checkerboard.png")
        return "saved checkerboard"
    end)
end

------------------------------------------------------------------------
section("mGBA source-informed probes (ScriptingController API)")
------------------------------------------------------------------------
-- Based on mGBA source code, the scripting API might expose these
if has_canvas then
    -- mGBA scripting canvas is mScriptPainter in source
    -- Try methods from src/script/engines/lua.c and src/script/types/canvas.c
    local source_methods = {
        -- From mScriptCanvasContext
        "setSize", "setLayerCount",
        "layerCount", "contentSize",
        -- From mScriptPainter
        "drawRectangle", "drawLine", "drawCircle", "drawText",
        "fillRectangle", "fillCircle",
        "setFillColor", "setStrokeColor", "setStrokeWidth",
        "setFont", "setFontSize",
        "setBlendMode", "pushTransform", "popTransform",
        "translate", "rotate", "scale",
        "save", "restore",
        -- Layer management
        "setLayer", "getLayer",
        -- Lifecycle
        "lock", "unlock", "needsRedraw",
    }
    log("  Probing mGBA source-informed methods on canvas:")
    for _, m in ipairs(source_methods) do
        local ok, val = pcall(function() return canvas[m] end)
        if ok and val ~= nil then
            discovery("canvas." .. m .. " = " .. type(val) .. " (SOURCE-INFORMED)")
            log("  [FOUND] canvas." .. m .. " = " .. type(val))

            -- Try calling parameterless getters
            if type(val) == "function" and (m == "layerCount" or m == "contentSize" or m == "needsRedraw") then
                local ok2, result2 = pcall(function() return canvas[m](canvas) end)
                if ok2 then
                    log("    canvas:" .. m .. "() = " .. tostring(result2))
                end
            end
        end
    end

    -- Try color-setting then drawing
    try("canvas:setFillColor(0xFFFF0000) then drawRectangle", function()
        canvas:setFillColor(0xFFFF0000)
        canvas:drawRectangle(10, 10, 50, 30)
        canvas:update()
        return "called"
    end)

    try("canvas:setStrokeColor(0xFF00FF00) then drawLine", function()
        canvas:setStrokeColor(0xFF00FF00)
        canvas:drawLine(0, 0, 100, 100)
        canvas:update()
        return "called"
    end)

    try("canvas:drawText(10, 10, 'PROBE')", function()
        canvas:drawText(10, 10, "PROBE")
        canvas:update()
        return "called"
    end)
end

------------------------------------------------------------------------
section("Comprehensive callback type probe")
------------------------------------------------------------------------
if callbacks then
    local cb_types = {
        "frame", "painted", "keysRead", "reset", "alarm", "shutdown",
        "crashed", "sleep", "wake",
        "start", "stop", "pause", "unpause",
        "draw", "render", "display", "paint", "overlay",
        "postFrame", "preFrame", "postPaint", "prePaint",
    }
    for _, t in ipairs(cb_types) do
        local ok, err = pcall(function()
            callbacks:add(t, function() end)
        end)
        if ok then
            log("  callbacks:add('" .. t .. "', fn): OK")
            discovery("Callback type '" .. t .. "' is accepted")
        else
            log("  callbacks:add('" .. t .. "', fn): REJECTED (" .. tostring(err) .. ")")
        end
    end
end

------------------------------------------------------------------------
section("Summary")
------------------------------------------------------------------------
log("")
log("############################################################")
log("#  PROBE COMPLETE")
log("#  Sections: " .. section_count)
log("#  Pass: " .. pass_count)
log("#  Fail: " .. fail_count)
log("#  Discoveries: " .. discovery_count)
log("#")
log("#  Note: Frame and Painted callback results will be appended")
log("#  to this log after the first frame is rendered by mGBA.")
log("#  Check the bottom of this file for deferred results.")
log("############################################################")
log("")
log("Log written to: " .. log_path)

if f then f:close() end
