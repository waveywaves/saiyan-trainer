-- pixel_draw.lua
-- Software rendering primitives using only image:setPixel(x, y, color).
-- Provides bitmap font text, Bresenham lines, rectangles, and circles.
--
-- Designed for mGBA's constrained Lua image API where no drawText/drawLine/
-- drawRect exist on the image object -- only setPixel and getPixel.
--
-- Color format: 0xAARRGGBB (ARGB32), matching mGBA's image API.
--
-- Usage:
--   local PD = dofile("lua/vis/pixel_draw.lua")
--   local img = image.new(240, 160)
--   PD.drawText(img, 2, 2, "GEN:1  FIT:350", 0xFF00FF00)
--   PD.drawLine(img, 10, 10, 100, 80, 0xFFFF0000)
--   PD.drawRect(img, 0, 0, 50, 30, 0xFFFFFFFF)
--   PD.fillRect(img, 0, 0, 50, 30, 0x80000000)
--   PD.drawCircle(img, 25, 25, 5, 0xFF00FFFF)
--   PD.fillCircle(img, 25, 25, 5, 0xFF00FFFF)

local PD = {}

---------------------------------------------------------------------------
-- 1. BITMAP FONT (4x6, derived from font4x6 public domain)
---------------------------------------------------------------------------
-- Each glyph is 4 pixels wide, 6 pixels tall.
-- Stored as 6 integers per character, each integer has 4 bits (one per column).
-- Bit 0 (LSB) = leftmost pixel column, bit 3 = rightmost pixel column.
-- So for a row value, pixel at column c is: (row >> c) & 1 == 1.
--
-- Glyph width = 4, height = 6, advance = 5 (4 + 1px spacing).
-- Line height = 7 (6 + 1px spacing).

PD.FONT_W = 4
PD.FONT_H = 6
PD.CHAR_ADVANCE = 5   -- horizontal step per character
PD.LINE_HEIGHT  = 7   -- vertical step per line

-- Font table: ASCII char -> {row1, row2, row3, row4, row5, row6}
-- Each row is 4 bits wide. LSB = left pixel.
local FONT = {}

-- Helper: convert a visual bitmap string to row values.
-- Each string is 4 chars of '.' and '#', top to bottom.
-- This is only used at load time to populate FONT.
local function defchar(ch, r1, r2, r3, r4, r5, r6)
    local function parse(s)
        local v = 0
        for i = 1, 4 do
            if s:sub(i,i) == "#" then v = v + (2^(i-1)) end
        end
        return v
    end
    FONT[ch] = { parse(r1), parse(r2), parse(r3), parse(r4), parse(r5), parse(r6) }
end

-- Digits 0-9
defchar("0", ".##.", "#..#", "#.##", "##.#", "#..#", ".##.")
defchar("1", ".#..", "##..", ".#..", ".#..", ".#..", "###.")
defchar("2", ".##.", "#..#", "..#.", ".#..", "#...", "####")
defchar("3", ".##.", "#..#", "..#.", "..#.", "#..#", ".##.")
defchar("4", "#..#", "#..#", "####", "..#.", "..#.", "..#.")
defchar("5", "####", "#...", "###.", "..#.", "#..#", ".##.")
defchar("6", ".##.", "#...", "###.", "#..#", "#..#", ".##.")
defchar("7", "####", "..#.", ".#..", ".#..", "#...", "#...")
defchar("8", ".##.", "#..#", ".##.", "#..#", "#..#", ".##.")
defchar("9", ".##.", "#..#", ".###", "..#.", "..#.", ".##.")

