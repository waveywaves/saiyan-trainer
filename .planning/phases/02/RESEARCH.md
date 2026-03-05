# Phase 2: NEAT Training Engine - Research

**Researched:** 2026-03-06
**Domain:** Neuroevolution (NEAT algorithm) in Lua for BizHawk GBA fighting game bot
**Confidence:** MEDIUM-HIGH

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| NEAT-01 | NEAT population initialization with configurable population size | MarI/O architecture: `Population = 300`, `newPool()` creates initial genomes with `basicGenome()` |
| NEAT-02 | Neural network forward pass computes outputs from memory map inputs | MarI/O `evaluateNetwork()` with sigmoid activation, adapted for fighting game input vector |
| NEAT-03 | Speciation groups genomes by structural compatibility distance | MarI/O `sameSpecies()` using `DeltaDisjoint`, `DeltaWeights`, `DeltaThreshold` |
| NEAT-04 | Selection within species based on adjusted fitness | MarI/O `rankGlobally()` + `calculateAverageFitness()` with fitness sharing |
| NEAT-05 | Crossover produces offspring from two parent genomes | MarI/O `crossover()` -- matching genes random, disjoint/excess from fitter parent |
| NEAT-06 | Structural mutation adds new nodes and connections | MarI/O `linkMutate()` and `nodeMutate()` with innovation tracking |
| NEAT-07 | Weight mutation perturbs connection weights | MarI/O `pointMutate()` with perturbation and random reset |
| NEAT-08 | Innovation number tracking prevents structural duplication | MarI/O `pool.innovation` global counter, assigned per new gene |
| NEAT-09 | Stagnation detection removes species that stop improving | MarI/O `StaleSpecies = 15` with `species.staleness` counter; increase to 30-50 for fighting game |
| FIT-01 | Fitness rewards damage dealt to opponent | Multi-component fitness: `damage_dealt * W1` -- verified by fighting game NEAT research |
| FIT-02 | Fitness penalizes damage taken from opponent | Multi-component fitness: `- damage_taken * W2` |
| FIT-03 | Fitness gives large bonus for winning a round | `+ round_won_bonus * W3` (e.g., +1000) |
| FIT-04 | Fitness gives large penalty for losing a round | `- round_lost_penalty * W4` (e.g., -500) |
| FIT-05 | Fitness penalizes excessive time without action (anti-stalling) | Time-based penalty component; track frames without damage dealt |
| FIT-06 | Fitness depends on bot's own actions, not opponent self-destruction | Track `damage_dealt_by_bot` separately from `opponent_hp_lost`; use delta-based measurement |
| LOOP-01 | Generation loop evaluates all genomes in population against CPU opponent | MarI/O main loop pattern: iterate species/genomes, evaluate each, advance generation |
| LOOP-02 | Each genome evaluation starts from an identical save state | `savestate.load(SavestateFile)` at start of each evaluation |
| LOOP-03 | Genome serialization saves full population state to JSON | dkjson library for JSON encode/decode; save species, genomes, innovation counter |
| LOOP-04 | Training can resume from a saved JSON checkpoint | Load JSON, reconstruct pool with all state including innovation numbers |
| LOOP-05 | Best genome of each generation is preserved (elitism) | Copy best genome to next generation unchanged during `newGeneration()` |
| VIS-01 | Neural network overlay displays evolved topology on BizHawk screen | MarI/O `displayGenome()` pattern using `gui.drawBox`, `gui.drawLine`, `gui.drawText` |
| VIS-02 | Overlay shows which neurons are active and connection weights | Color-coded connections (green=positive, red=negative), brightness=activation |
| VIS-03 | Species timeline graph shows species emergence, growth, and extinction | Track species IDs and sizes per generation; render as stacked bar or timeline |
| OPP-01 | Training rotates through multiple CPU difficulty levels | Save states at different difficulty settings; cycle per generation or per N generations |
| OPP-02 | Training can be configured to use different opponent characters | Multiple save states per character; configuration table for opponent rotation |
| COMBO-01 | Input logger records button sequences during evaluation fights | Append each frame's `joypad.set` inputs to a log table during evaluation |
| COMBO-02 | Analysis tool identifies most frequent button patterns | Sliding window pattern matching on input log; count n-gram frequencies |
| COMBO-03 | Analysis reports whether bot learned real fighting strategies vs button mashing | Compare pattern entropy and specific known combo sequences against random baseline |
</phase_requirements>

## Summary

Phase 2 implements the complete NEAT neuroevolution engine in Lua running inside BizHawk. This is the core intellectual work of the project: the algorithm that evolves neural networks to fight in DBZ Supersonic Warriors. The established pattern is MarI/O by SethBling -- a single-file Lua NEAT implementation (~1200 lines) that runs entirely within BizHawk's Lua scripting environment. The code structure is well-understood through the original source and multiple community forks (NEATEvolve, Neat-Genetic-Mario, MarioKart64NEAT).

