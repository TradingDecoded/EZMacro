local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")

--- Decode a GSE3 encoded string into a Lua table.
-- @param data string The !GSE3!-prefixed encoded string
-- @return boolean success
-- @return table|string result or error message
function EZMacro:DecodeGSEString(data)
    if type(data) ~= "string" then
        return false, "Input must be a string"
    end
    data = strtrim(data)
    if data:sub(1, 6) ~= "!GSE3!" then
        return false, "Not a valid GSE3 string (missing !GSE3! prefix)"
    end
    local ok, result = pcall(function()
        local encoded = data:sub(6)
        local decoded = C_EncodingUtil.DecodeBase64(encoded)
        local decompressed = C_EncodingUtil.DecompressString(decoded)
        return C_EncodingUtil.DeserializeCBOR(decompressed)
    end)
    if not ok then
        return false, "Failed to decode: " .. tostring(result)
    end
    return true, result
end

--- Parse a raw Lua step table string into an actual table.
-- Accepts the format: { [1] = { ["macrotext"] = "...", ["type"] = "macro" }, ... }
-- @param input string The raw Lua table code
-- @return boolean success
-- @return table|string result or error message
function EZMacro:ParseLuaStepTable(input)
    -- Wrap in a return statement so loadstring can evaluate it
    local code = "return " .. input
    local fn, err = loadstring(code)
    if not fn then
        return false, "Invalid Lua syntax: " .. tostring(err)
    end
    -- Execute in a sandboxed environment with no access to global functions
    setfenv(fn, {})
    local ok, result = pcall(fn)
    if not ok then
        return false, "Failed to evaluate: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return false, "Expected a table, got " .. type(result)
    end
    -- Validate it looks like a step table: array of tables with macrotext and type
    if not result[1] or type(result[1]) ~= "table" then
        return false, "Expected an array of step tables"
    end
    if not result[1].macrotext and not result[1].spell then
        return false, "Steps must have 'macrotext' or 'spell' fields"
    end
    return true, result
end

--- Import a raw Lua step table as a macro with the given name.
-- @param name string The macro name
-- @param input string The raw Lua table code
-- @return boolean success
-- @return string message
function EZMacro:ImportLuaTable(name, input)
    local ok, steps = self:ParseLuaStepTable(input)
    if not ok then
        return false, steps
    end

    -- Store as a pre-compiled macro (no GSE sequence structure, just raw steps)
    local existing = EZMacro_CharDB.macros[name]
    EZMacro_CharDB.macros[name] = {
        sequence = nil,
        compiledSteps = steps,  -- pre-compiled step table, used directly by Engine
        classID = 0,
        keybind = existing and existing.keybind or nil,
        source = input,
        warnings = {},
    }

    return true, "Imported macro: " .. name
end

--- Import a GSE string, storing decoded macros into EZMacro_CharDB.
-- @param inputString string The raw pasted string
-- @return boolean success
-- @return string message (success or error description)
function EZMacro:ImportString(inputString)
    local ok, decoded = self:DecodeGSEString(inputString)
    if not ok then
        return false, decoded
    end

    local count = 0

    if type(decoded) == "table" and decoded.type == "COLLECTION" then
        -- Collection import
        local payload = decoded.payload
        if payload and payload.Sequences then
            for name, sequence in pairs(payload.Sequences) do
                self:StoreSequence(name, sequence, inputString)
                count = count + 1
            end
        end
        -- Store Variables and Macros sub-tables for forward compatibility
        if payload and payload.Variables then
            if not EZMacro_CharDB.variables then EZMacro_CharDB.variables = {} end
            for k, v in pairs(payload.Variables) do
                EZMacro_CharDB.variables[k] = v
            end
        end
        if payload and payload.Macros then
            if not EZMacro_CharDB.rawMacros then EZMacro_CharDB.rawMacros = {} end
            for k, v in pairs(payload.Macros) do
                EZMacro_CharDB.rawMacros[k] = v
            end
        end
    elseif type(decoded) == "table" and decoded[1] and decoded[2] then
        -- Single sequence: {name, sequenceTable}
        local name = decoded[1]
        local sequence = decoded[2]
        self:StoreSequence(name, sequence, inputString)
        count = 1
    else
        return false, "Unrecognized GSE format"
    end

    return true, count .. " macro(s) imported"
end

--- Store a single sequence into per-character DB.
-- @param name string Sequence name
-- @param sequence table The decoded sequence table
-- @param source string Original encoded string
function EZMacro:StoreSequence(name, sequence, source)
    local classID = 0
    if sequence.MetaData and sequence.MetaData.ClassID then
        classID = sequence.MetaData.ClassID
    end

    local existing = EZMacro_CharDB.macros[name]
    EZMacro_CharDB.macros[name] = {
        sequence = sequence,
        classID = classID,
        keybind = existing and existing.keybind or nil,
        source = source,
        warnings = {},
    }
end
