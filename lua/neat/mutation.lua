-- mutation.lua
-- All mutation operators for NEAT.
-- Provides point mutation (weight perturbation), link mutation (new connection),
-- node mutation (split connection), and enable/disable mutation.
--
-- Usage:
--   local Mutation = dofile("lua/neat/mutation.lua")
--   Mutation.mutate(genome, config, innovation)

local Mutation = {}

-- Lazy-load dependencies (resolved at call time via dofile paths set by caller)
local Network = nil
local GenomeMod = nil

--- Set module dependencies (called once by the test or main entry point).
-- @param networkMod table   The network module.
-- @param genomeMod  table   The genome module.
function Mutation.setDependencies(networkMod, genomeMod)
    Network = networkMod
    GenomeMod = genomeMod
end

--- Perturb or randomize weights of all genes.
-- With PerturbChance probability, perturb by StepSize * random.
-- Otherwise, randomize to a new weight in [-2, 2].
-- @param genome table  The genome to mutate.
-- @param config table  The NEAT config table.
function Mutation.pointMutate(genome, config)
    local step = genome.mutationRates.step
    for _, gene in ipairs(genome.genes) do
        if math.random() < config.PerturbChance then
            gene.weight = gene.weight + (math.random() * 2 - 1) * step
        else
            gene.weight = math.random() * 4 - 2
        end
    end
end

--- Check if a connection between two neurons already exists.
-- @param genes table     Array of genes.
-- @param into  integer   Source neuron ID.
-- @param out   integer   Destination neuron ID.
-- @return boolean
local function containsLink(genes, into, out)
    for _, gene in ipairs(genes) do
        if gene.into == into and gene.out == out then
            return true
        end
    end
    return false
end

--- Add a new connection between two previously unconnected neurons.
-- @param genome     table   The genome to mutate.
-- @param config     table   The NEAT config table.
-- @param innovation table   The innovation tracker.
-- @param forceBias  boolean If true, source is always the bias neuron.
function Mutation.linkMutate(genome, config, innovation, forceBias)
    -- Generate network to find valid neurons
    Network.generateNetwork(genome, config)

    -- Collect all neuron IDs
    local neuronIds = {}
    for id, _ in pairs(genome.network.neurons) do
        neuronIds[#neuronIds + 1] = id
    end

    -- Pick random source (or bias if forced)
    local neuron1
    if forceBias then
        neuron1 = config.Inputs  -- bias is the last input neuron
    else
        neuron1 = neuronIds[math.random(#neuronIds)]
    end

    -- Pick random target (must not be an input neuron)
    local nonInputIds = {}
    for _, id in ipairs(neuronIds) do
        if id > config.Inputs then
            nonInputIds[#nonInputIds + 1] = id
        end
    end
    if #nonInputIds == 0 then
        return  -- no valid targets
    end
    local neuron2 = nonInputIds[math.random(#nonInputIds)]

    -- Don't create self-connections or duplicate connections
    if neuron1 == neuron2 then
        return
    end
    if containsLink(genome.genes, neuron1, neuron2) then
        return
    end

    -- Create the new gene
    local newGene = GenomeMod.newGene()
    newGene.into = neuron1
    newGene.out = neuron2
    newGene.weight = math.random() * 4 - 2
    newGene.innovation = innovation.newInnovation()
    newGene.enabled = true

    genome.genes[#genome.genes + 1] = newGene
end

--- Split an existing connection: disable it and add two new connections
-- with a new hidden neuron in between.
-- Gene1: same source -> new neuron, weight 1.0
-- Gene2: new neuron -> same target, original weight
-- @param genome     table  The genome to mutate.
-- @param config     table  The NEAT config table.
-- @param innovation table  The innovation tracker.
function Mutation.nodeMutate(genome, config, innovation)
    if #genome.genes == 0 then
        return
    end

    -- Pick a random enabled gene
    local enabledGenes = {}
    for i, gene in ipairs(genome.genes) do
        if gene.enabled then
            enabledGenes[#enabledGenes + 1] = i
        end
    end
    if #enabledGenes == 0 then
        return
    end

    local geneIndex = enabledGenes[math.random(#enabledGenes)]
    local gene = genome.genes[geneIndex]

    -- Disable the original connection
    gene.enabled = false

    -- New neuron ID
    genome.maxneuron = genome.maxneuron + 1
    local newNeuronId = genome.maxneuron

    -- Gene 1: original source -> new neuron, weight 1.0
    local gene1 = GenomeMod.newGene()
    gene1.into = gene.into
    gene1.out = newNeuronId
    gene1.weight = 1.0
    gene1.enabled = true
    gene1.innovation = innovation.newInnovation()
    genome.genes[#genome.genes + 1] = gene1

    -- Gene 2: new neuron -> original target, original weight
    local gene2 = GenomeMod.newGene()
    gene2.into = newNeuronId
    gene2.out = gene.out
    gene2.weight = gene.weight
    gene2.enabled = true
    gene2.innovation = innovation.newInnovation()
    genome.genes[#genome.genes + 1] = gene2
end

--- Toggle a random gene's enabled state.
-- @param genome table    The genome to mutate.
-- @param enable boolean  If true, enable a disabled gene; if false, disable an enabled gene.
function Mutation.enableDisableMutate(genome, enable)
    local candidates = {}
    for _, gene in ipairs(genome.genes) do
        if gene.enabled ~= enable then
            candidates[#candidates + 1] = gene
        end
    end
    if #candidates == 0 then
        return
    end
    local gene = candidates[math.random(#candidates)]
    gene.enabled = enable
end

--- Apply all mutation operators with their configured probabilities.
-- This is the main mutation entry point called per genome per generation.
-- @param genome     table  The genome to mutate.
-- @param config     table  The NEAT config table.
-- @param innovation table  The innovation tracker.
function Mutation.mutate(genome, config, innovation)
    -- Perturb mutation rates
    for key, value in pairs(genome.mutationRates) do
        if math.random() < 0.5 then
            genome.mutationRates[key] = value * 0.95
        else
            genome.mutationRates[key] = value * 1.05263
        end
    end

    -- Weight mutations
    if math.random() < genome.mutationRates.connections then
        Mutation.pointMutate(genome, config)
    end

    -- Link mutations (can happen multiple times based on rate)
    local p = genome.mutationRates.link
    while p > 0 do
        if math.random() < p then
            Mutation.linkMutate(genome, config, innovation, false)
        end
        p = p - 1
    end

    -- Bias mutations
    p = genome.mutationRates.bias
    while p > 0 do
        if math.random() < p then
            Mutation.linkMutate(genome, config, innovation, true)
        end
        p = p - 1
    end

    -- Node mutations
    p = genome.mutationRates.node
    while p > 0 do
        if math.random() < p then
            Mutation.nodeMutate(genome, config, innovation)
        end
        p = p - 1
    end

    -- Enable/disable mutations
    if math.random() < genome.mutationRates.enable then
        Mutation.enableDisableMutate(genome, true)
    end
    if math.random() < genome.mutationRates.disable then
        Mutation.enableDisableMutate(genome, false)
    end
end

return Mutation
