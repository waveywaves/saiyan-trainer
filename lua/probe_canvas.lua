-- probe_canvas.lua
-- Deep-probe the canvas and image APIs in mGBA.

local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or ""
local project_root = script_path:match("^(.*)/lua/probe_canvas%.lua$") or "."

local log_path = project_root .. "/output/probe_canvas.log"
local f = io.open(log_path, "w")
local function log(msg)
    print(msg)
    if f then f:write(msg .. "\n"); f:flush() end
end

log("=== Canvas Deep Probe ===")

-- Probe canvas methods by trying common names
local canvas_methods = {
    "newImage", "newPainter", "setImage", "image",
    "drawText", "drawRect", "drawLine", "drawPixel",
    "fillRect", "clear", "update", "refresh",
    "width", "height", "size", "setSize", "resize",
    "screenWidth", "screenHeight",
    "requestPaint", "paint",
}

log("--- canvas direct method probe ---")
for _, m in ipairs(canvas_methods) do
    local ok, val = pcall(function() return canvas[m] end)
    if ok and val ~= nil then
        log("  canvas." .. m .. " = " .. type(val))
    end
end

-- Try to get image dimensions
log("\n--- canvas properties ---")
local ok, w = pcall(function() return canvas.width end)
if ok and w then log("  canvas.width = " .. tostring(w)) end
local ok, h = pcall(function() return canvas.height end)
if ok and h then log("  canvas.height = " .. tostring(h)) end

-- Try creating an image
log("\n--- image creation ---")
local img = nil

-- Method 1: canvas:newImage
local ok1, r1 = pcall(function() return canvas:newImage(240, 160) end)
log("canvas:newImage(240,160): " .. (ok1 and type(r1) or "FAILED: " .. tostring(r1)))
if ok1 then img = r1 end

-- Method 2: image module
local ok2, image_mod = pcall(function() return _G.image end)
log("global 'image': " .. (ok2 and type(image_mod) or "nil"))
if ok2 and image_mod then
    local ok3, r3 = pcall(function() return image_mod.new(240, 160) end)
    log("image.new(240,160): " .. (ok3 and type(r3) or "FAILED: " .. tostring(r3)))
    if ok3 then img = r3 end
end

-- Probe image object methods if we got one
if img then
    log("\n--- image methods ---")
    local img_methods = {
        "drawText", "drawRect", "drawRectangle", "drawLine", "drawCircle",
        "drawPixel", "setPixel", "getPixel",
        "fillRect", "fillRectangle",
        "clear", "update", "paint", "blit",
        "width", "height", "save",
        "setAttribute",
    }
    for _, m in ipairs(img_methods) do
        local ok, val = pcall(function() return img[m] end)
        if ok and val ~= nil then
            log("  img." .. m .. " = " .. type(val))
        end
    end

    -- Try drawing on the image
    log("\n--- image drawing tests ---")
    local tests = {
        {"drawText", function() img:drawText(10, 10, "Hello") end},
        {"drawRect", function() img:drawRect(0, 0, 50, 50) end},
        {"drawRectangle", function() img:drawRectangle(0, 0, 50, 50) end},
        {"drawLine", function() img:drawLine(0, 0, 50, 50) end},
        {"drawCircle", function() img:drawCircle(25, 25, 10) end},
    }
    for _, t in ipairs(tests) do
        local ok, err = pcall(t[2])
        log("  " .. t[1] .. ": " .. (ok and "OK" or tostring(err)))
    end

    -- Try displaying the image
    log("\n--- canvas display tests ---")
    local display_tests = {
        {"canvas:setImage", function() canvas:setImage(img) end},
        {"canvas:update", function() canvas:update() end},
        {"canvas:requestPaint", function() canvas:requestPaint() end},
        {"canvas:paint", function() canvas:paint() end},
    }
    for _, t in ipairs(display_tests) do
        local ok, err = pcall(t[2])
        log("  " .. t[1] .. ": " .. (ok and "OK" or tostring(err)))
    end
end

-- Check console buffer capabilities for text HUD
log("\n--- console buffer HUD test ---")
local buf = console:createBuffer("HUD")
if buf then
    local ok1, _ = pcall(function() buf:setSize(40, 10) end)
    log("  setSize(40,10): " .. (ok1 and "OK" or "FAILED"))
    local ok2, _ = pcall(function() buf:clear() end)
    log("  clear: " .. (ok2 and "OK" or "FAILED"))
    local ok3, _ = pcall(function() buf:moveCursor(0, 0) end)
    log("  moveCursor(0,0): " .. (ok3 and "OK" or "FAILED"))
    local ok4, _ = pcall(function() buf:print("Gen: 0  Species: 1  Fitness: 0.0\n") end)
    log("  print: " .. (ok4 and "OK" or "FAILED"))
end

log("\n=== Probe Complete ===")
if f then f:close() end
