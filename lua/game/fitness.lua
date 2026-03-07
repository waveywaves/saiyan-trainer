-- fitness.lua
-- Multi-component fighting game fitness function.
-- Rewards KILLING the opponent (KO), not just surviving.
-- Penalizes timeouts to discourage passive play.
--
-- Tuned 2026-03-07: Previous version rewarded survival (win on timeout
-- with more HP). Bot learned to character-switch for HP and stall.
-- New version: massive KO bonus, timeout penalty, speed bonus for fast KOs.
-- P1 HP component removed: character switching causes P1 HP to increase,
-- confounding any defense-based signal. Focus purely on P2 damage dealt.
--
-- Usage:
--   local Fitness = dofile("lua/game/fitness.lua")
--   local score = Fitness.calculateFitness({...})

local Fitness = {}

-- Weight constants (tunable)
-- P1 HP is NOT used: character switching in DBZ:SW causes P1 HP to go UP,
-- which confounds any defense-based fitness signal.
local W_OFFENSE = 3.0        -- reward per HP of damage dealt to P2 (primary signal)
local W_KO_BONUS = 2000      -- bonus for KO'ing the opponent
local W_TIMEOUT_WIN = 200    -- small bonus for timeout win (not the goal)
local W_LOSE_PENALTY = 0     -- no penalty: P1 HP is confounded by char switching
local W_STALL = 1.0          -- penalty per frame of stalling
local W_SPEED_BONUS = 0.5    -- bonus per frame SAVED (faster KO = more bonus)

-- Round result constants
Fitness.WIN = 1
Fitness.LOSE = 2
Fitness.DRAW = 3
Fitness.IN_PROGRESS = 0
Fitness.KO = 4              -- new: explicit KO (P2 HP reached 0)

-- Stall frame threshold
local STALL_FRAME_THRESHOLD = 300  -- ~5 seconds at 60fps

--- Calculate multi-component fitness for a fighting game evaluation.
-- @param params table  Evaluation parameters:
--   startP1HP        number  Bot health at start
--   endP1HP          number  Bot health at end
--   startP2HP        number  Opponent health at start
--   endP2HP          number  Opponent health at end
--   roundResult      number  WIN/LOSE/DRAW/KO/IN_PROGRESS
--   frameCount       number  Total frames elapsed
--   timeoutConstant  number  Max frames before timeout (for speed bonus calc)
--   lastDamageFrame  number  Frame of most recent damage dealt (optional)
-- @return number  The fitness score.
function Fitness.calculateFitness(params)
    local damageDealt = (params.startP2HP or 0) - (params.endP2HP or 0)
    local frameCount = params.frameCount or 0
    local timeout = params.timeoutConstant or 1800

    -- FIT-01: Offense reward (primary and only HP-based signal)
    -- P1 HP is deliberately ignored: character switching in DBZ:SW causes
    -- P1 HP to increase, which confounds any defense fitness component.
    local fitness = damageDealt * W_OFFENSE

    -- FIT-02: KO bonus (massive reward for actually killing the opponent)
    if params.roundResult == Fitness.KO then
        fitness = fitness + W_KO_BONUS
        -- FIT-02b: Speed bonus — faster KO = higher fitness
        local framesSaved = math.max(0, timeout - frameCount)
        fitness = fitness + framesSaved * W_SPEED_BONUS
    elseif params.roundResult == Fitness.WIN then
        -- Timeout win: small bonus (not the goal, but better than losing)
        fitness = fitness + W_TIMEOUT_WIN
    end

    -- FIT-03: Anti-stall penalty (harsher to discourage passive play)
    if params.lastDamageFrame then
        local stallFrames = frameCount - params.lastDamageFrame
        if stallFrames > STALL_FRAME_THRESHOLD then
            fitness = fitness - (stallFrames - STALL_FRAME_THRESHOLD) * W_STALL
        end
    end

    -- Floor: avoid 0 which is used as "not evaluated"
    if fitness <= 0 then
        fitness = -1
    end

    return fitness
end

--- Get the current weight table (for logging/tuning).
function Fitness.getWeights()
    return {
        offense = W_OFFENSE,
        koBonus = W_KO_BONUS,
        timeoutWin = W_TIMEOUT_WIN,
        losePenalty = W_LOSE_PENALTY,
        stall = W_STALL,
        speedBonus = W_SPEED_BONUS,
    }
end

--- Get the round result constants.
function Fitness.getRoundConstants()
    return Fitness.WIN, Fitness.LOSE, Fitness.DRAW, Fitness.IN_PROGRESS
end

return Fitness