The primary challenge unique to this phase is adapting MarI/O's architecture from a platformer (single objective: go right) to a fighting game (multi-objective: deal damage, avoid damage, win rounds, manage ki). This affects three critical design decisions: (1) the input vector design -- replacing MarI/O's 13x13 tile grid with structured game state from the memory map (health, ki, positions, attack states), (2) the output vector design -- GBA fighting game requires 10 button outputs with simultaneous combinations (Down+B, R+A+B for specials), and (3) the fitness function -- which must use multi-component weighted scoring to avoid degenerate strategies like "always block" or "spam one move." Research from multi-objective NEAT papers and fighting game AI competitions confirms that naive single-scalar fitness produces convergence on degenerate behaviors.

The secondary challenge is genome serialization. MarI/O's original save/load was broken (crashed on load). The NEATEvolve fork fixed this by saving the full `pool.species` table to a separate file. For this project, use JSON serialization via the dkjson pure-Lua library, which handles nested tables natively and produces human-readable, cross-language-compatible output.

**Primary recommendation:** Fork the MarI/O NEAT architecture (data structures, speciation, crossover, mutation, innovation tracking) but completely replace the input/output/fitness layers for the fighting game domain. Use dkjson for genome serialization. Increase `StaleSpecies` from 15 to 30-50 and implement dynamic compatibility threshold to prevent premature convergence.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| BizHawk Lua API | 5.4 (bundled) | Emulator scripting, memory reads, joypad control, GUI overlay | Only option -- BizHawk dictates Lua version. All MarI/O-pattern projects use this. |
| Custom NEAT (MarI/O-derived) | N/A | Complete NEAT algorithm in Lua | Battle-tested across dozens of game bot projects. LuaNEAT is dead (2018). neat-python adds IPC overhead. |
| dkjson | 2.8+ | JSON encode/decode for genome serialization | Pure Lua, no dependencies, handles nested tables. Works in BizHawk's sandboxed Lua environment. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| BizHawk `gui.*` | built-in | Neural network visualization overlay | VIS-01, VIS-02 -- draw nodes, connections, activation values on emulator screen |
| BizHawk `memory.*` | built-in | Read game state from GBA RAM | Every frame during evaluation -- health, ki, positions, attack states (from Phase 1) |
| BizHawk `joypad.*` | built-in | Send NEAT outputs as controller inputs | Every frame -- translate output neurons to button presses |
| BizHawk `savestate.*` | built-in | Reset fight state between evaluations | LOOP-02 -- load identical state before each genome evaluation |
| BizHawk `emu.*` | built-in | Frame advance control | Main loop heartbeat -- `emu.frameadvance()` drives the training loop |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom NEAT in Lua | neat-python via LuaSocket bridge | Avoids reimplementation but adds ~10ms latency per frame from IPC. Fighting game timing is frame-sensitive. |
| dkjson | Lua `dofile` (NEATEvolve approach) | NEATEvolve saves pool as Lua code (`species.lua`). Works but not cross-language compatible and allows code injection. |
| dkjson | lunajson | Slightly faster decoding but less mature. dkjson is the Lua community standard. |
| Single-file script | Multi-file module system | MarI/O is single-file. For this project's complexity, split into modules (neat.lua, fitness.lua, vis.lua, etc.). |

**Installation:**
```
-- dkjson is a single .lua file, no package manager needed
-- Download dkjson.lua from http://dkolf.de/dkjson-lua/
-- Place in BizHawk root directory alongside training script
```

## Architecture Patterns

### Recommended Project Structure
```
lua/
  neat/
    config.lua          # All NEAT hyperparameters and game-specific settings
    genome.lua          # Genome, Gene data structures and operations
    species.lua         # Species management, compatibility distance
    pool.lua            # Population pool, generation management
    network.lua         # Neural network construction and forward pass
    mutation.lua        # All mutation operators (point, link, node, enable/disable)
    crossover.lua       # Crossover operator
    innovation.lua      # Global innovation number tracker
  game/
    memory_map.lua      # GBA memory addresses (from Phase 1)
    inputs.lua          # Read game state, construct NEAT input vector
    controller.lua      # Translate NEAT outputs to joypad buttons
    fitness.lua         # Multi-component fitness calculation
  training/
    loop.lua            # Main training loop (generation evaluation cycle)
    checkpoint.lua      # JSON save/load using dkjson
    combo_logger.lua    # Input sequence recording and analysis
  vis/
    network_display.lua # Neural network overlay (MarI/O displayGenome pattern)
    species_timeline.lua # Species emergence/extinction visualization
    hud.lua             # Generation stats, fitness display
  lib/
    dkjson.lua          # JSON library (vendored, single file)
  main.lua              # Entry point, loaded by BizHawk
```

