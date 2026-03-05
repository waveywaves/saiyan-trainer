-- dkjson.lua - Minimal JSON encoder/decoder for Lua 5.1+
-- Based on dkjson by David Kolf (http://dkolf.de/dkjson-lua/)
-- This is a simplified, MIT-licensed reimplementation for BizHawk compatibility.
-- Supports: strings, numbers, booleans, null (nil), arrays, objects, nested structures.
--
-- Usage:
--   local json = dofile("lua/lib/dkjson.lua")
--   local str = json.encode({name="test", value=42})
--   local tbl = json.decode(str)

local json = {}

-- Escape map for JSON strings
local escapeMap = {
    ['"']  = '\\"',
    ['\\'] = '\\\\',
    ['/']  = '\\/',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

--- Escape a string for JSON.
local function escapeString(s)
    s = s:gsub('[\\"/\b\f\n\r\t]', function(c)
        return escapeMap[c] or c
    end)
    -- Escape control characters
    s = s:gsub('[\x00-\x1f]', function(c)
        return string.format('\\u%04x', string.byte(c))
    end)
    return '"' .. s .. '"'
end

--- Check if a table is an array (sequential integer keys starting at 1).
local function isArray(t)
    if type(t) ~= "table" then return false end
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    if count == 0 then return true end -- empty table treated as array
    for i = 1, count do
        if t[i] == nil then return false end
    end
    return true
end

--- Encode a Lua value to a JSON string.
-- @param value     any       The value to encode.
-- @param state     table     Optional state table with 'indent' (boolean/string).
-- @param indent    string    Current indentation (internal use).
-- @param currentIndent string Current level indentation (internal use).
-- @return string   JSON string.
function json.encode(value, state, indent, currentIndent)
    local indentEnabled = false
    local indentStr = "  "
    if state and state.indent then
        indentEnabled = true
        if type(state.indent) == "string" then
            indentStr = state.indent
        end
    end

    indent = indent or ""
    currentIndent = currentIndent or ""

    local t = type(value)

    if value == nil then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        -- Handle special float values
        if value ~= value then return "null" end -- NaN
        if value == math.huge then return "1e+999" end
        if value == -math.huge then return "-1e+999" end
        -- Use integer format if it's a whole number
        if math.floor(value) == value and value >= -2^53 and value <= 2^53 then
            return string.format("%.0f", value)
        end
        return tostring(value)
    elseif t == "string" then
        return escapeString(value)
    elseif t == "table" then
        local nextIndent = currentIndent .. indentStr
        local sep = indentEnabled and ",\n" or ","
        local openSep = indentEnabled and "\n" or ""
        local closeSep = indentEnabled and ("\n" .. currentIndent) or ""
        local colonSep = indentEnabled and ": " or ":"
        local itemIndent = indentEnabled and nextIndent or ""

        if isArray(value) then
            if #value == 0 then return "[]" end
            local parts = {}
            for i = 1, #value do
                parts[i] = itemIndent .. json.encode(value[i], state, indentStr, nextIndent)
            end
            return "[" .. openSep .. table.concat(parts, sep) .. closeSep .. "]"
        else
            -- Object: collect keys and sort for deterministic output
            local keys = {}
            for k in pairs(value) do
                if type(k) == "string" then
                    keys[#keys + 1] = k
                end
            end
            if #keys == 0 then return "{}" end
            table.sort(keys)

            local parts = {}
            for i, k in ipairs(keys) do
                parts[i] = itemIndent .. escapeString(k) .. colonSep ..
                           json.encode(value[k], state, indentStr, nextIndent)
            end
            return "{" .. openSep .. table.concat(parts, sep) .. closeSep .. "}"
        end
    else
        error("Cannot encode type: " .. t)
    end
end

-- JSON decoder

local function skipWhitespace(s, pos)
    local p = s:find("[^ \t\n\r]", pos)
    return p or #s + 1
end

local function decodeString(s, pos)
    -- pos points to the opening "
    local startPos = pos + 1
    local result = {}
    local i = startPos
    while i <= #s do
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(result), i + 1
        elseif c == '\\' then
            i = i + 1
            local esc = s:sub(i, i)
            if esc == '"' then result[#result+1] = '"'
            elseif esc == '\\' then result[#result+1] = '\\'
            elseif esc == '/' then result[#result+1] = '/'
            elseif esc == 'b' then result[#result+1] = '\b'
            elseif esc == 'f' then result[#result+1] = '\f'
            elseif esc == 'n' then result[#result+1] = '\n'
            elseif esc == 'r' then result[#result+1] = '\r'
            elseif esc == 't' then result[#result+1] = '\t'
            elseif esc == 'u' then
                local hex = s:sub(i+1, i+4)
                local codepoint = tonumber(hex, 16)
                if codepoint and codepoint < 128 then
                    result[#result+1] = string.char(codepoint)
                else
                    result[#result+1] = '\\u' .. hex -- pass through non-ASCII
                end
                i = i + 4
            end
            i = i + 1
        else
            result[#result+1] = c
            i = i + 1
        end
    end
    error("Unterminated string at position " .. pos)
end

local decodeValue  -- forward declaration

local function decodeArray(s, pos)
    -- pos points to [
    local arr = {}
    pos = skipWhitespace(s, pos + 1)
    if s:sub(pos, pos) == ']' then
        return arr, pos + 1
    end

    while true do
        local value
        value, pos = decodeValue(s, pos)
        arr[#arr + 1] = value
        pos = skipWhitespace(s, pos)
        local c = s:sub(pos, pos)
        if c == ']' then
            return arr, pos + 1
        elseif c == ',' then
            pos = skipWhitespace(s, pos + 1)
        else
            error("Expected ',' or ']' at position " .. pos)
        end
    end
end

local function decodeObject(s, pos)
    -- pos points to {
    local obj = {}
    pos = skipWhitespace(s, pos + 1)
    if s:sub(pos, pos) == '}' then
        return obj, pos + 1
    end

    while true do
        -- Key must be a string
        if s:sub(pos, pos) ~= '"' then
            error("Expected string key at position " .. pos)
        end
        local key
        key, pos = decodeString(s, pos)
        pos = skipWhitespace(s, pos)
        if s:sub(pos, pos) ~= ':' then
            error("Expected ':' at position " .. pos)
        end
        pos = skipWhitespace(s, pos + 1)

        local value
        value, pos = decodeValue(s, pos)
        obj[key] = value

        pos = skipWhitespace(s, pos)
        local c = s:sub(pos, pos)
        if c == '}' then
            return obj, pos + 1
        elseif c == ',' then
            pos = skipWhitespace(s, pos + 1)
        else
            error("Expected ',' or '}' at position " .. pos)
        end
    end
end

decodeValue = function(s, pos)
    pos = skipWhitespace(s, pos)
    local c = s:sub(pos, pos)

    if c == '"' then
        return decodeString(s, pos)
    elseif c == '{' then
        return decodeObject(s, pos)
    elseif c == '[' then
        return decodeArray(s, pos)
    elseif c == 't' then
        if s:sub(pos, pos + 3) == "true" then
            return true, pos + 4
        end
        error("Invalid value at position " .. pos)
    elseif c == 'f' then
        if s:sub(pos, pos + 4) == "false" then
            return false, pos + 5
        end
        error("Invalid value at position " .. pos)
    elseif c == 'n' then
        if s:sub(pos, pos + 3) == "null" then
            return nil, pos + 4
        end
        error("Invalid value at position " .. pos)
    elseif c == '-' or (c >= '0' and c <= '9') then
        local numStr = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
        if not numStr then
            error("Invalid number at position " .. pos)
        end
        return tonumber(numStr), pos + #numStr
    else
        error("Unexpected character '" .. c .. "' at position " .. pos)
    end
end

--- Decode a JSON string into a Lua value.
-- @param s string  The JSON string to decode.
-- @return any      The decoded Lua value.
function json.decode(s)
    if type(s) ~= "string" then
        error("Expected string, got " .. type(s))
    end
    local value, pos = decodeValue(s, 1)
    return value
end

return json
