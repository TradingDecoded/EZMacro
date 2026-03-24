local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
local AceGUI = LibStub("AceGUI-3.0")

local importFrame = nil

function EZMacro:ShowImportDialog()
    if importFrame then
        importFrame:ReleaseChildren()
    else
        importFrame = AceGUI:Create("Frame")
        importFrame:SetTitle("EZMacro: Import")
        importFrame:SetWidth(500)
        importFrame:SetHeight(400)
        importFrame:SetLayout("List")
        importFrame.frame:SetFrameStrata("HIGH")
        importFrame.frame:SetClampedToScreen(true)
        importFrame:SetCallback("OnClose", function(widget)
            widget:Hide()
        end)
    end

    local desc = AceGUI:Create("Label")
    desc:SetText("Paste a GSE macro string below and click Import.")
    desc:SetFullWidth(true)
    importFrame:AddChild(desc)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel("GSE Macro String")
    editBox:SetNumLines(15)
    editBox:SetFullWidth(true)
    editBox:DisableButton(true)
    importFrame:AddChild(editBox)

    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetLayout("Flow")
    btnGroup:SetFullWidth(true)

    local importBtn = AceGUI:Create("Button")
    importBtn:SetText("Import")
    importBtn:SetWidth(120)
    importBtn:SetCallback("OnClick", function()
        local text = editBox:GetText()
        if not text or strtrim(text) == "" then
            EZMacro:Print("Nothing to import -- paste a GSE string first.")
            return
        end

        local ok, msg = EZMacro:ImportString(strtrim(text))
        if ok then
            EZMacro:Print("|cFF00FF00" .. msg .. "|r")
            EZMacro:QueueAction(function()
                EZMacro:InitializeButtons()
                EZMacro:ValidateAllMacros()
                EZMacro:RefreshMainFrame()
            end)
            importFrame:Hide()
        else
            EZMacro:Print("|cFFFF0000Import failed:|r " .. msg)
        end
    end)
    btnGroup:AddChild(importBtn)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetWidth(120)
    cancelBtn:SetCallback("OnClick", function()
        importFrame:Hide()
    end)
    btnGroup:AddChild(cancelBtn)

    importFrame:AddChild(btnGroup)
    importFrame:Show()
end