### Pattern 1: MarI/O Main Loop (adapted for fighting game)
**What:** Frame-by-frame evaluation loop that reads game state, runs network forward pass, sends controller inputs, and checks termination conditions.
**When to use:** The core training loop -- every genome evaluation follows this pattern.
**Example:**
```lua
-- Source: MarI/O neatevolve.lua main loop, adapted for fighting game
function evaluateGenome(genome)
    savestate.load(SavestateFile)
    generateNetwork(genome)

    local startP2HP = readP2Health()
    local startP1HP = readP1Health()
    local frameCount = 0
    local lastDamageFrame = 0
    local inputLog = {}

    while true do
        -- Read game state (Phase 1 memory map)
        local inputs = getGameInputs()  -- HP, Ki, positions, attack states

        -- Forward pass
        local outputs = evaluateNetwork(genome.network, inputs)

        -- Convert outputs to buttons
        local buttons = outputsToButtons(outputs)
        joypad.set(buttons, 1)

        -- Log inputs for combo analysis
        inputLog[#inputLog + 1] = buttons

        -- Check termination: round over, timeout, or stall
        local roundState = readRoundState()
        frameCount = frameCount + 1

        if roundState == ROUND_OVER or frameCount > MAX_EVAL_FRAMES then
            break
        end

        -- Track last damage frame for stall detection
        local currentP2HP = readP2Health()
        if currentP2HP < startP2HP then
            lastDamageFrame = frameCount
        end

        emu.frameadvance()
    end

    -- Calculate multi-component fitness
    genome.fitness = calculateFitness(startP1HP, readP1Health(),
                                       startP2HP, readP2Health(),
                                       readRoundState(), frameCount,
                                       lastDamageFrame)
    genome.inputLog = inputLog
end
```

### Pattern 2: Multi-Component Fighting Game Fitness
**What:** Weighted sum of offense, defense, and outcome metrics that avoids degenerate convergence.
**When to use:** After every genome evaluation to assign fitness.
**Example:**
```lua
-- Source: Multi-objective NEAT research + FightLadder dense reward pattern
function calculateFitness(startP1HP, endP1HP, startP2HP, endP2HP,
                           roundResult, frameCount, lastDamageFrame)
    local damageDealt = startP2HP - endP2HP
    local damageTaken = startP1HP - endP1HP

    local fitness = 0

    -- Offense reward (primary driver)
    fitness = fitness + damageDealt * 2.0

    -- Defense penalty
    fitness = fitness - damageTaken * 1.5

    -- Round outcome bonuses
    if roundResult == WIN then
        fitness = fitness + 1000
    elseif roundResult == LOSE then
        fitness = fitness - 500
    end

    -- Anti-stalling: penalize time without dealing damage
    local stallFrames = frameCount - lastDamageFrame
    if stallFrames > 300 then  -- ~5 seconds at 60fps
        fitness = fitness - (stallFrames - 300) * 0.5
    end

    -- Ensure fitness depends on bot's actions, not opponent self-destruction
    -- damageDealt is measured from P2 HP delta, which only changes from hits

    -- Floor at -1 to avoid zero (which MarI/O uses as "not evaluated")
    if fitness <= 0 then
        fitness = -1
    end

    return fitness
end
```

### Pattern 3: NEAT Output to GBA Button Mapping
**What:** Maps NEAT output neurons (sigmoid values 0-1) to GBA button presses, supporting simultaneous combinations.
**When to use:** Every frame, converting neural network outputs to controller inputs.
**Example:**
```lua
-- Source: BizHawk joypad API docs + DBZ:SW move list
-- GBA buttons: A, B, L, R, Up, Down, Left, Right, Start, Select
-- DBZ:SW key combos:
--   R+A+B = special/desperation move
--   B repeatedly = light combo
--   A = heavy/knock away
--   R (hold) = charge Ki
--   D-pad double-tap = dash/dodge

-- NEAT outputs: one neuron per button, threshold at 0.5
local ButtonNames = {"A", "B", "L", "R", "Up", "Down", "Left", "Right"}
local Outputs = #ButtonNames  -- 8 outputs

function outputsToButtons(outputs)
    local buttons = {}
    for i = 1, Outputs do
        if outputs[i] > 0.5 then
            buttons[ButtonNames[i]] = true
        else
            buttons[ButtonNames[i]] = false
        end
    end
    return buttons
end

-- CRITICAL: Pass ALL buttons in ONE joypad.set call per frame
-- Multiple calls override each other (known BizHawk issue)
```

### Pattern 4: Genome Serialization with dkjson
**What:** Save/load complete NEAT population state as JSON.
**When to use:** After each generation (checkpoint) and on training resume.
**Example:**
```lua
-- Source: dkjson library docs + NEATEvolve save pattern
local json = require("dkjson")

function saveCheckpoint(pool, filename)
    local data = {
        generation = pool.generation,
        innovation = pool.innovation,
        maxFitness = pool.maxFitness,
        species = {}
    }
    for s, species in pairs(pool.species) do
        local speciesData = {
            topFitness = species.topFitness,
            staleness = species.staleness,
            genomes = {}
        }
        for g, genome in pairs(species.genomes) do
            local genomeData = {
                maxneuron = genome.maxneuron,
                fitness = genome.fitness,
                mutationRates = genome.mutationRates,
                genes = {}
            }
            for _, gene in pairs(genome.genes) do
                genomeData.genes[#genomeData.genes + 1] = {
                    into = gene.into,
                    out = gene.out,
                    weight = gene.weight,
                    enabled = gene.enabled,
                    innovation = gene.innovation
                }
            end
            speciesData.genomes[#speciesData.genomes + 1] = genomeData
        end
        data.species[#data.species + 1] = speciesData
    end

    local jsonStr = json.encode(data, {indent = true})
    local file = io.open(filename, "w")
    file:write(jsonStr)
    file:close()
end

function loadCheckpoint(filename)
    local file = io.open(filename, "r")
    local jsonStr = file:read("*all")
    file:close()
    local data = json.decode(jsonStr)
    -- Reconstruct pool from data...
    return reconstructPool(data)
end
```

