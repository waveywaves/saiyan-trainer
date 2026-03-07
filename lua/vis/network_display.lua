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

local NetworkDisplay = {}

---------------------------------------------------------------------------
-- Internal state (lazy-initialized on first call)
---------------------------------------------------------------------------
local state = nil  -- { available, layer, painter, hasText, pd, w, h }
local enabled = true

-- Layout constants
local PANEL_W = 132
local PANEL_H = 160

local INPUT_X = 10
local OUTPUT_X = 115
local HIDDEN_X_MIN = 35
local HIDDEN_X_MAX = 95
local NODE_Y_MIN = 25
local NODE_Y_MAX = 145
local NODE_RADIUS = 3

-- Colors (ARGB32)
local BG_COLOR    = 0xB0000000  -- semi-transparent black
local TEXT_WHITE  = 0xFFFFFFFF
local TEXT_CYAN   = 0xFF00FFFF
local TEXT_YELLOW = 0xFFFFFF00

-- Font settings
local FONT_PATH   = "/opt/mgba/share/mgba/scripts/demos/SourceSans3-Regular.otf"
local FONT_ALT    = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
local FONT_SIZE   = 7

-- Input and output labels
local inputLabels = nil
local outputLabels = nil

local function getInputLabels()
    if not inputLabels then
        inputLabels = GameInputs.getInputLabels()
        inputLabels[#inputLabels + 1] = "BIAS"  -- 9th input
    end
    return inputLabels
end

local function getOutputLabels()
    if not outputLabels then
        local names = Controller.getButtonNames()
        outputLabels = {}
        for i, name in ipairs(names) do
            -- Shorten for display
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

    -- Check if canvas API exists
    if type(canvas) ~= "userdata" and type(canvas) ~= "table" then
        state = { available = false }
        return state
    end

    local ok, err = pcall(function()
        local layer = canvas:newLayer(PANEL_W, PANEL_H)
        layer:setPosition(0, 0)
        local painter = image.newPainter(layer.image)

        -- Try to load a FreeType font for text rendering
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

        -- Load pixel_draw.lua as fallback text renderer
        local pd = nil
        if not hasText then
            local pdOk, pdResult = pcall(dofile, "lua/vis/pixel_draw.lua")
            if pdOk then
                pd = pdResult
            end
        end

        -- Also load pixel_draw for color utilities (weightColor, nodeColor)
        local pdColors = nil
        local pcOk, pcResult = pcall(dofile, "lua/vis/pixel_draw.lua")
        if pcOk then
            pdColors = pcResult
        end

        state = {
            available = true,
            layer     = layer,
            painter   = painter,
            hasText   = hasText,
            pd        = pd,           -- fallback text renderer (nil if FreeType works)
            pdColors  = pdColors,      -- color utilities
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
-- Text drawing helper (Painter or pixel_draw fallback)
---------------------------------------------------------------------------
local function drawText(s, text, x, y, color)
    if s.hasText then
        s.painter:setFillColor(color)
        s.painter:drawText(text, x, y)
    elseif s.pd then
        s.pd.drawText(s.layer.image, x, y, text, color)
    end
end

---------------------------------------------------------------------------
-- Color helpers (use pixel_draw utilities or inline fallback)
---------------------------------------------------------------------------
local function weightColor(pdColors, weight)
    if pdColors and pdColors.weightColor then
        return pdColors.weightColor(weight)
    end
    -- Inline fallback
    local mag = math.abs(weight)
    local sigmoid_val = 2.0 / (1.0 + math.exp(-4.9 * mag)) - 1.0
    local intensity = math.floor(sigmoid_val * 255)
    local alpha = math.max(40, math.min(220, 40 + intensity))
    if weight > 0 then
        return alpha * 0x1000000 + intensity * 0x100  -- green
    else
        return alpha * 0x1000000 + intensity * 0x10000  -- red
    end
end

local function nodeColor(pdColors, value)
    if pdColors and pdColors.nodeColor then
        return pdColors.nodeColor(value)
    end
    -- Inline fallback
    local v = math.max(-1, math.min(1, value or 0))
    local gray = math.floor((v + 1) / 2 * 255)
    local alpha = (v == 0) and 0x50 or 0xFF
    local fill = alpha * 0x1000000 + gray * 0x10000 + gray * 0x100 + gray
    local border = alpha * 0x1000000
    return fill, border
end

--- Connection color adapted from MarI/O convention.
-- Green = positive weight, red = negative weight, alpha based on source activation.
local function connectionColor(weight, sourceActive)
    local mag = math.abs(weight)
    local sigmoid_val = 2.0 / (1.0 + math.exp(-4.9 * mag)) - 1.0
    local intensity = math.floor(sigmoid_val * 200 + 55)
    local alpha = sourceActive and 0xA0 or 0x20
    if weight > 0 then
        return alpha * 0x1000000 + intensity * 0x100  -- green channel
    else
        return alpha * 0x1000000 + intensity * 0x10000  -- red channel
    end
end

---------------------------------------------------------------------------
-- Layout: compute neuron positions
---------------------------------------------------------------------------
local function computeLayout(genome)
    local cells = {}  -- [neuronId] = { x, y, value }
    local network = genome.network

    -- Input neurons (IDs 1..Config.Inputs)
    local numInputs = Config.Inputs  -- 9 (8 game + bias)
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
    local numOutputs = Config.Outputs  -- 8
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

    -- Hidden neurons: discover from genes and network
    local hiddenIds = {}
    if genome.genes then
        for _, gene in ipairs(genome.genes) do
            for _, nid in ipairs({ gene.into, gene.out }) do
                if nid > Config.Inputs and nid <= Config.MaxNodes then
                    if not cells[nid] then
                        -- Hash neuron ID for initial Y position
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

    -- Spring-layout: 4 iterations of force-directed positioning (MarI/O style)
    if genome.genes then
        for _ = 1, 4 do
            for _, gene in ipairs(genome.genes) do
                if gene.enabled then
                    local c1 = cells[gene.into]
                    local c2 = cells[gene.out]
                    if c1 and c2 then
                        -- Only move hidden nodes (not input or output)
                        if gene.into > Config.Inputs and gene.into <= Config.MaxNodes then
                            c1.x = 0.75 * c1.x + 0.25 * c2.x
                            if c1.x < HIDDEN_X_MIN then c1.x = HIDDEN_X_MIN end
                            if c1.x > HIDDEN_X_MAX then c1.x = HIDDEN_X_MAX end
                        end
                        if gene.out > Config.Inputs and gene.out <= Config.MaxNodes then
                            c2.x = 0.75 * c2.x + 0.25 * c1.x
                            if c2.x < HIDDEN_X_MIN then c2.x = HIDDEN_X_MIN end
                            if c2.x > HIDDEN_X_MAX then c2.x = HIDDEN_X_MAX end
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

--- Display the neural network topology on the canvas overlay.
-- Draws input, hidden, and output neurons with weighted connections.
-- @param genome table  The genome to visualize (must have .genes and .network).
-- @param pool   table  The population pool (for stats: generation, maxFitness, species count).
function NetworkDisplay.displayGenome(genome, pool)
    if not enabled then return end
    if genome == nil or genome.network == nil then return end

    local s = initOverlay()
    if not s.available then return end

    local p = s.painter

    -- Clear background
    p:setBlend(false)
    p:setFill(true)
    p:setFillColor(BG_COLOR)
    p:drawRectangle(0, 0, s.w, s.h)
    p:setBlend(true)

    -- Compute neuron positions
    local cells, hiddenIds = computeLayout(genome)

    -- Draw stats text at top
    local gen = pool and pool.generation or 0
    local fit = genome.fitness or 0
    local species = pool and #pool.species or 0
    local maxFit = pool and pool.maxFitness or 0

    drawText(s, string.format("G:%d F:%.0f", gen, fit), 2, 2, TEXT_CYAN)
    drawText(s, string.format("Sp:%d Max:%.0f", species, maxFit), 2, 10, TEXT_YELLOW)

    -- Draw connections
    if genome.genes then
        for _, gene in ipairs(genome.genes) do
            if gene.enabled then
                local c1 = cells[gene.into]
                local c2 = cells[gene.out]
                if c1 and c2 then
                    local sourceActive = math.abs(c1.value) > 0.01
                    local color = connectionColor(gene.weight, sourceActive)
                    p:setStrokeColor(color)
                    p:setStrokeWidth(1)
                    p:setFill(false)
                    p:drawLine(c1.x, c1.y, c2.x, c2.y)
                end
            end
        end
    end

    -- Draw nodes
    local function drawNode(nid, cell)
        local fill, border = nodeColor(s.pdColors, cell.value)
        -- Filled circle
        p:setFill(true)
        p:setFillColor(fill)
        p:setStrokeWidth(0)
        p:drawCircle(cell.x, cell.y, NODE_RADIUS)
        -- Border circle
        p:setFill(false)
        p:setStrokeColor(border)
        p:setStrokeWidth(1)
        p:drawCircle(cell.x, cell.y, NODE_RADIUS)
    end

    -- Draw input nodes + labels
    local labels = getInputLabels()
    for i = 1, Config.Inputs do
        local cell = cells[i]
        if cell then
            drawNode(i, cell)
            drawText(s, labels[i] or "", 1, cell.y - 3, TEXT_WHITE)
        end
    end

    -- Draw output nodes + labels
    local outLabels = getOutputLabels()
    for o = 1, Config.Outputs do
        local nid = Config.MaxNodes + o
        local cell = cells[nid]
        if cell then
            drawNode(nid, cell)
            drawText(s, outLabels[o] or "", OUTPUT_X + NODE_RADIUS + 2, cell.y - 3, TEXT_WHITE)
        end
    end

    -- Draw hidden nodes
    for _, nid in ipairs(hiddenIds) do
        local cell = cells[nid]
        if cell then
            drawNode(nid, cell)
        end
    end

    -- Push overlay to screen
    s.layer:update()
end

--- Toggle the overlay on/off.
-- @param val boolean  true to enable, false to disable.
function NetworkDisplay.setEnabled(val)
    enabled = val
end

--- Check if the overlay initialized successfully.
-- @return boolean  true if canvas/painter are available.
function NetworkDisplay.isAvailable()
    local s = initOverlay()
    return s.available
end

return NetworkDisplay
