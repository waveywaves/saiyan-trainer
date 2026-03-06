-- hud.lua
-- Training statistics heads-up display for mGBA.
--
-- mGBA does not provide BizHawk-style gui.* overlay drawing functions.
-- This module provides the same public API but currently is a no-op.
-- Training stats are logged to console by the training loop directly.
--
-- Usage:
--   local HUD = dofile("lua/vis/hud.lua")
--   HUD.displayHUD(pool, currentGenome, fps)
--   HUD.displayFitnessBar(fitness, maxFitness)

local HUD = {}

--- Display the training statistics HUD overlay (no-op on mGBA).
-- @param pool          table   The population pool.
-- @param currentGenome table   The genome currently being evaluated (optional).
-- @param fps           number  Current frames per second (optional).
function HUD.displayHUD(pool, currentGenome, fps)
    -- No-op: mGBA does not support screen overlay drawing.
    -- Training stats are logged to console by the training loop.
end

--- Display a horizontal fitness bar (no-op on mGBA).
-- @param fitness    number  Current fitness value.
-- @param maxFitness number  Maximum fitness achieved (for scale).
function HUD.displayFitnessBar(fitness, maxFitness)
    -- No-op: mGBA does not support screen overlay drawing.
end

return HUD
