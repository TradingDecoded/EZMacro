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
        importFrame:SetHeight(450)
        importFrame:SetLayout("List")
        importFrame.frame:SetFrameStrata("HIGH")
        importFrame.frame:SetClampedToScreen(true)
        importFrame:SetCallback("OnClose", function(widget)
            widget:Hide()
        end)
    end

    local desc = AceGUI:Create("Label")
    desc:SetText("Paste an EZMacro string, GSE macro string, or raw Lua step table.\nFor Lua tables, enter a macro name first.")
    desc:SetFullWidth(true)
    importFrame:AddChild(desc)

    -- Macro name field (needed for raw Lua imports, optional for GSE strings)
    local nameBox = AceGUI:Create("EditBox")
    nameBox:SetLabel("Macro Name (required for Lua tables)")
    nameBox:SetFullWidth(true)
    importFrame:AddChild(nameBox)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel("GSE String or Lua Step Table")
    editBox:SetNumLines(13)
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
            EZMacro:Print("Nothing to import -- paste something first.")
            return
        end
        text = strtrim(text)

        local ok, msg
        -- Detect format: GSE strings start with !GSE3!, Lua tables start with {
        if text:sub(1, 5) == "!EZM!" then
            ok, msg = EZMacro:ImportEZMString(text)
        elseif text:sub(1, 5) == "!GSE3" then
            ok, msg = EZMacro:ImportString(text)
        elseif text:sub(1, 1) == "{" then
            local name = strtrim(nameBox:GetText() or "")
            if name == "" then
                EZMacro:Print("|cFFFF0000Enter a macro name for Lua table imports.|r")
                return
            end
            ok, msg = EZMacro:ImportLuaTable(name, text)
        else
            EZMacro:Print("|cFFFF0000Unrecognized format. Paste an !EZM!, !GSE3!, or Lua table starting with {|r")
            return
        end

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