### Pattern 5: Neural Network Visualization (displayGenome)
**What:** Draw the evolved neural network topology on BizHawk's screen using gui.* functions.
**When to use:** During active genome evaluation to visualize what the network is doing.
**Example:**
```lua
-- Source: MarI/O displayGenome function, adapted for fighting game inputs
function displayGenome(genome)
    local network = genome.network
    local cells = {}

    -- Input nodes: arranged as labeled game state values (not a grid)
    -- Unlike MarI/O's 13x13 tile grid, fighting game uses structured inputs
    local inputLabels = {"P1HP", "P2HP", "P1Ki", "P2Ki", "DistX", "DistY",
                          "P1Atk", "P2Atk", "Round", "Timer"}
    for i = 1, #inputLabels do
        cells[i] = {x = 30, y = 20 + 12 * i, value = network.neurons[i].value}
        gui.drawText(2, 16 + 12 * i, inputLabels[i], 0xFF888888, 8)
    end

    -- Bias node
    cells[Inputs] = {x = 30, y = 20 + 12 * (#inputLabels + 1),
                     value = network.neurons[Inputs].value}

    -- Output nodes: button names
    for o = 1, Outputs do
        local neuronId = MaxNodes + o
        cells[neuronId] = {x = 220, y = 30 + 12 * o,
                           value = network.neurons[neuronId].value}
        local color = 0xFF000000
        if cells[neuronId].value > 0.5 then
            color = 0xFF00FF00  -- Green when active
        end
        gui.drawText(225, 26 + 12 * o, ButtonNames[o], color, 9)
    end

    -- Hidden nodes: positioned by force-directed layout (MarI/O pattern)
    -- [same force layout logic as MarI/O]

    -- Draw connections with weight coloring
    for _, gene in pairs(genome.genes) do
        if gene.enabled then
            local c1 = cells[gene.into]
            local c2 = cells[gene.out]
            if c1 and c2 then
                local color
                if gene.weight > 0 then
                    color = 0xA000FF00  -- Green = positive
                else
                    color = 0xA0FF0000  -- Red = negative
                end
                gui.drawLine(c1.x + 1, c1.y, c2.x - 3, c2.y, color)
            end
        end
    end

    -- Draw node boxes
    for n, cell in pairs(cells) do
        local brightness = math.floor((cell.value + 1) / 2 * 256)
        brightness = math.max(0, math.min(255, brightness))
        local color = 0xFF000000 + brightness * 0x10000 + brightness * 0x100 + brightness
        gui.drawBox(cell.x - 2, cell.y - 2, cell.x + 2, cell.y + 2, 0xFF000000, color)
    end
end
```

### Anti-Patterns to Avoid
- **Single-scalar fitness for fighting game:** Do NOT use `fitness = damage_dealt` or `fitness = rounds_won`. This produces degenerate strategies (spam one move, always block). Always use multi-component weighted fitness.
- **Separate joypad.set calls per button:** BizHawk only processes the LAST `joypad.set` call per frame. Always pass ALL buttons in ONE table in ONE call.
- **MarI/O tile grid input for fighting game:** Do NOT read a spatial grid around the character. Fighting game state is relational (distances, health bars, ki levels), not spatial tiles.
- **Saving genomes without innovation numbers:** Innovation numbers are essential for crossover to work correctly. The checkpoint must preserve every gene's innovation number.
- **Evaluating network every frame:** MarI/O evaluates every 5th frame (`pool.currentFrame%5 == 0`). For fighting games, evaluate EVERY frame -- timing matters more than in platformers.
- **Hard-coded memory addresses:** Use the memory_map.lua module from Phase 1. Never inline hex addresses in NEAT code.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON serialization | Custom Lua table-to-string converter | dkjson.lua (single file, pure Lua) | Handles nested tables, arrays, escaping, Unicode. Custom serializers always have edge cases. |
| NEAT algorithm from scratch | Entirely new NEAT implementation | Fork MarI/O's data structures and operators | MarI/O's NEAT is debugged across thousands of runs. Speciation, crossover, and innovation tracking have subtle interactions that are easy to get wrong. |
| Neural network visualization layout | Custom force-directed graph layout | MarI/O's displayGenome iterative positioning | The 4-iteration force-directed layout in MarI/O produces readable network visualizations. Writing a new one is unnecessary. |
| Sigmoid activation function | Custom activation | `sigmoid(x) = 2/(1+exp(-4.9*x))-1` | This specific sigmoid (from the NEAT paper) maps to [-1, 1] range with a steep slope. Using standard 0-1 sigmoid changes the network dynamics. |

