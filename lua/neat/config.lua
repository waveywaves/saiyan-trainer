-- config.lua
-- All NEAT hyperparameters and game-specific constants.
-- MarI/O-derived values with fighting game adjustments.
--
-- Tuned 2026-03-07 based on checkpoint analysis (Gen 0-16):
--   - Fitness plateaued at 775.5 from Gen 6-16 (stagnation)
--   - Species collapsed to 1 (no diversity)
--   - Networks over-complex (~85 genes, ~11 hidden by Gen 16)
--   - Reduced node mutation, increased population, lowered stale threshold
--
-- Usage:
--   local config = dofile("lua/neat/config.lua")

local Config = {}

-- Population
Config.Population = 40          -- balance between speed (30) and diversity (50)
Config.Inputs = 5               -- 4 game state (P1HP, P2HP, P1Ki, P1Pwr) + 1 bias
Config.Outputs = 8              -- from Controller.getNumOutputs()
Config.MaxNodes = 1000000

-- Compatibility distance (loosened to encourage more species)
Config.DeltaDisjoint = 2.0
Config.DeltaWeights = 0.4
Config.DeltaThreshold = 0.8     -- was 1.0; lower = more species created

-- Stagnation (reduced from 30 to kill stale species faster)
Config.StaleSpecies = 12        -- kill stale species faster to make room for new strategies

-- Mutation rates (rebalanced to favor weight tuning over topology growth)
Config.MutateConnectionsChance = 0.25
Config.PerturbChance = 0.90
Config.LinkMutationChance = 1.5     -- was 2.0; slower connection growth
Config.NodeMutationChance = 0.35    -- bumped from 0.25; need topology diversity for combo discovery
Config.BiasMutationChance = 0.40
Config.StepSize = 0.1
Config.DisableMutationChance = 0.3  -- was 0.4; less pruning
Config.EnableMutationChance = 0.3   -- was 0.2; re-enable disabled genes more often
Config.CrossoverChance = 0.75

-- Fitness
Config.TimeoutConstant = 600       -- ~10 seconds at 60fps (faster iteration; raise to 1800+ for final training)
Config.StallFrameThreshold = 300   -- ~5 seconds before anti-stall kicks in

-- Dynamic compatibility (more aggressive species targeting)
Config.TargetSpecies = 8           -- was 12; more achievable with 50 genomes
Config.ThresholdStep = 0.15        -- was 0.1; faster threshold adjustment
Config.ThresholdFloor = 0.2        -- was 0.3; allow tighter species separation

return Config
