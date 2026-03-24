local EZMacro = LibStub("AceAddon-3.0"):NewAddon("EZMacro", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
EZMacro.Version = "1.0.0"

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
end

function EZMacro:OnEnable()
    self:Print("EZMacro v" .. self.Version .. " loaded.")
end