**Key insight:** The NEAT algorithm has many interacting components (innovation tracking, speciation thresholds, stagnation detection, crossover alignment). Getting any one wrong silently degrades evolution without obvious errors. Start from proven code and modify only what must change for the fighting game domain.

## Common Pitfalls

### Pitfall 1: Degenerate Fitness Convergence
**What goes wrong:** All genomes converge on a single degenerate strategy (always block, spam B, stand still) because the fitness function has a local optimum that rewards simple behaviors.
**Why it happens:** Single-scalar or poorly weighted multi-component fitness creates deceptive landscapes. "Always block" survives longer, getting higher fitness than "fight and sometimes die."
**How to avoid:** (1) Weight offense higher than defense (W_offense > W_defense). (2) Add anti-stalling penalty. (3) Test fitness function: if "always block" scores higher than "fight actively," the weights are wrong. (4) Watch replays of top-5 genomes every 10 generations.
**Warning signs:** All species doing the same thing. Fitness plateaus within 10-20 generations. Population diversity (species count) collapses below 3.

### Pitfall 2: Innovation Number Reset on Load
**What goes wrong:** After loading a checkpoint, the global innovation counter resets or starts from a wrong value. New mutations create genes with duplicate innovation numbers, breaking crossover alignment.
**Why it happens:** MarI/O's original save/load was broken. NEATEvolve fixed save but the innovation counter management is subtle. If innovation starts from `Outputs` instead of the saved value, all new genes collide with existing ones.
**How to avoid:** Checkpoint MUST save `pool.innovation`. On load, set `pool.innovation` to the saved value. Verify by checking that `pool.innovation > max(all gene innovation numbers in loaded pool)`.
**Warning signs:** Crossover produces garbage networks after loading a checkpoint. Species assignments change dramatically after a save/load cycle.

### Pitfall 3: Lua 5.4 Integer/Float Distinction
**What goes wrong:** MarI/O was written for Lua 5.1. Lua 5.4 distinguishes integers from floats. Division `5/2` returns `2.5` (float) but `5//2` returns `2` (integer floor division). Array indexing with float keys creates nil entries.
**Why it happens:** BizHawk 2.11 bundles Lua 5.4. Old code that used integer division implicitly may break.
**How to avoid:** (1) Always use `math.floor()` for indices. (2) Use `//` explicitly for integer division. (3) Test: `type(1/2)` should return "float" in 5.4. (4) Watch for nil errors in table access patterns.
**Warning signs:** Mysterious nil values when accessing genome arrays. Network neurons missing after construction.

### Pitfall 4: Species Stagnation (Fighting Game Specific)
**What goes wrong:** After 30-50 generations, species converge on one strategy. New topology innovations (added nodes/connections) temporarily reduce fitness and are eliminated before optimization.
**Why it happens:** Fighting games have deceptive fitness landscapes. A simple strategy achieves moderate fitness quickly. MarI/O's `StaleSpecies = 15` is too aggressive for fighting games.
**How to avoid:** (1) Increase `StaleSpecies` to 30-50. (2) Implement dynamic `DeltaThreshold` that adjusts to maintain 10-15 species. (3) Add novelty bonus to fitness. (4) Use curriculum training: start easy CPU, advance when win rate > 80%.
**Warning signs:** Species count drops below 3. Best fitness unchanged for 20+ generations. All top genomes have nearly identical topology.

### Pitfall 5: Save State Does Not Reset Lua State
**What goes wrong:** Loading a save state resets the emulator (game state) but NOT the Lua script's local variables. Generation counters, fitness accumulators, and frame counters from the previous evaluation bleed into the next one.
**Why it happens:** BizHawk save states are emulator-level, not script-level. Lua variables persist across save state loads.
**How to avoid:** Explicitly reset ALL evaluation state variables at the start of each genome evaluation, AFTER loading the save state. Never rely on save state load to reset script variables.
**Warning signs:** Fitness values that increase monotonically within a generation (accumulating from previous evaluations). Frame counters that do not reset.

### Pitfall 6: Fighting Game Input Space Design
**What goes wrong:** Using too many or too few input neurons. Too many (every memory address) creates an intractable search space. Too few (just HP) gives the network no useful information about positioning or timing.
**Why it happens:** MarI/O uses 169 inputs (13x13 grid). A fighting game needs different inputs entirely: relative positions, health bars, ki levels, attack states. The right set is not obvious.
**How to avoid:** Start with 10-15 inputs: P1 HP, P2 HP, P1 Ki, P2 Ki, X distance, Y distance, P1 attack state, P2 attack state, round state, timer. Normalize all to [0, 1] or [-1, 1]. Add more inputs only if training stalls.
**Warning signs:** Network topology grows to hundreds of nodes without fitness improvement (too many inputs). Network never uses certain input neurons (those inputs are irrelevant).

