-- network_display.lua
-- Neural network topology visualization overlay for BizHawk.
-- Draws the evolved NEAT network on screen: labeled input/output nodes,
-- color-coded connections (green=positive, red=negative weight),
-- brightness-coded neurons (brighter=more active), and force-directed
-- hidden node positioning.
--
-- Usage:
--   local NetworkDisplay = dofile("lua/vis/network_display.lua")
--   NetworkDisplay.displayGenome(genome)

local Config = dofile("lua/neat/config.lua")
local GameInputs = dofile("lua/game/inputs.lua")
local Controller = dofile("lua/controller.lua")

local NetworkDisplay = {}

-- Layout constants for the network display area (left side of GBA 240x160 screen)
local DISPLAY_X = 0
local DISPLAY_Y = 0
local DISPLAY_WIDTH = 132
local DISPLAY_HEIGHT = 160

local INPUT_X = 12
local OUTPUT_X = 120
local NODE_RADIUS = 2

local LABEL_FONT_SIZE = 7

-- Background overlay color (semi-transparent black)
local BG_COLOR = 0x80000000
local BG_BORDER = 0x80444444

-- Colors
local COLOR_LABEL = 0xFF888888
local COLOR_LABEL_ACTIVE = 0xFFCCCCCC
local COLOR_BORDER = 0xFF000000
local COLOR_OUTPUT_ACTIVE = 0xFF00FF00
local COLOR_OUTPUT_INACTIVE = 0xFF444444
local COLOR_DISABLED_GENE = 0x20666666

--- Map a value to [0, 1] using sigmoid-like clamping.
-- @param x number  Input value (typically neuron activation in [-1, 1]).
-- @return number   Value in [0, 1].
local function sigmoid01(x)
    return math.max(0, math.min(1, (x + 1) / 2))
end

--- Convert a connection weight to an ARGB color.
-- Positive weights are green, negative are red.
-- Alpha and intensity scale with |weight|.
-- @param weight number  The connection weight.
-- @return number  ARGB color value.
local function weightToColor(weight)
    local magnitude = math.abs(weight)
    -- Clamp magnitude to [0, 2] for color mapping
    magnitude = math.min(magnitude, 2.0)
    local intensity = math.floor(magnitude / 2.0 * 255)
    local alpha = math.floor(0x60 + magnitude / 2.0 * 0x80)
    alpha = math.min(alpha, 0xFF)

    if weight > 0 then
        -- Green: positive weight
        return alpha * 0x1000000 + intensity * 0x100
    else
        -- Red: negative weight
        return alpha * 0x1000000 + intensity * 0x10000
    end
end

--- Compute brightness fill color from neuron activation value.
-- @param value number  Neuron activation (typically in [-1, 1]).
-- @return number  ARGB fill color.
local function activationToColor(value)
    local brightness = math.floor(sigmoid01(value) * 255)
    brightness = math.max(0, math.min(255, brightness))
    -- Grayscale: same R, G, B
    return 0xFF000000 + brightness * 0x10000 + brightness * 0x100 + brightness
end

