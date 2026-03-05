-- fitness.lua
-- Multi-component fighting game fitness function.
-- Rewards damage dealt, penalizes damage taken, gives win/loss bonuses,
-- penalizes stalling, and guards against opponent self-destruction credit.
--
-- Usage:
--   local Fitness = dofile("lua/game/fitness.lua")
--   local score = Fitness.calculateFitness({...})

local Fitness = {}

-- Weight constants (tunable)
local W_OFFENSE = 2.0        -- reward per HP of damage dealt
local W_DEFENSE = 1.5        -- penalty per HP of damage taken
local W_WIN_BONUS = 1000     -- bonus for winning the round
local W_LOSE_PENALTY = 500   -- penalty for losing the round
local W_STALL = 0.5          -- penalty per frame of stalling beyond threshold

-- Round result constants
Fitness.WIN = 1
Fitness.LOSE = 2
Fitness.DRAW = 3
Fitness.IN_PROGRESS = 0

-- Stall frame threshold (loaded from config if available, but has default)
local STALL_FRAME_THRESHOLD = 300  -- ~5 seconds at 60fps

--- Calculate multi-component fitness for a fighting game evaluation.
-- @param params table  Evaluation parameters:
--   startP1HP        number  Bot health at start
--   endP1HP          number  Bot health at end
--   startP2HP        number  Opponent health at start
--   endP2HP          number  Opponent health at end
--   roundResult      number  WIN/LOSE/DRAW/IN_PROGRESS
--   frameCount       number  Total frames elapsed
--   lastDamageFrame  number  Frame of most recent damage dealt (optional)
--   damageDealtByBot number  Damage explicitly dealt by bot actions (optional, FIT-06)
-- @return number  The fitness score.
function Fitness.calculateFitness(params)
    -- Calculate damage dealt and taken
    local damageDealt = (params.startP2HP or 0) - (params.endP2HP or 0)
    local damageTaken = (params.startP1HP or 0) - (params.endP1HP or 0)

    -- FIT-06: Self-destruction guard
    -- If damageDealtByBot is provided and less than total HP loss,
    -- only credit what the bot actually dealt
    if params.damageDealtByBot and damageDealt > params.damageDealtByBot then
        damageDealt = params.damageDealtByBot
    end

    -- FIT-01: Offense reward
    local fitness = damageDealt * W_OFFENSE

    -- FIT-02: Defense penalty
    fitness = fitness - damageTaken * W_DEFENSE

    -- FIT-03: Win bonus
    if params.roundResult == Fitness.WIN then
        fitness = fitness + W_WIN_BONUS
    end

    -- FIT-04: Loss penalty
    if params.roundResult == Fitness.LOSE then
        fitness = fitness - W_LOSE_PENALTY
    end

    -- FIT-05: Anti-stall penalty
    if params.lastDamageFrame then
        local stallFrames = (params.frameCount or 0) - params.lastDamageFrame
        if stallFrames > STALL_FRAME_THRESHOLD then
            fitness = fitness - (stallFrames - STALL_FRAME_THRESHOLD) * W_STALL
        end
    end

    -- Floor: avoid 0 which MarI/O uses as "not evaluated"
    if fitness <= 0 then
        fitness = -1
    end

    return fitness
end

--- Get the current weight table (for logging/tuning).
-- @return table  Weight constants.
function Fitness.getWeights()
    return {
        offense = W_OFFENSE,
        defense = W_DEFENSE,
        winBonus = W_WIN_BONUS,
        losePenalty = W_LOSE_PENALTY,
        stall = W_STALL,
    }
end

--- Get the round result constants.
-- @return number, number, number, number  WIN, LOSE, DRAW, IN_PROGRESS
function Fitness.getRoundConstants()
    return Fitness.WIN, Fitness.LOSE, Fitness.DRAW, Fitness.IN_PROGRESS
end

return Fitness
