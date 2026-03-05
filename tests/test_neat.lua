-- test_neat.lua
-- Automated tests for NEAT core operations.
-- Runs WITHOUT BizHawk (pure Lua 5.4/5.5).
-- Run from project root: lua tests/test_neat.lua
--
-- Tests validate: population init, forward pass, speciation, crossover,
-- mutation, innovation tracking, stagnation detection, generation advance.

-----------------------------------------------------------------------
-- Test framework
-----------------------------------------------------------------------
local passed = 0
local failed = 0
local total = 0

local function assert_eq(a, b, msg)
    total = total + 1
    if a == b then
        passed = passed + 1
    else
        failed = failed + 1
        print("  FAIL: " .. (msg or "?") .. " (expected=" .. tostring(b) .. " got=" .. tostring(a) .. ")")
    end
end

local function assert_true(cond, msg)
    total = total + 1
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("  FAIL: " .. (msg or "?") .. " (expected true, got false)")
    end
end

local function assert_neq(a, b, msg)
    total = total + 1
    if a ~= b then
        passed = passed + 1
    else
        failed = failed + 1
        print("  FAIL: " .. (msg or "?") .. " (expected not " .. tostring(b) .. ")")
    end
end

local function assert_gt(a, b, msg)
    total = total + 1
    if a > b then
        passed = passed + 1
    else
        failed = failed + 1
        print("  FAIL: " .. (msg or "?") .. " (expected " .. tostring(a) .. " > " .. tostring(b) .. ")")
    end
end

local function assert_gte(a, b, msg)
    total = total + 1
    if a >= b then
        passed = passed + 1
    else
        failed = failed + 1
        print("  FAIL: " .. (msg or "?") .. " (expected " .. tostring(a) .. " >= " .. tostring(b) .. ")")
    end
end

local function assert_lt(a, b, msg)
    total = total + 1
    if a < b then
        passed = passed + 1
    else
        failed = failed + 1
        print("  FAIL: " .. (msg or "?") .. " (expected " .. tostring(a) .. " < " .. tostring(b) .. ")")
    end
end

-----------------------------------------------------------------------
-- Load modules via dofile (BizHawk compatible)
-----------------------------------------------------------------------
local Config = dofile("lua/neat/config.lua")
local Innovation = dofile("lua/neat/innovation.lua")
local Genome = dofile("lua/neat/genome.lua")
local Network = dofile("lua/neat/network.lua")
local Mutation = dofile("lua/neat/mutation.lua")
local Crossover = dofile("lua/neat/crossover.lua")
local Species = dofile("lua/neat/species.lua")
local Pool = dofile("lua/neat/pool.lua")
local Fitness = dofile("lua/game/fitness.lua")

-- Set up module dependencies
Mutation.setDependencies(Network, Genome)
Crossover.setDependencies(Genome)
Pool.setDependencies(Genome, Species, Crossover, Mutation, Network)

-- Use small population for tests
local testConfig = {}
for k, v in pairs(Config) do
    testConfig[k] = v
end
testConfig.Population = 20

-- Seed RNG for reproducibility in tests
math.randomseed(42)

-----------------------------------------------------------------------
-- Test functions
-----------------------------------------------------------------------
local tests = {}

