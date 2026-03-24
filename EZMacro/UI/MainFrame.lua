local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
local AceGUI = LibStub("AceGUI-3.0")

local mainFrame = nil

function EZMacro:ToggleMainFrame()
    if mainFrame and mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:ShowMainFrame()
    end
end

function EZMacro:ShowMainFrame()
    if mainFrame then
        mainFrame:ReleaseChildren()
    else
        mainFrame = AceGUI:Create("Frame")
        mainFrame:SetTitle("EZMacro")
        mainFrame:SetStatusText("EZMacro v" .. self.Version)
        mainFrame:SetWidth(500)
        mainFrame:SetHeight(450)
        mainFrame:SetLayout("Fill")
        mainFrame.frame:SetFrameStrata("MEDIUM")
        mainFrame.frame:SetClampedToScreen(true)
        mainFrame:SetCallback("OnClose", function(widget)
            widget:Hide()
        end)
    end

    local scrollContainer = AceGUI:Create("SimpleGroup")
    scrollContainer:SetFullWidth(true)
    scrollContainer:SetFullHeight(true)
    scrollContainer:SetLayout("Fill")
    mainFrame:AddChild(scrollContainer)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scrollContainer:AddChild(scroll)

    local importBtn = AceGUI:Create("Button")
    importBtn:SetText("Import GSE Macro")
    importBtn:SetFullWidth(true)
    importBtn:SetCallback("OnClick", function()
        if InCombatLockdown() then
            EZMacro:Print("Cannot import during combat.")
            return
        end
        EZMacro:ShowImportDialog()
    end)
    scroll:AddChild(importBtn)

    local spacer = AceGUI:Create("Heading")
    spacer:SetText("Imported Macros")
    spacer:SetFullWidth(true)
    scroll:AddChild(spacer)

    local hasMacros = false
    for name, data in pairs(EZMacro_CharDB.macros) do
        hasMacros = true
        self:AddMacroRow(scroll, name, data)
    end

    if not hasMacros then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetText("No macros imported yet. Click 'Import GSE Macro' above.")
        emptyLabel:SetFullWidth(true)
        scroll:AddChild(emptyLabel)
    end

    mainFrame:Show()
end

function EZMacro:AddMacroRow(parent, name, data)
    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")

    local label = AceGUI:Create("Label")
    local labelText = "|cFFFFFFFF" .. name .. "|r"
    if data.keybind then
        labelText = labelText .. "  |cFF00FF00[" .. data.keybind .. "]|r"
    else
        labelText = labelText .. "  |cFF888888[unbound]|r"
    end
    label:SetText(labelText)
    label:SetWidth(220)
    row:AddChild(label)

    local bindBtn = AceGUI:Create("Button")
    bindBtn:SetText("Bind Key")
    bindBtn:SetWidth(80)
    bindBtn:SetCallback("OnClick", function()
        if InCombatLockdown() then
            EZMacro:Print("Cannot bind keys during combat.")
            return
        end
        EZMacro:ShowKeyBindDialog(name)
    end)
    row:AddChild(bindBtn)

    local deleteBtn = AceGUI:Create("Button")
    deleteBtn:SetText("Delete")
    deleteBtn:SetWidth(70)
    deleteBtn:SetCallback("OnClick", function()
        if InCombatLockdown() then
            EZMacro:Print("Cannot delete during combat.")
            return
        end
        EZMacro:DeleteMacro(name)
        EZMacro:ShowMainFrame()
    end)
    row:AddChild(deleteBtn)

    parent:AddChild(row)

    if data.warnings and #data.warnings > 0 then
        local warnLabel = AceGUI:Create("Label")
        local warnTexts = {}
        for _, w in ipairs(data.warnings) do
            warnTexts[#warnTexts + 1] = w.spell .. ": " .. w.reason
        end
        warnLabel:SetText("|cFFFF8800  Warnings: " .. table.concat(warnTexts, ", ") .. "|r")
        warnLabel:SetFullWidth(true)
        parent:AddChild(warnLabel)
    end
end

function EZMacro:RefreshMainFrame()
    if mainFrame and mainFrame:IsShown() then
        self:ShowMainFrame()
    end
end
