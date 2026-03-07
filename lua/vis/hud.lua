-- hud.lua
-- Training statistics heads-up display for mGBA.
--
-- Uses mGBA's canvas/image/painter API (available in mGBA 0.11+ Qt frontend)
-- to draw an on-screen overlay with training stats.  Falls back to console
-- logging if the canvas API is not available.
--
-- mGBA Drawing API Summary:
--   canvas:newLayer(w, h)         -> overlay layer
--   image.newPainter(layer.image) -> painter object
--   painter:drawText(text, x, y)  (requires USE_FREETYPE build)
--   painter:drawRectangle(x, y, w, h)
--   painter:setFillColor(0xAARRGGBB)
--   overlay:update()              -> push changes to screen
--
-- Usage:
--   local HUD = dofile("lua/vis/hud.lua")
--   HUD.displayHUD(pool, currentGenome, fps)
--   HUD.displayFitnessBar(fitness, maxFitness)

local HUD = {}

---------------------------------------------------------------------------
-- Internal state (lazy-initialized on first call)
---------------------------------------------------------------------------
local state = nil  -- { overlay, painter, hasText, w, h }

local FONT_PATH  = "/opt/mgba/share/mgba/scripts/demos/SourceSans3-Regular.otf"
local FONT_ALT   = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
local FONT_SIZE  = 8
local BG_COLOR   = 0xB0000000  -- semi-transparent black
local TEXT_WHITE  = 0xFFFFFFFF
local TEXT_GREEN  = 0xFF00FF00
local TEXT_YELLOW = 0xFFFFFF00
local TEXT_RED    = 0xFFFF4444
local TEXT_CYAN   = 0xFF00FFFF
local LINE_H      = 10
local PAD          = 2

local function initOverlay()
    if state then return state end

    -- Check if canvas API exists
    if type(canvas) ~= "userdata" and type(canvas) ~= "table" then
        state = { hasCanvas = false }
        return state
    end

    local ok, err = pcall(function()
        local w = math.min(160, canvas:screenWidth())
        local h = math.min(80, canvas:screenHeight())
        local overlay = canvas:newLayer(w, h)
        overlay:setPosition(0, 0)  -- top-left corner
        local painter = image.newPainter(overlay.image)

        -- Try to load a font
        local hasText = false
        for _, fpath in ipairs({FONT_PATH, FONT_ALT}) do
            local f = io.open(fpath, "r")
            if f then
                f:close()
                painter:loadFont(fpath)
                painter:setFontSize(FONT_SIZE)
                hasText = true
                break
            end
        end

        state = {
            hasCanvas = true,
            hasText   = hasText,
            overlay   = overlay,
            painter   = painter,
            w         = w,
            h         = h,
        }
    end)

    if not ok then
        state = { hasCanvas = false }
        if console then
            console:log("[HUD] Canvas init failed: " .. tostring(err))
        end
    end

    return state
end

--- Display the training statistics HUD overlay.
-- Draws generation, species, genome, fitness, and FPS on screen.
-- Falls back to no-op if canvas is not available.
-- @param pool          table   The population pool.
-- @param currentGenome table   The genome currently being evaluated (optional).
-- @param fps           number  Current frames per second (optional).
function HUD.displayHUD(pool, currentGenome, fps)
    local s = initOverlay()
    if not s.hasCanvas or not s.hasText then return end

    local p = s.painter

    -- Clear background
    p:setBlend(false)
    p:setFill(true)
    p:setFillColor(BG_COLOR)
    p:drawRectangle(0, 0, s.w, s.h)
    p:setBlend(true)
    p:setStrokeWidth(0)

    local y = PAD
    -- Generation / Species
    p:setFillColor(TEXT_CYAN)
    local gen = pool and pool.generation or "?"
    local sp  = pool and pool.currentSpecies or "?"
    local gn  = pool and pool.currentGenome or "?"
    p:drawText(string.format("Gen:%s  Sp:%s  G:%s", gen, sp, gn), PAD, y)

    -- Fitness
    y = y + LINE_H
    local fit = currentGenome and currentGenome.fitness or 0
    local maxFit = pool and pool.maxFitness or 0
    p:setFillColor(TEXT_GREEN)
    p:drawText(string.format("Fit:%d  Max:%d", fit, maxFit), PAD, y)

    -- FPS
    y = y + LINE_H
    p:setFillColor(TEXT_YELLOW)
    p:drawText(string.format("FPS: %s", fps or "?"), PAD, y)

    -- Measured / stale indicator
    y = y + LINE_H
    if pool and pool.measured then
        p:setFillColor(TEXT_WHITE)
        p:drawText(string.format("Measured: %d", pool.measured), PAD, y)
    end

    s.overlay:update()
end

--- Display a horizontal fitness bar.
-- Draws a colored bar representing current fitness relative to max.
-- @param fitness    number  Current fitness value.
-- @param maxFitness number  Maximum fitness achieved (for scale).
function HUD.displayFitnessBar(fitness, maxFitness)
    local s = initOverlay()
    if not s.hasCanvas then return end

    fitness    = fitness or 0
    maxFitness = maxFitness or 1
    if maxFitness <= 0 then maxFitness = 1 end

    local barY = s.h - 6
    local barW = s.w - PAD * 2
    local barH = 4
    local fillW = math.max(0, math.min(barW, math.floor(barW * fitness / maxFitness)))

    local p = s.painter
    -- Bar background (dark)
    p:setBlend(false)
    p:setFill(true)
    p:setFillColor(0xFF333333)
    p:drawRectangle(PAD, barY, barW, barH)
    -- Bar fill (green to red gradient approximation)
    local ratio = fillW / barW
    local color
    if ratio > 0.5 then
        color = TEXT_GREEN
    elseif ratio > 0.25 then
        color = TEXT_YELLOW
    else
        color = TEXT_RED
    end
    p:setFillColor(color)
    p:drawRectangle(PAD, barY, fillW, barH)
    p:setBlend(true)

    s.overlay:update()
end

return HUD
