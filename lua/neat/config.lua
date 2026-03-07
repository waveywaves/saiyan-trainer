-- config.lua
-- All NEAT hyperparameters and game-specific constants.
-- MarI/O-derived values with fighting game adjustments.
--
-- Usage:
--   local config = dofile("lua/neat/config.lua")

local Config = {}

-- Population
Config.Population = 300
Config.Inputs = 9           -- 8 game state + 1 bias
Config.Outputs = 8          -- from Controller.getNumOutputs()
Config.MaxNodes = 1000000

-- Compatibility distance
Config.DeltaDisjoint = 2.0
Config.DeltaWeights = 0.4
Config.DeltaThreshold = 1.0

-- Stagnation (increased from MarI/O's 15 for fighting game complexity)
Config.StaleSpecies = 30

-- Mutation rates
Config.MutateConnectionsChance = 0.25
Config.PerturbChance = 0.90
Config.LinkMutationChance = 2.0
Config.NodeMutationChance = 0.50
Config.BiasMutationChance = 0.40
Config.StepSize = 0.1
Config.DisableMutationChance = 0.4
Config.EnableMutationChance = 0.2
Config.CrossoverChance = 0.75

-- Fitness
Config.TimeoutConstant = 5400      -- ~90 seconds at 60fps (one round)
Config.StallFrameThreshold = 300   -- ~5 seconds before anti-stall kicks in

-- Dynamic compatibility
Config.TargetSpecies = 12
Config.ThresholdStep = 0.1
Config.ThresholdFloor = 0.3

return Config