## Code Examples

### MarI/O NEAT Core Constants (reference values to adapt)
```lua
-- Source: MarI/O neatevolve.lua by SethBling
-- These are the standard NEAT hyperparameters from MarI/O.
-- Adapt for fighting game domain.

Population = 300            -- Pool size (start here, reduce to 150 if too slow)
DeltaDisjoint = 2.0         -- Weight for disjoint gene count in compatibility
DeltaWeights = 0.4          -- Weight for average weight difference in compatibility
DeltaThreshold = 1.0        -- Species compatibility threshold (may need dynamic adjustment)
StaleSpecies = 15           -- Generations without improvement before species removal
                            -- INCREASE TO 30-50 for fighting game

MutateConnectionsChance = 0.25   -- Probability of weight mutation per genome
PerturbChance = 0.90             -- Within weight mutation, perturb vs randomize
LinkMutationChance = 2.0         -- Expected new connections per mutation
NodeMutationChance = 0.50        -- Probability of adding a new node
BiasMutationChance = 0.40        -- Probability of adding bias connection
StepSize = 0.1                   -- Weight perturbation magnitude
DisableMutationChance = 0.4      -- Probability of disabling a gene
EnableMutationChance = 0.2       -- Probability of re-enabling a gene
CrossoverChance = 0.75           -- Probability of crossover vs asexual reproduction

MaxNodes = 1000000               -- Upper bound on neuron IDs (innovation space)
```

### Compatibility Distance Calculation
```lua
-- Source: MarI/O neatevolve.lua, verified against NEAT paper (Stanley & Miikkulainen 2002)
function disjoint(genes1, genes2)
    local i1 = {}
    for _, gene in pairs(genes1) do
        i1[gene.innovation] = true
    end
    local i2 = {}
    for _, gene in pairs(genes2) do
        i2[gene.innovation] = true
    end

    local disjointGenes = 0
    for _, gene in pairs(genes1) do
        if not i2[gene.innovation] then
            disjointGenes = disjointGenes + 1
        end
    end
    for _, gene in pairs(genes2) do
        if not i1[gene.innovation] then
            disjointGenes = disjointGenes + 1
        end
    end

    local n = math.max(#genes1, #genes2)
    return disjointGenes / n
end

function weights(genes1, genes2)
    local i2 = {}
    for _, gene in pairs(genes2) do
        i2[gene.innovation] = gene
    end

    local sum = 0
    local coincident = 0
    for _, gene in pairs(genes1) do
        if i2[gene.innovation] then
            sum = sum + math.abs(gene.weight - i2[gene.innovation].weight)
            coincident = coincident + 1
        end
    end

    return sum / coincident
end

function sameSpecies(genome1, genome2)
    local dd = DeltaDisjoint * disjoint(genome1.genes, genome2.genes)
    local dw = DeltaWeights * weights(genome1.genes, genome2.genes)
    return dd + dw < DeltaThreshold
end
```

### Dynamic Compatibility Threshold
```lua
-- Source: NEAT paper recommendations + neat-python implementation pattern
-- Adjust DeltaThreshold to maintain target species count
local TargetSpecies = 12
local ThresholdStep = 0.1

function adjustCompatibilityThreshold(pool)
    local speciesCount = #pool.species
    if speciesCount < TargetSpecies then
        DeltaThreshold = DeltaThreshold - ThresholdStep
    elseif speciesCount > TargetSpecies then
        DeltaThreshold = DeltaThreshold + ThresholdStep
    end
    if DeltaThreshold < 0.3 then
        DeltaThreshold = 0.3  -- Floor to prevent all-same-species
    end
end
```

### Combo Analysis Pattern
```lua
-- Source: Original pattern for this project
function analyzeInputLog(inputLog)
    -- Convert button tables to string keys for pattern matching
    local sequence = {}
    for _, buttons in ipairs(inputLog) do
        local key = ""
        for _, name in ipairs(ButtonNames) do
            key = key .. (buttons[name] and "1" or "0")
        end
        sequence[#sequence + 1] = key
    end

    -- Count n-gram patterns (3-frame sequences)
    local patterns = {}
    for i = 1, #sequence - 2 do
        local trigram = sequence[i] .. "|" .. sequence[i+1] .. "|" .. sequence[i+2]
        patterns[trigram] = (patterns[trigram] or 0) + 1
    end

    -- Sort by frequency
    local sorted = {}
    for pattern, count in pairs(patterns) do
        sorted[#sorted + 1] = {pattern = pattern, count = count}
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    -- Calculate entropy (low entropy = repetitive = likely button mashing)
    local total = #sequence - 2
    local entropy = 0
    for _, entry in ipairs(sorted) do
        local p = entry.count / total
        entropy = entropy - p * math.log(p)
    end

    return {
        topPatterns = {unpack(sorted, 1, math.min(10, #sorted))},
        entropy = entropy,
        uniquePatterns = #sorted,
        totalFrames = #sequence,
        isButtonMashing = entropy < 1.5  -- Low entropy threshold
    }
end
```

