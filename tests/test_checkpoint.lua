-- test_checkpoint.lua
-- Automated tests for checkpoint serialization round-trip and combo logger.
-- Runs without BizHawk: lua5.4 tests/test_checkpoint.lua

-- Track test results
local passed = 0
local failed = 0
local total = 0

local function assert_eq(actual, expected, msg)
    total = total + 1
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
        print("  expected: " .. tostring(expected))
        print("  actual:   " .. tostring(actual))
    end
end

local function assert_true(val, msg)
    total = total + 1
    if val then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
        print("  expected: true")
        print("  actual:   " .. tostring(val))
    end
end

local function assert_near(actual, expected, tolerance, msg)
    total = total + 1
    if math.abs(actual - expected) < tolerance then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
        print("  expected: " .. tostring(expected) .. " +/- " .. tostring(tolerance))
        print("  actual:   " .. tostring(actual))
    end
end

local function section(name)
    print("\n--- " .. name .. " ---")
end

-- Stub out console.log for non-BizHawk
if not console then
    console = { log = function(msg) end }
end

-- Load modules under test
local json = dofile("lua/lib/dkjson.lua")
local Checkpoint = dofile("lua/training/checkpoint.lua")
local ComboLogger = dofile("lua/training/combo_logger.lua")
local Innovation = dofile("lua/neat/innovation.lua")

-- ============================================================
-- CHECKPOINT TESTS
-- ============================================================

section("Checkpoint: saveCheckpoint writes valid JSON")