-- Uppercase A-Z
defchar("A", ".##.", "#..#", "####", "#..#", "#..#", "#..#")
defchar("B", "###.", "#..#", "###.", "#..#", "#..#", "###.")
defchar("C", ".##.", "#..#", "#...", "#...", "#..#", ".##.")
defchar("D", "###.", "#..#", "#..#", "#..#", "#..#", "###.")
defchar("E", "####", "#...", "###.", "#...", "#...", "####")
defchar("F", "####", "#...", "###.", "#...", "#...", "#...")
defchar("G", ".##.", "#...", "#.##", "#..#", "#..#", ".###")
defchar("H", "#..#", "#..#", "####", "#..#", "#..#", "#..#")
defchar("I", "###.", ".#..", ".#..", ".#..", ".#..", "###.")
defchar("J", "..##", "..#.", "..#.", "..#.", "#.#.", ".#..")
defchar("K", "#..#", "#.#.", "##..", "##..", "#.#.", "#..#")
defchar("L", "#...", "#...", "#...", "#...", "#...", "####")
defchar("M", "#..#", "####", "####", "#..#", "#..#", "#..#")
defchar("N", "#..#", "##.#", "####", "#.##", "#..#", "#..#")
defchar("O", ".##.", "#..#", "#..#", "#..#", "#..#", ".##.")
defchar("P", "###.", "#..#", "###.", "#...", "#...", "#...")
defchar("Q", ".##.", "#..#", "#..#", "#.##", ".##.", "..##")
defchar("R", "###.", "#..#", "###.", "#.#.", "#..#", "#..#")
defchar("S", ".###", "#...", ".##.", "..#.", "..#.", "###.")
defchar("T", "####", ".#..", ".#..", ".#..", ".#..", ".#..")
defchar("U", "#..#", "#..#", "#..#", "#..#", "#..#", ".##.")
defchar("V", "#..#", "#..#", "#..#", "#..#", ".##.", ".##.")
defchar("W", "#..#", "#..#", "#..#", "####", "####", "#..#")
defchar("X", "#..#", "#..#", ".##.", ".##.", "#..#", "#..#")
defchar("Y", "#..#", "#..#", ".##.", ".#..", ".#..", ".#..")
defchar("Z", "####", "..#.", ".#..", ".#..", "#...", "####")

-- Symbols
defchar(" ", "....", "....", "....", "....", "....", "....")
defchar(".", "....", "....", "....", "....", "....", ".#..")
defchar(":", "....", ".#..", "....", ".#..", "....", "....")
defchar("/", "..#.", "..#.", ".#..", ".#..", "#...", "#...")
defchar("%", "#.#.", "..#.", ".#..", ".#..", "#...", "#.#.")
defchar("-", "....", "....", "####", "....", "....", "....")
defchar("+", "....", ".#..", "####", ".#..", "....", "....")
defchar("(", ".#..", "#...", "#...", "#...", "#...", ".#..")
defchar(")", ".#..", "..#.", "..#.", "..#.", "..#.", ".#..")
defchar("_", "....", "....", "....", "....", "....", "####")
defchar("!", ".#..", ".#..", ".#..", ".#..", "....", ".#..")
defchar("=", "....", "####", "....", "####", "....", "....")
defchar(",", "....", "....", "....", "....", ".#..", "#...")
defchar("?", ".##.", "#..#", "..#.", ".#..", "....", ".#..")
defchar("#", ".#.#", "####", ".#.#", "#.#.", "####", "#.#.")
defchar("*", "....", "#.#.", ".#..", "#.#.", "....", "....")

-- Lowercase letters (mapped to uppercase glyphs for simplicity)
for b = string.byte("a"), string.byte("z") do
    local upper = string.char(b - 32)
    if FONT[upper] then
        FONT[string.char(b)] = FONT[upper]
    end
end

---------------------------------------------------------------------------
-- 2. SAFE PIXEL SETTER (bounds-checked)
---------------------------------------------------------------------------
local function safeSetPixel(img, x, y, color)
    if x >= 0 and y >= 0 and x < img:width() and y < img:height() then
        img:setPixel(x, y, color)
    end
end

---------------------------------------------------------------------------
-- 3. TEXT RENDERING
---------------------------------------------------------------------------

--- Draw a single character at (px, py).
-- @param img    image   The mGBA image object.
-- @param px     number  Top-left x of the character cell.
-- @param py     number  Top-left y of the character cell.
-- @param ch     string  Single character to draw.
-- @param color  number  ARGB32 color value.
local function drawChar(img, px, py, ch, color)
    local glyph = FONT[ch]
    if not glyph then return end
    for row = 1, 6 do
        local bits = glyph[row]
        for col = 0, 3 do
            if bits % 2 == 1 then
                safeSetPixel(img, px + col, py + row - 1, color)
            end
            bits = math.floor(bits / 2)
        end
    end
end

--- Draw a string of text at (x, y).
-- Supports newline characters (\n) for multi-line text.
-- @param img    image   The mGBA image object.
-- @param x      number  Top-left x position.
-- @param y      number  Top-left y position.
-- @param text   string  The text to draw.
-- @param color  number  ARGB32 color value (default: 0xFFFFFFFF white).
function PD.drawText(img, x, y, text, color)
    color = color or 0xFFFFFFFF
    local cx, cy = x, y
    for i = 1, #text do
        local ch = text:sub(i, i)
        if ch == "\n" then
            cx = x
            cy = cy + PD.LINE_HEIGHT
        else
            drawChar(img, cx, cy, ch, color)
            cx = cx + PD.CHAR_ADVANCE
        end
    end
end

