local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")

--- Capture the player's current talent loadout as an export string.
-- Loads Blizzard_PlayerSpells if needed, calls UpdateTreeInfo(), then GetLoadoutExportString().
-- @return string|nil talentString, or nil if capture fails
function EZMacro:CaptureCurrentTalents()
    local loaded, reason = C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
    if not loaded then
        self:Print("Could not load talent UI: " .. tostring(reason))
        return nil
    end
    if not PlayerSpellsFrame or not PlayerSpellsFrame.TalentsFrame then
        self:Print("Talent frame not available.")
        return nil
    end
    PlayerSpellsFrame.TalentsFrame:UpdateTreeInfo()
    local exportString = PlayerSpellsFrame.TalentsFrame:GetLoadoutExportString()
    if not exportString or exportString == "" then
        self:Print("No talent loadout to export.")
        return nil
    end
    return exportString
end

--- Encode a macro into an !EZM! string for sharing.
-- Bundles compiled steps + talent loadout into a single string.
-- @param macroName string The macro name from EZMacro_CharDB.macros
-- @return string|nil The encoded !EZM! string, or nil on failure
function EZMacro:EncodeEZMString(macroName)
    local data = EZMacro_CharDB.macros[macroName]
    if not data then
        self:Print("Macro not found: " .. macroName)
        return nil
    end

    local steps = self:GetStepsForMacro(data)
    if #steps == 0 then
        self:Print("Macro has no steps to export.")
        return nil
    end

    -- Use stored talent loadout, or capture current if none stored
    local talentLoadout = data.talentLoadout
    if not talentLoadout then
        talentLoadout = self:CaptureCurrentTalents()
        if talentLoadout then
            -- Persist captured talents back to the macro for future use
            data.talentLoadout = talentLoadout
        else
            self:Print("|cFFFF8800Exporting without talent loadout.|r")
        end
    end

    local _, _, playerClassID = UnitClass("player")
    local specIndex = GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex) or nil

    local payload = {
        formatVersion = 1,
        name = macroName,
        classID = data.classID or playerClassID,
        specID = data.specID or specID,
        talentLoadout = talentLoadout,
        steps = steps,
    }

    local ok, encoded = pcall(function()
        local cbor = C_EncodingUtil.SerializeCBOR(payload)
        local compressed = C_EncodingUtil.CompressString(cbor)
        return "!EZM!" .. C_EncodingUtil.EncodeBase64(compressed)
    end)

    if not ok then
        self:Print("Encoding failed: " .. tostring(encoded))
        return nil
    end

    return encoded
end
