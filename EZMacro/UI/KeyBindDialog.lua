local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
local AceGUI = LibStub("AceGUI-3.0")

local bindFrame = nil
local pendingMacro = nil

function EZMacro:ShowKeyBindDialog(macroName)
    if InCombatLockdown() then
        self:Print("Cannot bind keys during combat.")
        return
    end

    pendingMacro = macroName

    if bindFrame then
        bindFrame:ReleaseChildren()
    else
        bindFrame = AceGUI:Create("Frame")
        bindFrame:SetTitle("EZMacro: Bind Key")
        bindFrame:SetWidth(350)
        bindFrame:SetHeight(200)
        bindFrame:SetLayout("List")
        bindFrame.frame:SetFrameStrata("DIALOG")
        bindFrame.frame:SetClampedToScreen(true)
        bindFrame:SetCallback("OnClose", function(widget)
            widget:Hide()
            pendingMacro = nil
        end)
    end

    local label = AceGUI:Create("Label")
    label:SetText("|cFFFFFFFFBinding macro:|r " .. macroName .. "\n\nPress any key to bind...")
    label:SetFullWidth(true)
    label:SetFontObject(GameFontNormalLarge)
    bindFrame:AddChild(label)

    local keybind = AceGUI:Create("Keybinding")
    keybind:SetLabel("Press a key")
    keybind:SetFullWidth(true)
    keybind:SetCallback("OnKeyChanged", function(widget, event, key)
        if not key or key == "" then return end
        if not pendingMacro then return end

        local existingAction = GetBindingAction(key)
        if existingAction and existingAction ~= "" then
            EZMacro:Print("Note: key [" .. key .. "] was previously bound to '" .. existingAction .. "'")
        end

        local success = EZMacro:BindKey(pendingMacro, key)
        if success then
            bindFrame:Hide()
            pendingMacro = nil
            EZMacro:RefreshMainFrame()
        end
    end)
    bindFrame:AddChild(keybind)

    local currentData = EZMacro_CharDB.macros[macroName]
    if currentData and currentData.keybind then
        local unbindBtn = AceGUI:Create("Button")
        unbindBtn:SetText("Unbind [" .. currentData.keybind .. "]")
        unbindBtn:SetFullWidth(true)
        unbindBtn:SetCallback("OnClick", function()
            EZMacro:UnbindKey(macroName)
            bindFrame:Hide()
            pendingMacro = nil
            EZMacro:RefreshMainFrame()
            EZMacro:Print("Unbound " .. macroName)
        end)
        bindFrame:AddChild(unbindBtn)
    end

    bindFrame:Show()
end