### Fighting Game Input Vector Construction
```lua
-- Source: Adapted from MarI/O getInputs() for fighting game domain
-- Uses Phase 1 memory_map.lua addresses

function getGameInputs()
    local mem = require("game.memory_map")

    local inputs = {}

    -- Health (normalized to [0, 1])
    inputs[#inputs + 1] = memory.read_u16_le(mem.P1_HEALTH, "System Bus") / mem.MAX_HEALTH
    inputs[#inputs + 1] = memory.read_u16_le(mem.P2_HEALTH, "System Bus") / mem.MAX_HEALTH

    -- Ki (normalized to [0, 1])
    inputs[#inputs + 1] = memory.read_u16_le(mem.P1_KI, "System Bus") / mem.MAX_KI
    inputs[#inputs + 1] = memory.read_u16_le(mem.P2_KI, "System Bus") / mem.MAX_KI

    -- Relative position (normalized, signed)
    local p1x = memory.read_u16_le(mem.P1_POS_X, "System Bus")
    local p2x = memory.read_u16_le(mem.P2_POS_X, "System Bus")
    local p1y = memory.read_u16_le(mem.P1_POS_Y, "System Bus")
    local p2y = memory.read_u16_le(mem.P2_POS_Y, "System Bus")
    inputs[#inputs + 1] = (p2x - p1x) / mem.SCREEN_WIDTH   -- X distance
    inputs[#inputs + 1] = (p2y - p1y) / mem.SCREEN_HEIGHT   -- Y distance

    -- Attack states (raw byte, normalized)
    inputs[#inputs + 1] = memory.readbyte(mem.P1_ATTACK_STATE, "System Bus") / 255
    inputs[#inputs + 1] = memory.readbyte(mem.P2_ATTACK_STATE, "System Bus") / 255

    -- Round state
    inputs[#inputs + 1] = memory.readbyte(mem.ROUND_STATE, "System Bus") / 255

    -- Timer (normalized)
    inputs[#inputs + 1] = memory.read_u16_le(mem.TIMER, "System Bus") / mem.MAX_TIMER

    -- Bias node (always 1)
    inputs[#inputs + 1] = 1

    return inputs
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| MarI/O .pool text format save | JSON serialization (dkjson) | 2018+ forks | Cross-language compatible, debuggable, reliable |
| MarI/O crashed on load | NEATEvolve dual-file save | 2019 | Reliable save/load of full population state |
| Single-scalar fitness (go right) | Multi-component weighted fitness | Research 2020+ | Required for fighting games; avoids degenerate convergence |
| Static compatibility threshold | Dynamic threshold targeting N species | neat-python, community | Maintains diversity automatically |
| StaleSpecies = 15 | 30-50 for complex domains | Community experience | Fighting games need more time for topology innovations to optimize |
| Lua 5.1 MarI/O code | Lua 5.4 (BizHawk 2.11) | BizHawk update | Integer/float distinction requires code adaptation |
| Single-file 1200-line script | Multi-file module architecture | Code quality | Maintainability for a project this complex |

**Deprecated/outdated:**
- LuaNEAT library: Dead since 2018, no serialization, no BizHawk integration. Do not use.
- MarI/O's original save/load: Crashes on load. Use dkjson JSON serialization instead.
- Lua 5.1 arithmetic assumptions: Lua 5.4 has integer type. Use `math.floor()` for all indices.

## Open Questions

1. **Optimal input vector for DBZ Supersonic Warriors**
   - What we know: Health, Ki, positions, attack states are available from Phase 1 memory map. 10-15 inputs is a reasonable starting point.
   - What's unclear: Whether attack state byte encodes useful information (idle vs attacking vs blocking vs hitstun). Whether additional inputs (frame advantage, combo counter) are discoverable and useful.
   - Recommendation: Start with 10 inputs + bias. Add more only if training stalls after 50+ generations. Log input utilization (which neurons have non-trivial weights) to identify unused inputs.

2. **Fitness function weight tuning**
   - What we know: Multi-component is mandatory. Research suggests offense should outweigh defense. Round outcome bonuses should dominate individual hit rewards.
   - What's unclear: Exact weight ratios. Whether anti-stall penalty threshold (300 frames / 5 seconds) is appropriate for DBZ:SW's pacing.
   - Recommendation: Start with W_offense=2.0, W_defense=1.5, W_win=1000, W_lose=-500, W_stall=-0.5/frame. Tune empirically by watching top-5 agent replays every 10 generations.

3. **Evaluation length (MAX_EVAL_FRAMES)**
   - What we know: DBZ:SW rounds have a timer. A round typically lasts 60-99 seconds.
   - What's unclear: How many GBA frames is one in-game second? (Likely 60fps). Whether one round or a full match (best of 3) should be one evaluation.
   - Recommendation: Start with one round per evaluation (faster iteration). Set MAX_EVAL_FRAMES to the round timer equivalent (~5400 frames for 90 seconds). Move to full match later if needed.

4. **Species timeline visualization (VIS-03)**
   - What we know: Track species IDs and membership counts per generation. MarI/O does not implement this.
   - What's unclear: Best rendering approach within BizHawk's limited gui.* API. Whether to draw on-screen or in a separate `forms.newform` window.
   - Recommendation: Use a separate canvas window (`gui.createcanvas`) for the timeline, keeping the main screen for network visualization. Render as stacked horizontal bars per generation.

5. **Curriculum training implementation**
   - What we know: DBZ:SW has CPU difficulty levels. Training against one difficulty leads to overfitting. Curriculum (easy then hard) improves generalization.
   - What's unclear: How to change CPU difficulty at runtime -- likely requires different save states per difficulty level. Whether difficulty is a RAM value that can be written.
   - Recommendation: Create multiple save states (easy/medium/hard). Rotate difficulty every N generations. If RAM-writable difficulty exists, that is more elegant.

## Sources

### Primary (HIGH confidence)
- [MarI/O source code (SethBling)](https://gist.github.com/d12frosted/7471e2123f10485d96bb) -- Full NEAT implementation, data structures, main loop, visualization
- [MarI/O GitHub clone](https://github.com/rodvan/MarI-O/blob/master/NEATEvolve.lua) -- Same code, browsable
- [BizHawk Lua Functions Reference](https://tasvideos.org/Bizhawk/LuaFunctions) -- gui.*, joypad.*, memory.*, emu.*, savestate.* APIs
- [NEAT paper (Stanley & Miikkulainen 2002)](https://nn.cs.utexas.edu/downloads/papers/stanley.ec02.pdf) -- Original algorithm specification
- [NEAT overview - CMU](https://www.cs.cmu.edu/afs/cs/project/jair/pub/volume21/stanley04a-html/node3.html) -- Speciation, crossover, innovation details
- [dkjson - JSON module for Lua](http://dkolf.de/dkjson-lua/) -- Pure Lua JSON library documentation
- [DBZ Supersonic Warriors Move List (GameFAQs)](https://gamefaqs.gamespot.com/gba/919603-dragon-ball-z-supersonic-warriors/faqs/29698) -- Complete button combinations for all characters
- [DBZ Supersonic Warriors Moves (StrategyWiki)](https://strategywiki.org/wiki/Dragon_Ball_Z:_Supersonic_Warriors/Moves) -- Controls and combat mechanics

### Secondary (MEDIUM confidence)
- [NEATEvolve (improved MarI/O fork)](https://github.com/SngLol/NEATEvolve) -- Save/load bug fixes, species.lua serialization pattern
- [Multi-objective NEAT for fighting games (Springer 2020)](https://link.springer.com/article/10.1007/s00521-020-04794-x) -- Fighting game fitness function design, Pareto-based NEAT
- [Neuroevolution in Games survey (arXiv)](https://arxiv.org/pdf/1410.7326) -- Domain challenges and patterns for game neuroevolution
- [NEAT Python overview](https://neat-python.readthedocs.io/en/latest/neat_overview.html) -- Speciation, stagnation, compatibility threshold patterns
- [Speciation in Canonical NEAT (SharpNeat)](https://sharpneat.sourceforge.io/research/speciation-canonical-neat.html) -- Detailed speciation algorithm analysis
- [The NEAT Algorithm (Lunatech 2024)](https://blog.lunatech.com/posts/2024-02-29-the-neat-algorithm-evolving-neural-network-topologies) -- Modern explanation of NEAT components
- [BizHawk joypad.set multiple buttons](https://gist.github.com/Gikkman/53c0527c01289ff53e20e8ff125bbb7b) -- Single-call pattern for simultaneous buttons
- [BizHawk joypad button names](https://tasvideos.org/Bizhawk/LuaFunctions/JoypadTableKeyNames) -- GBA button name reference

### Tertiary (LOW confidence)
- [FightLadder benchmark (2024)](https://arxiv.org/html/2406.02081v2) -- Dense reward shaping pattern for fighting games (RL context, pattern applicable to neuroevolution)
- [Platform fighting game NEAT blog](https://medium.com/@mikecazzinaro/teaching-ai-to-play-a-platform-fighting-game-using-neural-networks-ef9316c34f52) -- Anecdotal fighting game NEAT experience
- [lunajson](https://github.com/grafi-tt/lunajson) -- Alternative pure Lua JSON library (benchmarked against dkjson)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- MarI/O pattern is proven, BizHawk Lua API is well-documented, dkjson is established
- Architecture: MEDIUM-HIGH -- MarI/O architecture is solid; fighting game adaptation requires input/output/fitness redesign which is less proven
- Pitfalls: HIGH -- Well-documented across MarI/O forks, fighting game NEAT research, and community experience
- Fitness function: MEDIUM -- Multi-component approach is well-supported by research but exact weight tuning requires empirical iteration

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (30 days -- stable domain, NEAT algorithm and BizHawk API are not fast-moving)