--- Measure the pixel width and height of a text string.
-- @param text string The text to measure.
-- @return number, number  Width in pixels, height in pixels.
function PD.measureText(text)
    local maxW = 0
    local cx = 0
    local lines = 1
    for i = 1, #text do
        local ch = text:sub(i, i)
        if ch == "\n" then
            if cx > maxW then maxW = cx end
            cx = 0
            lines = lines + 1
        else
            cx = cx + PD.CHAR_ADVANCE
        end
    end
    if cx > maxW then maxW = cx end
    -- Subtract trailing 1px spacing
    if maxW > 0 then maxW = maxW - 1 end
    return maxW, lines * PD.LINE_HEIGHT - 1
end

---------------------------------------------------------------------------
-- 4. BRESENHAM LINE DRAWING
---------------------------------------------------------------------------

--- Draw a line from (x0, y0) to (x1, y1) using Bresenham's algorithm.
-- @param img    image   The mGBA image object.
-- @param x0     number  Start x.
-- @param y0     number  Start y.
-- @param x1     number  End x.
-- @param y1     number  End y.
-- @param color  number  ARGB32 color value.
function PD.drawLine(img, x0, y0, x1, y1, color)
    color = color or 0xFFFFFFFF
    x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)

    local dx = math.abs(x1 - x0)
    local dy = -math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy  -- note: dy is negative

    while true do
        safeSetPixel(img, x0, y0, color)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then
            err = err + dy
            x0 = x0 + sx
        end
        if e2 <= dx then
            err = err + dx
            y0 = y0 + sy
        end
    end
end

---------------------------------------------------------------------------
-- 5. RECTANGLE DRAWING
---------------------------------------------------------------------------

--- Draw a filled rectangle.
-- @param img    image   The mGBA image object.
-- @param x      number  Top-left x.
-- @param y      number  Top-left y.
-- @param w      number  Width in pixels.
-- @param h      number  Height in pixels.
-- @param color  number  ARGB32 fill color.
function PD.fillRect(img, x, y, w, h, color)
    color = color or 0xFFFFFFFF
    x, y = math.floor(x), math.floor(y)
    local imgW, imgH = img:width(), img:height()
    -- Clamp to image bounds
    local x0 = math.max(0, x)
    local y0 = math.max(0, y)
    local x1 = math.min(imgW - 1, x + w - 1)
    local y1 = math.min(imgH - 1, y + h - 1)
    for py = y0, y1 do
        for px = x0, x1 do
            img:setPixel(px, py, color)
        end
    end
end

--- Draw a rectangle outline (1px border).
-- @param img    image   The mGBA image object.
-- @param x      number  Top-left x.
-- @param y      number  Top-left y.
-- @param w      number  Width in pixels.
-- @param h      number  Height in pixels.
-- @param color  number  ARGB32 border color.
function PD.drawRect(img, x, y, w, h, color)
    color = color or 0xFFFFFFFF
    -- Top edge
    PD.drawLine(img, x, y, x + w - 1, y, color)
    -- Bottom edge
    PD.drawLine(img, x, y + h - 1, x + w - 1, y + h - 1, color)
    -- Left edge
    PD.drawLine(img, x, y, x, y + h - 1, color)
    -- Right edge
    PD.drawLine(img, x + w - 1, y, x + w - 1, y + h - 1, color)
end

---------------------------------------------------------------------------
-- 6. CIRCLE DRAWING (Midpoint / Bresenham)
---------------------------------------------------------------------------

--- Draw a circle outline using the midpoint circle algorithm.
-- Plots 8-way symmetric points for efficiency.
-- @param img    image   The mGBA image object.
-- @param cx     number  Center x.
-- @param cy     number  Center y.
-- @param r      number  Radius in pixels.
-- @param color  number  ARGB32 color value.
function PD.drawCircle(img, cx, cy, r, color)
    color = color or 0xFFFFFFFF
    cx, cy, r = math.floor(cx), math.floor(cy), math.floor(r)
    if r <= 0 then
        safeSetPixel(img, cx, cy, color)
        return
    end

    local x = 0
    local y = r
    local d = 3 - 2 * r

    while x <= y do
        -- 8 symmetric points
        safeSetPixel(img, cx + x, cy - y, color)
        safeSetPixel(img, cx - x, cy - y, color)
        safeSetPixel(img, cx + x, cy + y, color)
        safeSetPixel(img, cx - x, cy + y, color)
        safeSetPixel(img, cx + y, cy - x, color)
        safeSetPixel(img, cx - y, cy - x, color)
        safeSetPixel(img, cx + y, cy + x, color)
        safeSetPixel(img, cx - y, cy + x, color)

        if d < 0 then
            d = d + 4 * x + 6
        else
            d = d + 4 * (x - y) + 10
            y = y - 1
        end
        x = x + 1
    end