function tests.test_01_newGenome()
    print("Test 1: newGenome creates genome with proper defaults")
    Innovation.reset(0)
    local g = Genome.newGenome(Config)
    assert_eq(#g.genes, 0, "genes should be empty")
    assert_eq(g.maxneuron, 0, "maxneuron should be 0")
    assert_eq(g.fitness, 0, "fitness should be 0")
    assert_eq(g.globalRank, 0, "globalRank should be 0")
    assert_true(g.mutationRates ~= nil, "mutationRates should exist")
    assert_eq(g.mutationRates.connections, Config.MutateConnectionsChance, "connections rate")
    assert_eq(g.mutationRates.link, Config.LinkMutationChance, "link rate")
    assert_eq(g.mutationRates.node, Config.NodeMutationChance, "node rate")
    assert_eq(g.network, nil, "network should be nil initially")
end

function tests.test_02_newGene()
    print("Test 2: newGene creates gene with proper fields")
    local gene = Genome.newGene()
    assert_eq(gene.into, 0, "into should be 0")
    assert_eq(gene.out, 0, "out should be 0")
    assert_eq(gene.weight, 0.0, "weight should be 0.0")
    assert_eq(gene.enabled, true, "enabled should be true")
    assert_eq(gene.innovation, 0, "innovation should be 0")
end

function tests.test_03_copyGenome()
    print("Test 3: copyGenome produces independent deep copy")
    Innovation.reset(0)
    local orig = Genome.basicGenome(Config, Innovation)
    orig.fitness = 42
    local copy = Genome.copyGenome(orig)

    assert_eq(copy.fitness, 42, "copy should have same fitness")
    assert_eq(#copy.genes, #orig.genes, "copy should have same number of genes")
    assert_eq(copy.maxneuron, orig.maxneuron, "copy should have same maxneuron")

    -- Modify copy and verify original is unaffected
    copy.fitness = 999
    copy.genes[1].weight = 999.0
    assert_eq(orig.fitness, 42, "original fitness should be unchanged")
    assert_neq(orig.genes[1].weight, 999.0, "original gene weight should be unchanged")
end

function tests.test_04_innovation()
    print("Test 4: newInnovation returns incrementing unique numbers")
    Innovation.reset(0)
    local n1 = Innovation.newInnovation()
    local n2 = Innovation.newInnovation()
    local n3 = Innovation.newInnovation()
    assert_eq(n1, 1, "first innovation should be 1")
    assert_eq(n2, 2, "second innovation should be 2")
    assert_eq(n3, 3, "third innovation should be 3")
    assert_eq(Innovation.getCurrent(), 3, "current should be 3")

    Innovation.reset(100)
    local n4 = Innovation.newInnovation()
    assert_eq(n4, 101, "after reset to 100, next should be 101")
end

function tests.test_05_generateNetwork()
    print("Test 5: generateNetwork creates neurons and wires connections")
    Innovation.reset(0)
    local g = Genome.newGenome(Config)
    g.maxneuron = Config.Inputs

    -- Add 2 test genes
    local gene1 = Genome.newGene()
    gene1.into = 1
    gene1.out = Config.MaxNodes + 1
    gene1.weight = 0.5
    gene1.innovation = Innovation.newInnovation()
    g.genes[1] = gene1

    local gene2 = Genome.newGene()
    gene2.into = 2
    gene2.out = Config.MaxNodes + 1
    gene2.weight = -0.3
    gene2.innovation = Innovation.newInnovation()
    g.genes[2] = gene2

    Network.generateNetwork(g, Config)

    assert_true(g.network ~= nil, "network should be created")
    assert_true(g.network.neurons[1] ~= nil, "input neuron 1 should exist")
    assert_true(g.network.neurons[2] ~= nil, "input neuron 2 should exist")
    assert_true(g.network.neurons[Config.MaxNodes + 1] ~= nil, "output neuron should exist")
    assert_eq(#g.network.neurons[Config.MaxNodes + 1].incoming, 2, "output neuron should have 2 incoming")
end

function tests.test_06_evaluateNetwork()
    print("Test 6: evaluateNetwork with known weights produces expected sigmoid outputs")
    Innovation.reset(0)
    local g = Genome.newGenome(Config)
    g.maxneuron = Config.Inputs

    -- Single connection: input 1 -> output 1, weight 1.0
    local gene = Genome.newGene()
    gene.into = 1
    gene.out = Config.MaxNodes + 1
    gene.weight = 1.0
    gene.innovation = Innovation.newInnovation()
    g.genes[1] = gene

    Network.generateNetwork(g, Config)

    local inputs = {}
    for i = 1, Config.Inputs do inputs[i] = 0.0 end
    inputs[1] = 1.0  -- set input 1 to 1.0

    local outputs = Network.evaluateNetwork(g.network, inputs, Config)

    -- sigmoid(1.0 * 1.0) = 2/(1+exp(-4.9*1)) - 1 = 2/(1+0.00745) - 1 = 0.9852
    local expected = 2.0 / (1.0 + math.exp(-4.9 * 1.0)) - 1.0
    local diff = math.abs(outputs[1] - expected)
    assert_lt(diff, 0.001, "output should match sigmoid(1.0)")
end

function tests.test_07_sigmoid()
    print("Test 7: sigmoid(0) returns ~0 (NEAT sigmoid)")
    local result = Network.sigmoid(0)
    -- 2/(1+exp(0)) - 1 = 2/2 - 1 = 0
    assert_eq(result, 0.0, "sigmoid(0) should be 0")
end

function tests.test_08_pointMutate()
    print("Test 8: pointMutate changes at least one gene weight")
    Innovation.reset(0)
    local g = Genome.basicGenome(Config, Innovation)
    local originalWeights = {}
    for i, gene in ipairs(g.genes) do
        originalWeights[i] = gene.weight
    end

    Mutation.pointMutate(g, Config)

    local changed = false
    for i, gene in ipairs(g.genes) do
        if gene.weight ~= originalWeights[i] then
            changed = true
            break
        end
    end
    assert_true(changed, "at least one weight should change after pointMutate")
end

function tests.test_09_linkMutate()
    print("Test 9: linkMutate adds a new gene with new innovation number")
    Innovation.reset(0)
    local g = Genome.basicGenome(Config, Innovation)
    local geneCountBefore = #g.genes
    local innovBefore = Innovation.getCurrent()

    Mutation.linkMutate(g, Config, Innovation, false)

    -- May or may not add a gene (if it picks duplicate or self-connection)
    -- Try multiple times to ensure at least one succeeds
    for _ = 1, 10 do
        if #g.genes > geneCountBefore then break end
        Mutation.linkMutate(g, Config, Innovation, false)
    end

    assert_gt(#g.genes, geneCountBefore, "should have added at least one new gene")
    assert_gt(Innovation.getCurrent(), innovBefore, "innovation counter should have increased")
end

function tests.test_10_nodeMutate()
    print("Test 10: nodeMutate splits connection into two with new neuron")
    Innovation.reset(0)
    local g = Genome.basicGenome(Config, Innovation)
    local geneCountBefore = #g.genes
    local maxNeuronBefore = g.maxneuron

    Mutation.nodeMutate(g, Config, Innovation)

    assert_eq(#g.genes, geneCountBefore + 2, "should add 2 new genes")
    assert_eq(g.maxneuron, maxNeuronBefore + 1, "maxneuron should increment by 1")

    -- Verify the split: one original gene should be disabled
    local disabledCount = 0
    for _, gene in ipairs(g.genes) do
        if not gene.enabled then
            disabledCount = disabledCount + 1
        end
    end
    assert_gte(disabledCount, 1, "at least one gene should be disabled after nodeMutate")
end

function tests.test_11_crossover()
    print("Test 11: crossover merges two genomes correctly")
    Innovation.reset(0)
    local g1 = Genome.basicGenome(Config, Innovation)
    g1.fitness = 100

    -- Create g2 with overlapping and different innovation numbers
    local g2 = Genome.basicGenome(Config, Innovation)
    g2.fitness = 50

    local child = Crossover.crossover(g1, g2, Config)

    assert_true(child ~= nil, "child should be created")
    assert_gt(#child.genes, 0, "child should have genes")
    -- Child gets genes from fitter parent (g1) for disjoint/excess
    -- and from either parent for matching innovations
    assert_eq(child.maxneuron, math.max(g1.maxneuron, g2.maxneuron), "child maxneuron should be max of parents")
end

function tests.test_12_sameSpecies()
    print("Test 12: sameSpecies returns true for identical, false for different genomes")
    Innovation.reset(0)
    local g1 = Genome.basicGenome(Config, Innovation)
    local g1copy = Genome.copyGenome(g1)

    assert_true(Species.sameSpecies(g1, g1copy, Config), "identical genomes should be same species")

    -- Create a structurally different genome
    Innovation.reset(0)
    local g2 = Genome.basicGenome(Config, Innovation)
    -- Add many extra genes to make it structurally different
    for i = 1, 50 do
        local gene = Genome.newGene()
        gene.into = math.random(Config.Inputs)
        gene.out = Config.MaxNodes + math.random(Config.Outputs)
        gene.weight = math.random() * 4 - 2
        gene.innovation = Innovation.newInnovation() + 10000  -- very different innovation numbers
        g2.genes[#g2.genes + 1] = gene
    end

    -- With very different structures, they should NOT be same species
    -- (depends on DeltaThreshold, but 50 extra genes should exceed it)
    local result = Species.sameSpecies(g1, g2, Config)
    assert_true(not result, "structurally very different genomes should be different species")
end

function tests.test_13_rankGlobally()
    print("Test 13: rankGlobally assigns ranks (highest fitness = highest rank)")
    Innovation.reset(0)

    local pool = { species = {} }
    local sp1 = Species.newSpecies()
    local sp2 = Species.newSpecies()

    local g1 = Genome.newGenome(Config); g1.fitness = 10
    local g2 = Genome.newGenome(Config); g2.fitness = 50
    local g3 = Genome.newGenome(Config); g3.fitness = 30

    sp1.genomes = {g1, g2}
    sp2.genomes = {g3}
    pool.species = {sp1, sp2}

    Pool.rankGlobally(pool)

    -- g1(10) < g3(30) < g2(50) so ranks: g1=1, g3=2, g2=3
    assert_eq(g1.globalRank, 1, "lowest fitness should get rank 1")
    assert_eq(g3.globalRank, 2, "middle fitness should get rank 2")
    assert_eq(g2.globalRank, 3, "highest fitness should get rank 3")
end

function tests.test_14_cullSpecies()
    print("Test 14: cullSpecies removes bottom half")
    Innovation.reset(0)

    local pool = { species = {} }
    local sp = Species.newSpecies()
    for i = 1, 10 do
        local g = Genome.newGenome(Config)
        g.fitness = i * 10
        sp.genomes[#sp.genomes + 1] = g
    end
    pool.species = {sp}

    Species.cullSpecies(pool, false)

    assert_eq(#pool.species[1].genomes, 5, "should keep top 5 of 10")
    -- Verify kept genomes are the top ones (sorted descending by fitness)
    assert_eq(pool.species[1].genomes[1].fitness, 100, "best should be first")
    assert_eq(pool.species[1].genomes[5].fitness, 60, "5th should be 60")
end

function tests.test_15_removeStaleSpecies()
    print("Test 15: removeStaleSpecies removes species past StaleSpecies generations")
    Innovation.reset(0)

    local pool = { species = {} }

    -- Fresh species (staleness 0)
    local sp1 = Species.newSpecies()
    local g1 = Genome.newGenome(Config); g1.fitness = 100
    sp1.genomes = {g1}
    sp1.topFitness = 50  -- will improve to 100

    -- Stale species (staleness at limit)
    local sp2 = Species.newSpecies()
    local g2 = Genome.newGenome(Config); g2.fitness = 10
    sp2.genomes = {g2}
    sp2.staleness = Config.StaleSpecies  -- at the limit
    sp2.topFitness = 20  -- current best is 10, less than topFitness 20

    pool.species = {sp1, sp2}

    Species.removeStaleSpecies(pool, Config)

    assert_eq(#pool.species, 1, "stale species should be removed")
    assert_eq(pool.species[1].genomes[1].fitness, 100, "fresh species should survive")
end

function tests.test_16_newPool()
    print("Test 16: newPool initializes population with correct size and species")
    Innovation.reset(0)

    local pool = Pool.newPool(testConfig, Innovation)

    -- Count total genomes
    local totalGenomes = 0
    for _, species in ipairs(pool.species) do
        totalGenomes = totalGenomes + #species.genomes
    end

    assert_eq(totalGenomes, testConfig.Population, "total genomes should equal Population")
    assert_gte(#pool.species, 1, "should have at least 1 species")
    assert_eq(pool.generation, 0, "generation should start at 0")
end

function tests.test_17_newGeneration()
    print("Test 17: newGeneration produces same-size population with elitism")
    Innovation.reset(0)

    local pool = Pool.newPool(testConfig, Innovation)

    -- Assign random fitness to all genomes
    local bestFitness = 0
    for _, species in ipairs(pool.species) do
        for _, genome in ipairs(species.genomes) do
            genome.fitness = math.random() * 100
            if genome.fitness > bestFitness then
                bestFitness = genome.fitness
            end
        end
    end

    Pool.newGeneration(pool, testConfig, Innovation)

    -- Count total genomes in new generation
    local totalGenomes = 0
    for _, species in ipairs(pool.species) do
        totalGenomes = totalGenomes + #species.genomes
    end

    assert_eq(totalGenomes, testConfig.Population, "new generation should have same population size")
    assert_eq(pool.generation, 1, "generation should be 1")
    assert_gte(#pool.species, 1, "should have at least 1 species after new generation")
end

-- Fitness function tests
function tests.test_18_fitness_win()
    print("Test 18: Fitness rewards winning with damage dealt")
    local score = Fitness.calculateFitness({
        startP1HP = 100, endP1HP = 80,     -- took 20 damage
        startP2HP = 100, endP2HP = 60,     -- dealt 40 damage
        roundResult = Fitness.WIN,
        frameCount = 1000,
        lastDamageFrame = 900,
    })
    assert_gt(score, 0, "winning with net damage should be positive")
    assert_gt(score, 1000, "should include win bonus of 1000")
end

function tests.test_19_fitness_loss_penalty()
    print("Test 19: Fitness penalizes losing")
    local score = Fitness.calculateFitness({
        startP1HP = 100, endP1HP = 0,      -- KO'd
        startP2HP = 100, endP2HP = 90,     -- barely scratched
        roundResult = Fitness.LOSE,
        frameCount = 500,
        lastDamageFrame = 200,
    })
    assert_lt(score, 0, "losing badly should be negative (floored to -1)")
    assert_eq(score, -1, "negative fitness should be floored to -1")
end

function tests.test_20_fitness_antistall()
    print("Test 20: Fitness penalizes stalling")
    local scoreActive = Fitness.calculateFitness({
        startP1HP = 100, endP1HP = 100,
        startP2HP = 100, endP2HP = 50,     -- dealt 50 damage
        roundResult = Fitness.IN_PROGRESS,
        frameCount = 500,
        lastDamageFrame = 490,             -- very recent damage
    })

    local scoreStall = Fitness.calculateFitness({
        startP1HP = 100, endP1HP = 100,
        startP2HP = 100, endP2HP = 50,     -- same damage
        roundResult = Fitness.IN_PROGRESS,
        frameCount = 2000,
        lastDamageFrame = 100,             -- no damage for 1900 frames
    })

    assert_gt(scoreActive, scoreStall, "active fighting should score higher than stalling")
end

function tests.test_21_fitness_selfDestruction_guard()
    print("Test 21: Fitness guards against crediting opponent self-destruction")
    local scoreWithGuard = Fitness.calculateFitness({
        startP1HP = 100, endP1HP = 100,
        startP2HP = 100, endP2HP = 20,     -- opponent lost 80 HP
        roundResult = Fitness.IN_PROGRESS,
        frameCount = 500,
        lastDamageFrame = 400,
        damageDealtByBot = 30,             -- bot only dealt 30 of the 80
    })

    local scoreWithoutGuard = Fitness.calculateFitness({
        startP1HP = 100, endP1HP = 100,
        startP2HP = 100, endP2HP = 20,     -- same HP loss
        roundResult = Fitness.IN_PROGRESS,
        frameCount = 500,
        lastDamageFrame = 400,
        -- no damageDealtByBot: credits all 80
    })

    assert_lt(scoreWithGuard, scoreWithoutGuard, "guarded score should be lower than unguarded")
end

-- JSON test
function tests.test_22_json()
    print("Test 22: dkjson encode/decode round-trips correctly")
    local json = dofile("lua/lib/dkjson.lua")
    local data = {
        name = "test",
        value = 42,
        nested = {1, 2, 3},
        flag = true,
    }
    local encoded = json.encode(data)
    local decoded = json.decode(encoded)
    assert_eq(decoded.name, "test", "string round-trip")
    assert_eq(decoded.value, 42, "number round-trip")
    assert_eq(decoded.flag, true, "boolean round-trip")
    assert_eq(#decoded.nested, 3, "array length round-trip")
    assert_eq(decoded.nested[2], 2, "array element round-trip")
end

-----------------------------------------------------------------------
-- Run all tests
-----------------------------------------------------------------------
print("=== NEAT Algorithm Tests ===")
print()

local testNames = {}
for name in pairs(tests) do
    testNames[#testNames + 1] = name
end
table.sort(testNames)

local testsPassed = 0
local testsFailed = 0

for _, name in ipairs(testNames) do
    local prevFailed = failed
    local ok, err = pcall(tests[name])
    if not ok then
        print("  ERROR: " .. name .. ": " .. tostring(err))
        failed = failed + 1
        total = total + 1
        testsFailed = testsFailed + 1
    else
        if failed > prevFailed then
            testsFailed = testsFailed + 1
        else
            testsPassed = testsPassed + 1
        end
    end
end

print()
print(string.format("=== Results: %d/%d assertions passed ===", passed, total))
print(string.format("=== Tests: %d/%d test functions passed ===", testsPassed, testsPassed + testsFailed))

if failed > 0 then
    print("SOME TESTS FAILED")
    os.exit(1)
else
    print("ALL TESTS PASSED")
end
