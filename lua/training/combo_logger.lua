-- combo_logger.lua
-- Input sequence recording and pattern analysis for NEAT training.
-- Records button presses during genome evaluation and analyzes patterns
-- to detect button mashing vs learned strategies.
--
-- Usage:
--   local ComboLogger = dofile("lua/training/combo_logger.lua")
--   local logger = ComboLogger.newLogger()
--   ComboLogger.record(logger, buttons)
--   local analysis = ComboLogger.analyzeInputLog(logger.log)

local ComboLogger = {}

-- Button names in canonical order for pattern encoding.
-- Must match Controller.getButtonNames() order.
local ButtonNames = {"A", "B", "L", "R", "Up", "Down", "Left", "Right"}

--- Create a new empty combo logger.
-- @return table  Logger with empty log and zero frameCount.
function ComboLogger.newLogger()
    return {
        log = {},
        frameCount = 0,
    }
end

--- Record a frame's button state into the logger.
-- @param logger  table  The logger instance.
-- @param buttons table  Button name -> boolean table (e.g., {A=true, B=false, ...}).
function ComboLogger.record(logger, buttons)
    logger.log[#logger.log + 1] = buttons
    logger.frameCount = logger.frameCount + 1
end

--- Clear a logger's recorded data.
-- @param logger table  The logger instance.
function ComboLogger.clear(logger)
    logger.log = {}
    logger.frameCount = 0
end

--- Encode a buttons table to a binary string key.
-- Each button is represented as '1' (pressed) or '0' (not pressed)
-- in the order defined by ButtonNames.
-- @param buttons table  Button name -> boolean table.
-- @return string  Binary string like "10100010".
local function encodeButtons(buttons)
    local parts = {}
    for i, name in ipairs(ButtonNames) do
        parts[i] = buttons[name] and "1" or "0"
    end
    return table.concat(parts)
end

--- Decode a binary pattern string back to a human-readable button description.
-- "10100010" -> "A+L+Right"
-- @param pattern string  Binary string of button states.
-- @return string  Human-readable button combination.
function ComboLogger.decodePattern(pattern)
    local names = {}
    for i = 1, #pattern do
        if pattern:sub(i, i) == "1" then
            names[#names + 1] = ButtonNames[i]
        end
    end
    if #names == 0 then
        return "(none)"
    end
    return table.concat(names, "+")
end

--- Analyze an input log for patterns, entropy, and button mashing detection.
-- Converts button tables to binary string keys, counts trigram (3-frame) patterns,
-- computes Shannon entropy over the trigram distribution, and returns top patterns.
-- @param inputLog table  Array of button tables (from logger.log).
-- @return table  Analysis results:
--   topPatterns    - array of {pattern=string, count=number, buttons=string}
--   entropy        - Shannon entropy of trigram distribution (higher = more varied)
--   uniquePatterns - count of distinct trigrams
--   totalFrames    - total frames in log
--   isButtonMashing - true if entropy < 1.5 (repetitive input)
function ComboLogger.analyzeInputLog(inputLog)
    if #inputLog < 3 then
        return {
            topPatterns = {},
            entropy = 0,
            uniquePatterns = 0,
            totalFrames = #inputLog,
            isButtonMashing = true,
        }
    end

    -- Convert each buttons table to a binary string key
    local sequence = {}
    for i, buttons in ipairs(inputLog) do
        sequence[i] = encodeButtons(buttons)
    end

    -- Count trigram (3-frame) patterns using sliding window
    local patterns = {}
    local totalTrigrams = 0
    for i = 1, #sequence - 2 do
        local trigram = sequence[i] .. "|" .. sequence[i + 1] .. "|" .. sequence[i + 2]
        patterns[trigram] = (patterns[trigram] or 0) + 1
        totalTrigrams = totalTrigrams + 1
    end

    -- Sort patterns by frequency descending
    local sorted = {}
    for pattern, count in pairs(patterns) do
        sorted[#sorted + 1] = {pattern = pattern, count = count}
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    -- Calculate Shannon entropy over trigram distribution
    local entropy = 0
    for _, entry in ipairs(sorted) do
        local p = entry.count / totalTrigrams
        if p > 0 then
            entropy = entropy - p * math.log(p)
        end
    end

    -- Build top 10 patterns with decoded button names
    local topPatterns = {}
    for i = 1, math.min(10, #sorted) do
        local entry = sorted[i]
        -- Decode the trigram: split on "|" and decode each frame
        local frames = {}
        for frame in entry.pattern:gmatch("[^|]+") do
            frames[#frames + 1] = ComboLogger.decodePattern(frame)
        end
        topPatterns[i] = {
            pattern = entry.pattern,
            count = entry.count,
            buttons = table.concat(frames, " -> "),
        }
    end

    return {
        topPatterns = topPatterns,
        entropy = entropy,
        uniquePatterns = #sorted,
        totalFrames = #inputLog,
        isButtonMashing = entropy < 1.5,
    }
end

return ComboLogger
