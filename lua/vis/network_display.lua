-- network_display.lua
-- MarI/O-style neural network topology overlay for mGBA.
--
-- Draws input, hidden, and output neurons with weighted connections on
-- a semi-transparent canvas overlay using the mGBA Painter API.
-- Falls back to pixel_draw.lua bitmap text when FreeType is unavailable.
--
-- The module does NOT throttle itself -- the caller (main.lua) is
-- responsible for calling displayGenome() every N frames.
--
-- Usage:
--   local NetworkDisplay = dofile("lua/vis/network_display.lua")
--   NetworkDisplay.displayGenome(genome, pool)

local Config = dofile("lua/neat/config.lua")
local GameInputs = dofile("lua/game/inputs.lua")
local Controller = dofile("lua/controller.lua")
local MemoryMap = dofile("lua/memory_map.lua")

local NetworkDisplay = {}

---------------------------------------------------------------------------
-- Internal state (lazy-initialized on first call)
---------------------------------------------------------------------------
local state = nil
local enabled = true

-- Layout constants — compact to minimize game obstruction
local PANEL_W = 240    -- full GBA screen width
local PANEL_H = 160    -- full GBA screen height

-- Network area (compact left strip)
local NET_X = 0
local NET_W = 85

local INPUT_X = 8
local OUTPUT_X = 72
local HIDDEN_X_MIN = 24
local HIDDEN_X_MAX = 58
local NODE_Y_MIN = 18
local NODE_Y_MAX = 130
local NODE_RADIUS = 3

-- Stats area (compact right strip)
local STATS_X = 175
local STATS_W = 62

-- Connection filtering: hide weak connections to reduce visual noise
local CONNECTION_WEIGHT_THRESHOLD = 0.8  -- only draw |weight| > this (aggressive filter)

-- Colors (ARGB32)
local BG_COLOR       = 0x38000000  -- nearly transparent (game clearly visible)
local STATS_BG       = 0x80101020  -- semi-transparent stats panel
local TEXT_WHITE     = 0xFFFFFFFF
local TEXT_CYAN      = 0xFF00DDFF
local TEXT_YELLOW    = 0xFFFFDD00
local TEXT_GREEN     = 0xFF00FF88
local TEXT_RED       = 0xFFFF6644
local TEXT_GRAY      = 0xFFAAAAAA
local BAR_GREEN      = 0xFF00CC44
local BAR_RED        = 0xFFCC2222
local BAR_BLUE       = 0xFF3388FF
local BAR_BG         = 0xFF333333
local BORDER_COLOR   = 0xFF444466
local ACTIVE_BTN     = 0xFF4488FF
local INACTIVE_BTN   = 0xFF666666

-- Font settings
local FONT_PATH   = "/opt/mgba/share/mgba/scripts/demos/SourceSans3-Regular.otf"
local FONT_ALT    = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
local FONT_SIZE   = 7
local FONT_SIZE_SM = 6

-- Input and output labels
local inputLabels = nil
local outputLabels = nil

