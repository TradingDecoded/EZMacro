local EZMacro = LibStub("AceAddon-3.0"):NewAddon("EZMacro", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
EZMacro.Version = "1.1.0"

function EZMacro:OnInitialize()
    if not EZMacro_GlobalDB then
        EZMacro_GlobalDB = {
            options = {
                showWarningsInChat = true,
            },
        }
    end
    if not EZMacro_CharDB then
        EZMacro_CharDB = {
            macros = {},
        }
    end

    self:RegisterChatCommand("ezm", "SlashCommand")
    self:RegisterChatCommand("ezmacro", "SlashCommand")
end

function EZMacro:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentUpdate")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnRegenDisabled")

    self:Print("EZMacro v" .. self.Version .. " loaded. Type /ezm to open.")
end

function EZMacro:OnPlayerEnteringWorld()
    self:InitializeButtons()
    self:RestoreKeybinds()
    self:ValidateAllMacros()
    if EZMacro_GlobalDB.options.showWarningsInChat then
        self:PrintWarnings()
    end
end

function EZMacro:OnTalentUpdate()
    self:ValidateAllMacros()
end

EZMacro.PendingActions = {}

function EZMacro:OnRegenDisabled()
end

function EZMacro:OnRegenEnabled()
    for _, action in ipairs(self.PendingActions) do
        action()
    end
    wipe(self.PendingActions)
    self:InitializeButtons()
end

function EZMacro:QueueAction(fn)
    if InCombatLockdown() then
        self.PendingActions[#self.PendingActions + 1] = fn
        self:Print("Action queued -- will execute after combat.")
    else
        fn()
    end
end

function EZMacro:SlashCommand(input)
    input = strtrim(input or "")
    local cmd = input:lower()

    if cmd == "" then
        self:ToggleMainFrame()
    elseif cmd == "import" then
        self:ShowImportDialog()
    elseif cmd == "list" then
        self:ListMacros()
    elseif cmd == "stop" then
        self:StopMacro()
    elseif cmd == "reset" then
        StaticPopup_Show("EZMACRO_CONFIRM_RESET")
    else
        self:Print("Usage: /ezm [import|list|stop|reset]")
    end
end

--- Stop auto-attack, clear target, and reset all macro buttons to step 1.
-- Helps drop combat at target dummies.
function EZMacro:StopMacro()
    -- Stop auto-attack (this is what keeps you in combat at dummies)
    StopAttack()
    -- Clear target so you don't re-engage
    ClearTarget()
    -- Reset all macro buttons back to step 1
    for name, btn in pairs(self.Buttons) do
        if not InCombatLockdown() then
            btn:SetAttribute("step", 1)
            btn:SetAttribute("stepped", false)
        end
    end
    self:Print("Stopped. Auto-attack off, target cleared.")
end

function EZMacro:ListMacros()
    local count = 0
    for name, data in pairs(EZMacro_CharDB.macros) do
        local bind = data.keybind or "unbound"
        local warns = #data.warnings > 0 and ("|cFFFF8800" .. #data.warnings .. " warnings|r") or "|cFF00FF00OK|r"
        self:Print("  " .. name .. " [" .. bind .. "] " .. warns)
        count = count + 1
    end
    if count == 0 then
        self:Print("No macros imported. Use /ezm import")
    end
end

function EZMacro:PrintWarnings()
    for name, data in pairs(EZMacro_CharDB.macros) do
        if data.warnings and #data.warnings > 0 then
            for _, warn in ipairs(data.warnings) do
                self:Print("|cFFFF8800" .. name .. ":|r " .. warn.spell .. " -- " .. warn.reason)
            end
        end
    end
end

StaticPopupDialogs["EZMACRO_CONFIRM_RESET"] = {
    text = "Delete ALL EZMacro macros for this character?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        local EZM = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
        local names = {}
        for name in pairs(EZMacro_CharDB.macros) do
            names[#names + 1] = name
        end
        for _, name in ipairs(names) do
            EZM:DeleteMacro(name)
        end
        EZM:Print("All macros cleared.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

--- Addon Compartment click handler (minimap addon dropdown).
function EZMacro_OnAddonCompartmentClick(addonName, buttonName)
    local EZM = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
    EZM:ToggleMainFrame()
end