-- Build a mock pool with 2 species, 3 genomes each, 5 genes per genome
local function buildMockPool()
    Innovation.reset(0)
    local pool = {
        generation = 42,
        maxFitness = 1234.5,
        species = {},
    }
    for s = 1, 2 do
        local species = {
            topFitness = 100 * s,
            staleness = s * 2,
            genomes = {},
        }
        for g = 1, 3 do
            local genome = {
                maxneuron = 11 + g,
                fitness = 50 * g + 10 * s,
                mutationRates = {
                    connections = 0.25,
                    link = 2.0,
                    node = 0.50,
                    bias = 0.40,
                    step = 0.1,
                    disable = 0.4,
                    enable = 0.2,
                },
                genes = {},
            }
            for i = 1, 5 do
                local inn = Innovation.newInnovation()
                genome.genes[#genome.genes + 1] = {
                    into = i,
                    out = 1000001 + ((g - 1) * 5 + i) % 8,
                    weight = (i * 0.3 - 0.5) * (s == 1 and 1 or -1),
                    enabled = (i % 3 ~= 0),
                    innovation = inn,
                }
            end
            species.genomes[#species.genomes + 1] = genome
        end
        pool.species[#pool.species + 1] = species
    end
    return pool
end

local mockPool = buildMockPool()
local tmpFile = os.tmpname()

-- Test: save creates a valid JSON file
Checkpoint.saveCheckpoint(mockPool, tmpFile)
local f = io.open(tmpFile, "r")
assert_true(f ~= nil, "saveCheckpoint creates a file")
local content = f:read("*all")
f:close()

local data = json.decode(content)
assert_true(data ~= nil, "saved file contains valid JSON")
assert_eq(data.generation, 42, "JSON contains correct generation")
assert_eq(data.maxFitness, 1234.5, "JSON contains correct maxFitness")
assert_true(data.species ~= nil, "JSON contains species array")
assert_eq(#data.species, 2, "JSON has 2 species")

-- ============================================================
section("Checkpoint: loadCheckpoint reconstructs pool")

local loaded = Checkpoint.loadCheckpoint(tmpFile)
assert_eq(loaded.generation, 42, "loaded generation matches")
assert_eq(loaded.maxFitness, 1234.5, "loaded maxFitness matches")
assert_eq(#loaded.species, 2, "loaded species count matches")

local totalGenomes = 0
for _, sp in ipairs(loaded.species) do
    totalGenomes = totalGenomes + #sp.genomes
end
assert_eq(totalGenomes, 6, "loaded total genome count matches (2*3)")

-- ============================================================
section("Checkpoint: round-trip preserves gene fields")

for s = 1, #mockPool.species do
    for g = 1, #mockPool.species[s].genomes do
        local origGenome = mockPool.species[s].genomes[g]
        local loadGenome = loaded.species[s].genomes[g]
        for i = 1, #origGenome.genes do
            local origGene = origGenome.genes[i]
            local loadGene = loadGenome.genes[i]
            local prefix = "s" .. s .. "g" .. g .. "gene" .. i
            assert_eq(loadGene.into, origGene.into, prefix .. " into")
            assert_eq(loadGene.out, origGene.out, prefix .. " out")
            assert_near(loadGene.weight, origGene.weight, 0.0001, prefix .. " weight")
            assert_eq(loadGene.enabled, origGene.enabled, prefix .. " enabled")
            assert_eq(loadGene.innovation, origGene.innovation, prefix .. " innovation")
        end
    end
end

-- ============================================================
section("Checkpoint: round-trip preserves mutationRates")

for s = 1, #mockPool.species do
    for g = 1, #mockPool.species[s].genomes do
        local origRates = mockPool.species[s].genomes[g].mutationRates
        local loadRates = loaded.species[s].genomes[g].mutationRates
        local prefix = "s" .. s .. "g" .. g .. " mutationRates."
        for key, val in pairs(origRates) do
            assert_near(loadRates[key], val, 0.0001, prefix .. key)
        end
    end
end

-- ============================================================
section("Checkpoint: innovation counter restored correctly (Pitfall 2)")

-- After loading, innovation counter should be >= max innovation in any gene
local maxInnov = 0
for _, sp in ipairs(loaded.species) do
    for _, genome in ipairs(sp.genomes) do
        for _, gene in ipairs(genome.genes) do
            if gene.innovation > maxInnov then
                maxInnov = gene.innovation
            end
        end
    end
end
assert_true(Innovation.getCurrent() >= maxInnov,
    "innovation counter (" .. Innovation.getCurrent() .. ") >= max gene innovation (" .. maxInnov .. ")")

-- ============================================================
section("Checkpoint: getCheckpointFilename")

local fname = Checkpoint.getCheckpointFilename(17)
assert_true(string.find(fname, "gen_17") ~= nil, "filename contains gen_17")
assert_true(string.find(fname, ".json") ~= nil, "filename ends with .json")

-- ============================================================
-- COMBO LOGGER TESTS
-- ============================================================

section("ComboLogger: newLogger creates empty log")

local logger = ComboLogger.newLogger()
assert_eq(#logger.log, 0, "new logger has empty log")
assert_eq(logger.frameCount, 0, "new logger has zero frameCount")

-- ============================================================
section("ComboLogger: record appends entries")

ComboLogger.record(logger, {A=true, B=false, L=false, R=false, Up=false, Down=false, Left=false, Right=false})
ComboLogger.record(logger, {A=false, B=true, L=false, R=false, Up=false, Down=false, Left=false, Right=false})
assert_eq(#logger.log, 2, "after 2 records, log has 2 entries")
assert_eq(logger.frameCount, 2, "frameCount is 2 after 2 records")

-- ============================================================
section("ComboLogger: analyzeInputLog with repeated inputs => low entropy")

local repeatedLog = {}
local sameButtons = {A=true, B=false, L=false, R=false, Up=false, Down=false, Left=false, Right=false}
for i = 1, 100 do
    repeatedLog[i] = sameButtons
end
local analysisRepeat = ComboLogger.analyzeInputLog(repeatedLog)
assert_true(analysisRepeat.entropy < 1.5,
    "repeated inputs have low entropy: " .. tostring(analysisRepeat.entropy))
assert_true(analysisRepeat.isButtonMashing, "repeated inputs flagged as button mashing")

-- ============================================================
section("ComboLogger: analyzeInputLog with varied inputs => higher entropy")

local variedLog = {}
local buttonNames = {"A", "B", "L", "R", "Up", "Down", "Left", "Right"}
math.randomseed(12345)
for i = 1, 100 do
    local buttons = {}
    for _, name in ipairs(buttonNames) do
        buttons[name] = math.random() > 0.5
    end
    variedLog[i] = buttons
end
local analysisVaried = ComboLogger.analyzeInputLog(variedLog)
assert_true(analysisVaried.entropy > 1.5,
    "varied inputs have higher entropy: " .. tostring(analysisVaried.entropy))
assert_true(not analysisVaried.isButtonMashing, "varied inputs NOT flagged as button mashing")

-- ============================================================
section("ComboLogger: analyzeInputLog returns top 10 patterns sorted by frequency")

assert_true(#analysisRepeat.topPatterns <= 10, "topPatterns has at most 10 entries")
assert_true(#analysisRepeat.topPatterns >= 1, "topPatterns has at least 1 entry")

-- Verify sorting: first entry should have highest count
if #analysisRepeat.topPatterns >= 2 then
    assert_true(analysisRepeat.topPatterns[1].count >= analysisRepeat.topPatterns[2].count,
        "topPatterns sorted by frequency descending")
end

-- ============================================================
-- CLEANUP
-- ============================================================
os.remove(tmpFile)

-- ============================================================
-- RESULTS
-- ============================================================
print("\n========================================")
print(string.format("Results: %d/%d passed, %d failed", passed, total, failed))
print("========================================")

if failed > 0 then
    os.exit(1)
else
    print("ALL TESTS PASSED")
    os.exit(0)
end