local function getInputLabels()
    if not inputLabels then
        inputLabels = GameInputs.getInputLabels()
        inputLabels[#inputLabels + 1] = "Bias"
    end
    return inputLabels
end

local function getOutputLabels()
    if not outputLabels then
        local names = Controller.getButtonNames()
        outputLabels = {}
        for i, name in ipairs(names) do
            if name == "Down" then outputLabels[i] = "Dn"
            elseif name == "Left" then outputLabels[i] = "Lt"
            elseif name == "Right" then outputLabels[i] = "Rt"
            else outputLabels[i] = name
            end
        end
    end
    return outputLabels
end

---------------------------------------------------------------------------
-- Lazy initialization
---------------------------------------------------------------------------
local function initOverlay()
    if state then return state end

    if type(canvas) ~= "userdata" and type(canvas) ~= "table" then
        state = { available = false }
        return state
    end

    local ok, err = pcall(function()
        local layer = canvas:newLayer(PANEL_W, PANEL_H)
        layer:setPosition(0, 0)
        local painter = image.newPainter(layer.image)

        -- Try to load a FreeType font
        local hasText = false
        for _, fpath in ipairs({ FONT_PATH, FONT_ALT }) do
            local f = io.open(fpath, "r")
            if f then
                f:close()
                painter:loadFont(fpath)
                painter:setFontSize(FONT_SIZE)
                hasText = true
                break
            end
        end

        -- Load pixel_draw.lua as fallback
        local pd = nil
        if not hasText then
            local pdOk, pdResult = pcall(dofile, "lua/vis/pixel_draw.lua")
            if pdOk then pd = pdResult end
        end

        state = {
            available = true,
            layer     = layer,
            painter   = painter,
            hasText   = hasText,
            pd        = pd,
            w         = PANEL_W,
            h         = PANEL_H,
        }
    end)

    if not ok then
        state = { available = false }
        if console and console.log then
            pcall(function() console:log("[NetworkDisplay] Init failed: " .. tostring(err)) end)
        end
    end

    return state
end

---------------------------------------------------------------------------
-- Text drawing helpers
---------------------------------------------------------------------------
local function drawText(s, text, x, y, color)
    if s.hasText then
        s.painter:setFillColor(color)
        s.painter:drawText(text, x, y)
    elseif s.pd then
        s.pd.drawText(s.layer.image, x, y, text, color)
    end
end

local function setFontSize(s, size)
    if s.hasText then
        s.painter:setFontSize(size)
    end
end

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------
local function drawBar(p, x, y, w, h, pct, fgColor)
    -- Background
    p:setFill(true)
    p:setStrokeWidth(0)
    p:setFillColor(BAR_BG)
    p:drawRectangle(x, y, w, h)
    -- Foreground
    local fillW = math.floor(w * math.max(0, math.min(1, pct)))
    if fillW > 0 then
        p:setFillColor(fgColor)
        p:drawRectangle(x, y, fillW, h)
    end
end

--- Connection color: green=positive, red=negative, alpha by source activation.
local function connectionColor(weight, sourceActive)
    local mag = math.abs(weight)
    local sigmoid_val = 2.0 / (1.0 + math.exp(-4.9 * mag)) - 1.0
    local intensity = math.floor(sigmoid_val * 200 + 55)
    local alpha = sourceActive and 0xC0 or 0x18
    if weight > 0 then
        return alpha * 0x1000000 + intensity * 0x100  -- green
    else
        return alpha * 0x1000000 + intensity * 0x10000  -- red
    end
end

--- Node fill color based on activation value.
local function nodeColor(value)
    local v = math.max(-1, math.min(1, value or 0))
    local gray = math.floor((v + 1) / 2 * 255)
    local alpha = (math.abs(v) < 0.01) and 0x40 or 0xE0
    return alpha * 0x1000000 + gray * 0x10000 + gray * 0x100 + gray
end

---------------------------------------------------------------------------
-- Layout: compute neuron positions
---------------------------------------------------------------------------
local function computeLayout(genome)
    local cells = {}
    local network = genome.network

    -- Input neurons (IDs 1..Inputs)
    local numInputs = Config.Inputs
    local inputSpacing = (NODE_Y_MAX - NODE_Y_MIN) / math.max(1, numInputs - 1)
    for i = 1, numInputs do
        local neuron = network and network.neurons and network.neurons[i]
        cells[i] = {
            x = INPUT_X,
            y = NODE_Y_MIN + (i - 1) * inputSpacing,
            value = neuron and neuron.value or 0,
        }
    end

    -- Output neurons (IDs MaxNodes+1..MaxNodes+Outputs)
    local numOutputs = Config.Outputs
    local outputSpacing = (NODE_Y_MAX - NODE_Y_MIN) / math.max(1, numOutputs - 1)
    for o = 1, numOutputs do
        local nid = Config.MaxNodes + o
        local neuron = network and network.neurons and network.neurons[nid]
        cells[nid] = {
            x = OUTPUT_X,
            y = NODE_Y_MIN + (o - 1) * outputSpacing,
            value = neuron and neuron.value or 0,
        }
    end

    -- Hidden neurons: discover from genes
    local hiddenIds = {}
    if genome.genes then
        for _, gene in ipairs(genome.genes) do
            for _, nid in ipairs({ gene.into, gene.out }) do
                if nid > Config.Inputs and nid <= Config.MaxNodes then
                    if not cells[nid] then
                        local hashY = NODE_Y_MIN + ((nid * 7919) % 1000) / 1000 * (NODE_Y_MAX - NODE_Y_MIN)
                        local neuron = network and network.neurons and network.neurons[nid]
                        cells[nid] = {
                            x = (HIDDEN_X_MIN + HIDDEN_X_MAX) / 2,
                            y = hashY,
                            value = neuron and neuron.value or 0,
                        }
                        hiddenIds[#hiddenIds + 1] = nid
                    end
                end
            end
        end
    end

    -- Spring-layout: 4 iterations (MarI/O style)
    if genome.genes then
        for _ = 1, 4 do
            for _, gene in ipairs(genome.genes) do
                if gene.enabled then
                    local c1 = cells[gene.into]
                    local c2 = cells[gene.out]
                    if c1 and c2 then
                        if gene.into > Config.Inputs and gene.into <= Config.MaxNodes then
                            c1.x = 0.75 * c1.x + 0.25 * c2.x
                            c1.y = 0.75 * c1.y + 0.25 * c2.y
                            c1.x = math.max(HIDDEN_X_MIN, math.min(HIDDEN_X_MAX, c1.x))
                            c1.y = math.max(NODE_Y_MIN, math.min(NODE_Y_MAX, c1.y))
                        end
                        if gene.out > Config.Inputs and gene.out <= Config.MaxNodes then
                            c2.x = 0.75 * c2.x + 0.25 * c1.x
                            c2.y = 0.75 * c2.y + 0.25 * c1.y
                            c2.x = math.max(HIDDEN_X_MIN, math.min(HIDDEN_X_MAX, c2.x))
                            c2.y = math.max(NODE_Y_MIN, math.min(NODE_Y_MAX, c2.y))
                        end
                    end
                end
            end
        end
    end

    return cells, hiddenIds
end

---------------------------------------------------------------------------
-- Main draw function
---------------------------------------------------------------------------

function NetworkDisplay.displayGenome(genome, pool)
    if not enabled then return end
    if genome == nil or genome.network == nil then return end

    local s = initOverlay()
    if not s.available then return end

    local p = s.painter

    -- Clear entire overlay with transparency
    p:setBlend(false)
    p:setFill(true)
    p:setFillColor(0x00000000)
    p:setStrokeWidth(0)
    p:drawRectangle(0, 0, s.w, s.h)

    -- Draw network background (left area)
    p:setFillColor(BG_COLOR)
    p:drawRectangle(NET_X, 0, NET_W, s.h)

    -- Draw stats background (right area)
    p:setFillColor(STATS_BG)
    p:drawRectangle(STATS_X - 2, 0, STATS_W + 2, s.h)

    -- Border between network and stats
    p:setBlend(true)
    p:setFill(false)
    p:setStrokeColor(BORDER_COLOR)
    p:setStrokeWidth(1)
    p:drawLine(STATS_X - 2, 0, STATS_X - 2, s.h)

    -- ===== STATS PANEL (right side) =====
    local gen = pool and pool.generation or 0
    local fit = genome.fitness or 0
    local species = pool and #pool.species or 0
    local maxFit = pool and pool.maxFitness or 0

    setFontSize(s, FONT_SIZE)

    -- Title
    drawText(s, "SAIYAN TRAINER", STATS_X + 2, 3, TEXT_CYAN)

    -- Generation
    setFontSize(s, FONT_SIZE_SM)
    drawText(s, string.format("Gen: %d", gen), STATS_X + 2, 14, TEXT_WHITE)
    drawText(s, string.format("Species: %d", species), STATS_X + 2, 22, TEXT_WHITE)

    -- Fitness
    drawText(s, string.format("Fit: %.0f", fit), STATS_X + 2, 32, fit > 0 and TEXT_GREEN or TEXT_RED)
    drawText(s, string.format("Max: %.0f", maxFit), STATS_X + 2, 40, TEXT_YELLOW)

    -- Gene/node count
    local geneCount = genome.genes and #genome.genes or 0
    local hiddenCount = genome.maxneuron and math.max(0, genome.maxneuron - Config.Inputs) or 0
    drawText(s, string.format("Genes: %d", geneCount), STATS_X + 2, 52, TEXT_GRAY)
    drawText(s, string.format("Hidden: %d", hiddenCount), STATS_X + 2, 60, TEXT_GRAY)

    -- HP bars
    local p1hp = MemoryMap.read(MemoryMap.p1_health)
    local p1max = MemoryMap.read(MemoryMap.p1_health_max)
    local p2hp = MemoryMap.read(MemoryMap.p2_health)
    if p1max == 0 then p1max = 255 end

    drawText(s, string.format("P1: %d/%d", p1hp, p1max), STATS_X + 2, 72, TEXT_GREEN)
    drawBar(p, STATS_X + 2, 80, STATS_W - 6, 6, p1hp / math.max(1, p1max), BAR_GREEN)

    -- P2 max HP unknown (address unverified); use same max as P1 as best guess
    local p2max = p1max > 0 and p1max or 255
    drawText(s, string.format("P2: %d", p2hp), STATS_X + 2, 89, TEXT_RED)
    drawBar(p, STATS_X + 2, 97, STATS_W - 6, 6, p2hp / math.max(1, p2max), BAR_RED)

    -- Button states (output neurons)
    drawText(s, "BUTTONS", STATS_X + 2, 110, TEXT_CYAN)
    local outLabels = getOutputLabels()
    local btnY = 119
    for o = 1, Config.Outputs do
        local nid = Config.MaxNodes + o
        local neuron = genome.network and genome.network.neurons and genome.network.neurons[nid]
        local active = neuron and neuron.value and neuron.value > 0
        local color = active and ACTIVE_BTN or INACTIVE_BTN

        -- Small indicator square
        p:setFill(true)
        p:setStrokeWidth(0)
        p:setFillColor(color)
        p:drawRectangle(STATS_X + 2, btnY, 5, 5)

        drawText(s, outLabels[o] or "", STATS_X + 10, btnY - 1, active and TEXT_WHITE or TEXT_GRAY)

        if o <= 4 then
            -- Second column for buttons 5-8
        end
        btnY = btnY + 8
        if o == 4 then
            -- Reset for second column (not needed if vertical list fits)
        end
    end

    -- ===== NETWORK VISUALIZATION (left area) =====
    local cells, hiddenIds = computeLayout(genome)

    -- Draw "NETWORK" label
    setFontSize(s, FONT_SIZE_SM)
    drawText(s, "IN", INPUT_X - 2, 12, TEXT_GRAY)
    drawText(s, "OUT", OUTPUT_X - 4, 12, TEXT_GRAY)

    -- Draw connections first (behind nodes) — filter weak ones to reduce noise
    p:setFill(false)
    if genome.genes then
        for _, gene in ipairs(genome.genes) do
            if gene.enabled and math.abs(gene.weight) > CONNECTION_WEIGHT_THRESHOLD then
                local c1 = cells[gene.into]
                local c2 = cells[gene.out]
                if c1 and c2 then
                    local sourceActive = math.abs(c1.value) > 0.01
                    local color = connectionColor(gene.weight, sourceActive)
                    p:setStrokeColor(color)
                    -- Thicker lines for stronger weights
                    local thickness = math.abs(gene.weight) > 1.0 and 2 or 1
                    p:setStrokeWidth(thickness)
                    p:drawLine(c1.x, c1.y, c2.x, c2.y)
                end
            end
        end
    end

    -- Draw input nodes
    local labels = getInputLabels()
    for i = 1, Config.Inputs do
        local cell = cells[i]
        if cell and math.abs(cell.value) > 0.01 then
            local fill = nodeColor(cell.value)
            p:setFill(true)
            p:setFillColor(fill)
            p:setStrokeWidth(0)
            p:drawCircle(cell.x, cell.y, NODE_RADIUS)
            p:setFill(false)
            p:setStrokeColor(0xC0FFFFFF)
            p:setStrokeWidth(1)
            p:drawCircle(cell.x, cell.y, NODE_RADIUS)
        else
            -- Dim inactive input
            p:setFill(true)
            p:setFillColor(0x30FFFFFF)
            p:setStrokeWidth(0)
            p:drawCircle(cell.x, cell.y, NODE_RADIUS - 1)
        end
    end

    -- Draw output nodes
    for o = 1, Config.Outputs do
        local nid = Config.MaxNodes + o
        local cell = cells[nid]
        if cell then
            local active = cell.value > 0
            local fill = active and 0xE04488FF or 0x40666666
            p:setFill(true)
            p:setFillColor(fill)
            p:setStrokeWidth(0)
            p:drawCircle(cell.x, cell.y, NODE_RADIUS)
            if active then
                p:setFill(false)
                p:setStrokeColor(0xFFFFFFFF)
                p:setStrokeWidth(1)
                p:drawCircle(cell.x, cell.y, NODE_RADIUS)
            end
        end
    end

    -- Draw hidden nodes
    for _, nid in ipairs(hiddenIds) do
        local cell = cells[nid]
        if cell then
            local fill = nodeColor(cell.value)
            p:setFill(true)
            p:setFillColor(fill)
            p:setStrokeWidth(0)
            p:drawCircle(cell.x, cell.y, NODE_RADIUS - 1)
        end
    end

    -- Push overlay to screen
    s.layer:update()
end

function NetworkDisplay.setEnabled(val)
    enabled = val
end

function NetworkDisplay.isAvailable()
    local s = initOverlay()
    return s.available
end

return NetworkDisplay
