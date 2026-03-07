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
Config.Population = 50          -- was 30 (too small for speciation); 50 balances speed/diversity
Config.Inputs = 9               -- 8 game state + 1 bias
Config.Outputs = 8              -- from Controller.getNumOutputs()
Config.MaxNodes = 1000000

-- Compatibility distance (loosened to encourage more species)
Config.DeltaDisjoint = 2.0
Config.DeltaWeights = 0.4
Config.DeltaThreshold = 0.8     -- was 1.0; lower = more species created

-- Stagnation (reduced from 30 to kill stale species faster)
Config.StaleSpecies = 20

-- Mutation rates (rebalanced to favor weight tuning over topology growth)
Config.MutateConnectionsChance = 0.25
Config.PerturbChance = 0.90
Config.LinkMutationChance = 1.5     -- was 2.0; slower connection growth
Config.NodeMutationChance = 0.25    -- was 0.50; halved to reduce over-complexity
Config.BiasMutationChance = 0.40
Config.StepSize = 0.1
Config.DisableMutationChance = 0.3  -- was 0.4; less pruning
Config.EnableMutationChance = 0.3   -- was 0.2; re-enable disabled genes more often
Config.CrossoverChance = 0.75

-- Fitness
Config.TimeoutConstant = 1800      -- ~30 seconds at 60fps (testing; raise to 5400 for real training)
Config.StallFrameThreshold = 300   -- ~5 seconds before anti-stall kicks in

-- Dynamic compatibility (more aggressive species targeting)
Config.TargetSpecies = 8           -- was 12; more achievable with 50 genomes
Config.ThresholdStep = 0.15        -- was 0.1; faster threshold adjustment
Config.ThresholdFloor = 0.2        -- was 0.3; allow tighter species separation

return Config
