local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")

-- Compiled step tables per button
EZMacro.CompiledSteps = {}
-- Secure button references
EZMacro.Buttons = {}

--- Sanitize a macro name into a valid WoW global frame name.
local function SanitizeButtonName(name)
    return "EZMacro_" .. name:gsub("[^%w]", "_")
end

--- Get the active version table from a GSE sequence.
-- Uses MetaData.Default, falls back to version 1.
function EZMacro:GetActiveVersion(sequence)
    if not sequence or not sequence.Versions then
        return nil
    end
    local versionNum = 1
    if sequence.MetaData and sequence.MetaData.Default then
        versionNum = sequence.MetaData.Default
    end
    if versionNum == 0 then versionNum = 1 end
    return sequence.Versions[versionNum]
end

--- Compile a sequence version into a flat step table.
function EZMacro:CompileSequence(sequence)
    local version = self:GetActiveVersion(sequence)
    if not version then return {} end

    local steps = {}
    local actions = version.Actions or version

    if type(actions) == "table" then
        for i = 1, #actions do
            local action = actions[i]
            if action and not action.Disabled then
                local compiled = self:CompileAction(action)
                for _, step in ipairs(compiled) do
                    steps[#steps + 1] = step
                end
            end
        end
    end

    -- Fallback: if no steps compiled, try treating the version itself as macro text
    if #steps == 0 and type(version) == "table" then
        for i = 1, #version do
            if type(version[i]) == "string" then
                steps[#steps + 1] = { type = "macrotext", macrotext = version[i] }
            end
        end
    end

    return steps
end

--- Compile a single action block into one or more steps.
function EZMacro:CompileAction(action)
    local steps = {}
    local actionType = action.Type or "Action"

    if actionType == "Action" then
        local attrs = {}
        if action.macrotext then
            attrs.type = "macrotext"
            attrs.macrotext = action.macrotext
        elseif action.spell then
            attrs.type = "spell"
            attrs.spell = action.spell
        elseif type(action[1]) == "string" then
            attrs.type = "macrotext"
            attrs.macrotext = action[1]
        end

        if next(attrs) then
            local repeat_count = tonumber(action.Repeat) or 1
            for _ = 1, repeat_count do
                steps[#steps + 1] = attrs
            end
        end

    elseif actionType == "Pause" then
        local clicks = 1
        if action.Clicks then
            clicks = tonumber(action.Clicks) or 1
        elseif action.MS then
            clicks = math.max(1, math.floor(tonumber(action.MS) / 250))
        end
        local pauseStep = { type = "macrotext", macrotext = "" }
        for _ = 1, clicks do
            steps[#steps + 1] = pauseStep
        end

    elseif actionType == "Loop" then
        if action.Actions then
            local loopRepeat = tonumber(action.Repeat) or 1
            for _ = 1, loopRepeat do
                for j = 1, #action.Actions do
                    local child = action.Actions[j]
                    if child and not child.Disabled then
                        local childSteps = self:CompileAction(child)
                        for _, s in ipairs(childSteps) do
                            steps[#steps + 1] = s
                        end
                    end
                end
            end
        end
    end

    return steps
end

--- Create or update a SecureActionButton for a macro.
-- WrapScript is only applied on initial creation to avoid stacking handlers.
-- Step data is stored as a local in the restricted environment.
function EZMacro:CreateButton(macroName, steps)
    if InCombatLockdown() then
        self:Print("Cannot create buttons during combat. Will retry after combat.")
        return false
    end

    local buttonName = SanitizeButtonName(macroName)
    local btn = self.Buttons[macroName]
    local isNewButton = false

    if not btn then
        btn = CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
        btn:RegisterForClicks("AnyUp", "AnyDown")
        self.Buttons[macroName] = btn
        isNewButton = true
    end

    self.CompiledSteps[macroName] = steps

    if #steps == 0 then
        self:Print("Warning: macro '" .. macroName .. "' compiled to 0 steps.")
        return false
    end

    -- Set initial attributes from first step
    btn:SetAttribute("step", 1)
    for k, v in pairs(steps[1]) do
        btn:SetAttribute(k, v)
    end

    -- Build step data in the restricted environment as a local variable.
    -- Uses long-bracket strings to safely embed macro text.
    local stepLines = {}
    for i, step in ipairs(steps) do
        local attrLines = {}
        for k, v in pairs(step) do
            attrLines[#attrLines + 1] = string.format("spelllist[%d][%q] = [=======[%s]=======]", i, k, tostring(v))
        end
        stepLines[#stepLines + 1] = string.format("spelllist[%d] = newtable()", i)
        stepLines[#stepLines + 1] = table.concat(attrLines, "\n")
    end

    local setupCode = string.format(
        "local spelllist = newtable()\nlocal totalSteps = %d\n%s",
        #steps,
        table.concat(stepLines, "\n")
    )

    btn:Execute(setupCode)

    -- Only wrap the OnClick handler on new button creation to avoid stacking.
    if isNewButton then
        local clickHandler = [=[
            local step = tonumber(self:GetAttribute("step") or 1)

            if not spelllist or not spelllist[step] then return end

            -- Clear previous attributes to avoid conflicts
            self:SetAttribute("macrotext", nil)
            self:SetAttribute("spell", nil)
            self:SetAttribute("macro", nil)
            self:SetAttribute("unit", nil)

            -- Set current step's attributes
            for k, v in pairs(spelllist[step]) do
                self:SetAttribute(k, v)
            end

            -- Advance to next step (wrap around)
            step = step % totalSteps + 1
            self:SetAttribute("step", step)
        ]=]

        btn:WrapScript(btn, "OnClick", clickHandler)
    end

    return true
end

--- Bind a key to a macro's secure button.
function EZMacro:BindKey(macroName, key)
    if InCombatLockdown() then
        self:Print("Cannot bind keys during combat.")
        return false
    end

    local buttonName = SanitizeButtonName(macroName)
    local btn = self.Buttons[macroName]
    if not btn then
        self:Print("No button exists for macro '" .. macroName .. "'. Import it first.")
        return false
    end

    -- Unbind any previous key for this macro
    local existing = EZMacro_CharDB.macros[macroName]
    if existing and existing.keybind then
        SetBinding(existing.keybind)
    end

    SetBindingClick(key, buttonName, "LeftButton")
    if EZMacro_CharDB.macros[macroName] then
        EZMacro_CharDB.macros[macroName].keybind = key
    end

    self:Print("Bound [" .. key .. "] to " .. macroName)
    return true
end

--- Unbind a macro's key.
function EZMacro:UnbindKey(macroName)
    if InCombatLockdown() then return false end
    local entry = EZMacro_CharDB.macros[macroName]
    if entry and entry.keybind then
        SetBinding(entry.keybind)
        entry.keybind = nil
    end
    return true
end

--- Restore all keybinds from SavedVariables. Called on PLAYER_ENTERING_WORLD.
function EZMacro:RestoreKeybinds()
    if InCombatLockdown() then return end
    for name, data in pairs(EZMacro_CharDB.macros) do
        if data.keybind and self.Buttons[name] then
            SetBindingClick(data.keybind, SanitizeButtonName(name), "LeftButton")
        end
    end
end

--- Create buttons for all stored macros. Called on PLAYER_ENTERING_WORLD.
function EZMacro:InitializeButtons()
    if InCombatLockdown() then return end
    for name, data in pairs(EZMacro_CharDB.macros) do
        local steps = self:CompileSequence(data.sequence)
        self:CreateButton(name, steps)
    end
end

--- Delete a macro: remove button, unbind, remove from DB.
function EZMacro:DeleteMacro(macroName)
    if InCombatLockdown() then
        self:Print("Cannot delete during combat.")
        return false
    end
    self:UnbindKey(macroName)
    local btn = self.Buttons[macroName]
    if btn then
        btn:Hide()
        btn:SetAttribute("type", nil)
    end
    self.Buttons[macroName] = nil
    self.CompiledSteps[macroName] = nil
    EZMacro_CharDB.macros[macroName] = nil
    self:Print("Deleted macro: " .. macroName)
    return true
end
