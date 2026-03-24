local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")

--- Extract spell names from compiled steps.
function EZMacro:ExtractSpells(steps)
    local spells = {}
    local seen = {}
    for _, step in ipairs(steps) do
        local spellName = nil
        if step.spell then
            spellName = step.spell
        elseif step.macrotext then
            for line in step.macrotext:gmatch("[^\n]+") do
                local name = line:match("^/cast%s+(.+)") or line:match("^/use%s+(.+)")
                if name then
                    name = name:match("%]%s*(.+)") or name
                    name = strtrim(name)
                    if name ~= "" and not seen[name] then
                        seen[name] = true
                        spells[#spells + 1] = name
                    end
                end
            end
        end
        if spellName and not seen[spellName] then
            seen[spellName] = true
            spells[#spells + 1] = spellName
        end
    end
    return spells
end

--- Validate a single macro's spells against the player's known abilities.
function EZMacro:ValidateMacro(macroName, data)
    data.warnings = {}

    if data.classID and data.classID > 0 then
        local _, _, playerClassID = UnitClass("player")
        if data.classID ~= playerClassID then
            data.warnings[#data.warnings + 1] = {
                spell = "(class)",
                reason = "This macro is for a different class",
            }
        end
    end

    local steps = self:CompileSequence(data.sequence)
    local spells = self:ExtractSpells(steps)
    for _, spellName in ipairs(spells) do
        local spellInfo = C_Spell.GetSpellInfo(spellName)
        if spellInfo and spellInfo.spellID then
            if not IsSpellKnown(spellInfo.spellID) and not IsPlayerSpell(spellInfo.spellID) then
                data.warnings[#data.warnings + 1] = {
                    spell = spellName,
                    reason = "Not known (missing talent or wrong spec)",
                }
            end
        end
    end
end

--- Validate all stored macros.
function EZMacro:ValidateAllMacros()
    for name, data in pairs(EZMacro_CharDB.macros) do
        self:ValidateMacro(name, data)
    end
end