--- Position hidden nodes using a simple force-directed layout.
-- Input nodes are on the left, output nodes on the right.
-- Hidden nodes are placed in between and adjusted via repulsion/attraction.
-- @param genome table  The genome with genes.
-- @param cells  table  Table mapping neuron ID -> {x, y} (pre-filled with input/output).
-- @param hiddenIds table  Array of hidden neuron IDs.
local function positionHiddenNodes(genome, cells, hiddenIds)
    if #hiddenIds == 0 then
        return
    end

    -- Initialize hidden node positions: spread evenly in the middle area
    local midX = (INPUT_X + OUTPUT_X) / 2
    local spacing = (DISPLAY_HEIGHT - 20) / math.max(#hiddenIds, 1)

    for i, id in ipairs(hiddenIds) do
        cells[id] = {
            x = midX + math.random(-15, 15),
            y = 10 + (i - 1) * spacing + spacing / 2,
        }
    end

    -- Determine layer depth for each hidden node based on connectivity
    -- Nodes connected to inputs are more left, connected to outputs more right
    local leftBound = INPUT_X + 15
    local rightBound = OUTPUT_X - 15

    for _, id in ipairs(hiddenIds) do
        -- Count connections to inputs vs outputs
        local inputConns = 0
        local outputConns = 0
        local totalConns = 0
        for _, gene in ipairs(genome.genes) do
            if gene.enabled then
                if gene.into == id or gene.out == id then
                    totalConns = totalConns + 1
                    local other = (gene.into == id) and gene.out or gene.into
                    if other <= Config.Inputs then
                        inputConns = inputConns + 1
                    elseif other > Config.MaxNodes then
                        outputConns = outputConns + 1
                    end
                end
            end
        end

        -- Position X based on ratio of input vs output connections
        if totalConns > 0 then
            local ratio = outputConns / totalConns
            cells[id].x = leftBound + ratio * (rightBound - leftBound)
        end
    end

    -- Force-directed iterations: push apart close nodes, pull connected nodes
    for _ = 1, 4 do
        for i = 1, #hiddenIds do
            local id1 = hiddenIds[i]
            local c1 = cells[id1]

            -- Repulsion: push apart nodes that are too close
            for j = i + 1, #hiddenIds do
                local id2 = hiddenIds[j]
                local c2 = cells[id2]
                local dx = c2.x - c1.x
                local dy = c2.y - c1.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < 15 then
                    local force = (15 - dist) / 2
                    if dist > 0.1 then
                        c1.x = c1.x - dx / dist * force
                        c1.y = c1.y - dy / dist * force
                        c2.x = c2.x + dx / dist * force
                        c2.y = c2.y + dy / dist * force
                    else
                        c1.y = c1.y - force
                        c2.y = c2.y + force
                    end
                end
            end

            -- Clamp positions to display area
            c1.x = math.max(leftBound, math.min(rightBound, c1.x))
            c1.y = math.max(10, math.min(DISPLAY_HEIGHT - 10, c1.y))
        end
    end
end

--- Draw the neural network topology overlay on the BizHawk screen.
-- Renders input nodes (labeled with game state names), output nodes
-- (labeled with button names), hidden nodes, and connections between them.
-- @param genome table  The genome to visualize (must have .genes, optionally .network).
function NetworkDisplay.displayGenome(genome)
    if genome == nil then
        return
    end
    if genome.network == nil then
        return
    end

    local network = genome.network

    -- Draw semi-transparent background
    gui.drawBox(DISPLAY_X, DISPLAY_Y, DISPLAY_X + DISPLAY_WIDTH, DISPLAY_HEIGHT, BG_BORDER, BG_COLOR)

    -- Build cells table: neuron ID -> {x, y}
    local cells = {}

    -- Input labels
    local inputLabels = GameInputs.getInputLabels()
    -- Add "Bias" as the last label
    local allInputLabels = {}
    for i, label in ipairs(inputLabels) do
        allInputLabels[i] = label
    end
    allInputLabels[#allInputLabels + 1] = "Bias"

    -- Position input neurons vertically on the left
    local inputSpacing = (DISPLAY_HEIGHT - 20) / Config.Inputs
    for i = 1, Config.Inputs do
        local y = 10 + (i - 1) * inputSpacing + inputSpacing / 2
        cells[i] = { x = INPUT_X, y = y }
    end

    -- Position output neurons vertically on the right
    local outputSpacing = (DISPLAY_HEIGHT - 20) / Config.Outputs
    for o = 1, Config.Outputs do
        local id = Config.MaxNodes + o
        local y = 10 + (o - 1) * outputSpacing + outputSpacing / 2
        cells[id] = { x = OUTPUT_X, y = y }
    end

    -- Collect hidden neuron IDs
    local hiddenSet = {}
    local hiddenIds = {}
    for _, gene in ipairs(genome.genes) do
        local ids = { gene.into, gene.out }
        for _, nid in ipairs(ids) do
            if nid > Config.Inputs and nid <= Config.MaxNodes then
                if not hiddenSet[nid] then
                    hiddenSet[nid] = true
                    hiddenIds[#hiddenIds + 1] = nid
                end
            end
        end
    end
    table.sort(hiddenIds)

    -- Position hidden nodes
    positionHiddenNodes(genome, cells, hiddenIds)

    -- Draw connections
    for _, gene in ipairs(genome.genes) do
        local c1 = cells[gene.into]
        local c2 = cells[gene.out]
        if c1 and c2 then
            if gene.enabled then
                local color = weightToColor(gene.weight)
                gui.drawLine(
                    math.floor(c1.x), math.floor(c1.y),
                    math.floor(c2.x), math.floor(c2.y),
                    color
                )
            else
                -- Disabled genes: very faint gray
                gui.drawLine(
                    math.floor(c1.x), math.floor(c1.y),
                    math.floor(c2.x), math.floor(c2.y),
                    COLOR_DISABLED_GENE
                )
            end
        end
    end

    -- Draw input neurons with labels
    for i = 1, Config.Inputs do
        local c = cells[i]
        local neuron = network.neurons[i]
        local value = neuron and neuron.value or 0
        local fillColor = activationToColor(value)
        local labelColor = (math.abs(value) > 0.1) and COLOR_LABEL_ACTIVE or COLOR_LABEL

        gui.drawBox(
            math.floor(c.x - NODE_RADIUS), math.floor(c.y - NODE_RADIUS),
            math.floor(c.x + NODE_RADIUS), math.floor(c.y + NODE_RADIUS),
            COLOR_BORDER, fillColor
        )

        -- Label to the left of the node
        local label = allInputLabels[i] or ("I" .. i)
        gui.drawText(
            math.floor(c.x - NODE_RADIUS - 2), math.floor(c.y - 3),
            label, labelColor, LABEL_FONT_SIZE
        )
    end

    -- Draw output neurons with labels
    local buttonNames = Controller.getButtonNames()
    for o = 1, Config.Outputs do
        local id = Config.MaxNodes + o
        local c = cells[id]
        local neuron = network.neurons[id]
        local value = neuron and neuron.value or 0
        local isActive = value > 0

        local fillColor
        if isActive then
            fillColor = COLOR_OUTPUT_ACTIVE
        else
            fillColor = COLOR_OUTPUT_INACTIVE
        end

        gui.drawBox(
            math.floor(c.x - NODE_RADIUS), math.floor(c.y - NODE_RADIUS),
            math.floor(c.x + NODE_RADIUS), math.floor(c.y + NODE_RADIUS),
            COLOR_BORDER, fillColor
        )

        -- Label to the right of the node
        local label = buttonNames[o] or ("O" .. o)
        local labelColor = isActive and COLOR_OUTPUT_ACTIVE or COLOR_LABEL
        gui.drawText(
            math.floor(c.x + NODE_RADIUS + 3), math.floor(c.y - 3),
            label, labelColor, LABEL_FONT_SIZE
        )
    end

    -- Draw hidden neurons
    for _, id in ipairs(hiddenIds) do
        local c = cells[id]
        if c then
            local neuron = network.neurons[id]
            local value = neuron and neuron.value or 0
            local fillColor = activationToColor(value)

            gui.drawBox(
                math.floor(c.x - NODE_RADIUS), math.floor(c.y - NODE_RADIUS),
                math.floor(c.x + NODE_RADIUS), math.floor(c.y + NODE_RADIUS),
                COLOR_BORDER, fillColor
            )
        end
    end
end

--- Draw the network for the current genome (convenience alias).
-- @param genome table  The genome to visualize.
function NetworkDisplay.displayNetwork(genome)
    NetworkDisplay.displayGenome(genome)
end

return NetworkDisplay
