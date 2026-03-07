-- network.lua
-- Neural network construction and forward pass for NEAT.
-- Builds a network from a genome's genes and evaluates inputs through it.
--
-- Usage:
--   local Network = dofile("lua/neat/network.lua")
--   Network.generateNetwork(genome, config)
--   local outputs = Network.evaluateNetwork(genome.network, inputs, config)

local Network = {}

--- NEAT sigmoid activation function.
-- Maps to approximately [-1, 1] range with a steep slope.
-- @param x number  Input value.
-- @return number   Activated value.
function Network.sigmoid(x)
    return 2.0 / (1.0 + math.exp(-4.9 * x)) - 1.0
end

--- Build the neural network from a genome's genes.
-- Creates a neurons table indexed by neuron ID.
-- Input neurons: 1..Inputs
-- Output neurons: MaxNodes+1..MaxNodes+Outputs
-- Hidden neurons: discovered from genes
-- Each neuron: {incoming={}, value=0.0}
--
-- @param genome table  The genome to build from.
-- @param config table  The NEAT config table.
function Network.generateNetwork(genome, config)
    local network = {}
    network.neurons = {}

    -- Create input neurons
    for i = 1, config.Inputs do
        network.neurons[i] = { incoming = {}, value = 0.0 }
    end

    -- Create output neurons
    for o = 1, config.Outputs do
        network.neurons[config.MaxNodes + o] = { incoming = {}, value = 0.0 }
    end

    -- Sort genes by out neuron for consistent evaluation order
    table.sort(genome.genes, function(a, b)
        return a.out < b.out
    end)

    -- Create hidden neurons and wire connections from enabled genes
    for _, gene in ipairs(genome.genes) do
        if gene.enabled then
            if not network.neurons[gene.out] then
                network.neurons[gene.out] = { incoming = {}, value = 0.0 }
            end
            if not network.neurons[gene.into] then
                network.neurons[gene.into] = { incoming = {}, value = 0.0 }
            end
            local neuron = network.neurons[gene.out]
            neuron.incoming[#neuron.incoming + 1] = {
                into = gene.into,
                weight = gene.weight,
            }
        end
    end

    genome.network = network
end

--- Forward pass: compute output values from input values.
-- Sets input neuron values, then iterates all neurons computing
-- value = sigmoid(sum(weight * incoming_value)).
-- Uses the MarI/O pattern: iterate all neurons in order.
--
-- @param network table   The network (from generateNetwork).
-- @param inputs  table   Array of input values (length == config.Inputs).
-- @param config  table   The NEAT config table.
-- @return table  Array of output neuron values (length == config.Outputs).
function Network.evaluateNetwork(network, inputs, config)
    -- Set input neuron values
    for i = 1, config.Inputs do
        network.neurons[i].value = inputs[i]
    end

    -- Evaluate all non-input neurons.
    -- A single pass with numeric sort doesn't guarantee topological order for
    -- deep hidden chains (hidden neuron IDs are assigned incrementally but
    -- connections can point backward). Two passes handle chains up to 2 hidden
    -- layers deep, which covers most NEAT networks.
    local neuronIds = {}
    for id, _ in pairs(network.neurons) do
        if id > config.Inputs then
            neuronIds[#neuronIds + 1] = id
        end
    end
    table.sort(neuronIds)

    for _pass = 1, 2 do
        for _, id in ipairs(neuronIds) do
            local neuron = network.neurons[id]
            local sum = 0
            for _, incoming in ipairs(neuron.incoming) do
                local other = network.neurons[incoming.into]
                if other then
                    sum = sum + incoming.weight * other.value
                end
            end
            if #neuron.incoming > 0 then
                neuron.value = Network.sigmoid(sum)
            end
        end
    end

    -- Collect outputs
    local outputs = {}
    for o = 1, config.Outputs do
        outputs[o] = network.neurons[config.MaxNodes + o].value
    end

    return outputs
end

return Network