end

--- Draw a filled circle using the midpoint algorithm with horizontal spans.
-- @param img    image   The mGBA image object.
-- @param cx     number  Center x.
-- @param cy     number  Center y.
-- @param r      number  Radius in pixels.
-- @param color  number  ARGB32 fill color.
function PD.fillCircle(img, cx, cy, r, color)
    color = color or 0xFFFFFFFF
    cx, cy, r = math.floor(cx), math.floor(cy), math.floor(r)
    if r <= 0 then
        safeSetPixel(img, cx, cy, color)
        return
    end

    local x = 0
    local y = r
    local d = 3 - 2 * r

    -- Draw horizontal spans for each octant pair
    local function hline(x0, x1, py)
        local imgW, imgH = img:width(), img:height()
        if py < 0 or py >= imgH then return end
        x0 = math.max(0, x0)
        x1 = math.min(imgW - 1, x1)
        for px = x0, x1 do
            img:setPixel(px, py, color)
        end
    end

    while x <= y do
        hline(cx - x, cx + x, cy - y)
        hline(cx - x, cx + x, cy + y)
        hline(cx - y, cx + y, cy - x)
        hline(cx - y, cx + y, cy + x)

        if d < 0 then
            d = d + 4 * x + 6
        else
            d = d + 4 * (x - y) + 10
            y = y - 1
        end
        x = x + 1
    end
end

---------------------------------------------------------------------------
-- 7. HELPER: CLEAR IMAGE
---------------------------------------------------------------------------

--- Fill entire image with a single color (typically transparent or a bg color).
-- @param img    image   The mGBA image object.
-- @param color  number  ARGB32 color (default: 0x00000000 fully transparent).
function PD.clear(img, color)
    color = color or 0x00000000
    local w, h = img:width(), img:height()
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            img:setPixel(x, y, color)
        end
    end
end

---------------------------------------------------------------------------
-- 8. HELPER: COLOR UTILITIES
---------------------------------------------------------------------------

--- Create an ARGB32 color from components.
-- @param r number Red   (0-255).
-- @param g number Green (0-255).
-- @param b number Blue  (0-255).
-- @param a number Alpha (0-255, default 255 = opaque).
-- @return number ARGB32 color.
function PD.rgba(r, g, b, a)
    a = a or 255
    return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

--- Blend between two colors by a factor t in [0, 1].
-- Useful for weight-based connection coloring.
-- @param c1 number ARGB32 color at t=0.
-- @param c2 number ARGB32 color at t=1.
-- @param t  number Blend factor [0, 1].
-- @return number ARGB32 blended color.
function PD.lerpColor(c1, c2, t)
    if t <= 0 then return c1 end
    if t >= 1 then return c2 end
    local function decompose(c)
        local a = math.floor(c / 0x1000000) % 256
        local r = math.floor(c / 0x10000) % 256
        local g = math.floor(c / 0x100) % 256
        local b = c % 256
        return a, r, g, b
    end
    local a1, r1, g1, b1 = decompose(c1)
    local a2, r2, g2, b2 = decompose(c2)
    local mix = function(v1, v2) return math.floor(v1 + (v2 - v1) * t + 0.5) end
    return PD.rgba(mix(r1, r2), mix(g1, g2), mix(b1, b2), mix(a1, a2))
end

--- Return a connection color based on weight sign and magnitude.
-- Positive weights -> green, negative weights -> red, opacity by magnitude.
-- Matches MarI/O convention.
-- @param weight number The connection weight.
-- @return number ARGB32 color.
function PD.weightColor(weight)
    local mag = math.abs(weight)
    local sigmoid_val = 2.0 / (1.0 + math.exp(-4.9 * mag)) - 1.0
    local intensity = math.floor(sigmoid_val * 255)
    local alpha = math.max(40, math.min(220, 40 + intensity))
    if weight > 0 then
        return PD.rgba(0, intensity, 0, alpha)         -- green
    else
        return PD.rgba(intensity, 0, 0, alpha)          -- red
    end
end

--- Return a node color based on activation value [-1, 1].
-- Maps to grayscale; 0 = dim/transparent, |1| = bright/opaque.
-- @param value number Neuron activation in [-1, 1].
-- @return number ARGB32 fill color.
-- @return number ARGB32 border color.
function PD.nodeColor(value)
    local v = math.max(-1, math.min(1, value or 0))
    local gray = math.floor((v + 1) / 2 * 255)
    local alpha = (v == 0) and 0x50 or 0xFF
    local fill = alpha * 0x1000000 + gray * 0x10000 + gray * 0x100 + gray
    local border = alpha * 0x1000000
    return fill, border
end

return PD
