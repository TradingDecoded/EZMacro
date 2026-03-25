local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
local AceGUI = LibStub("AceGUI-3.0")

local exportFrame = nil

--- Show an export dialog with the encoded EZM string for copying.
-- @param macroName string The macro name to export
function EZMacro:ShowExportDialog(macroName)
    local encoded = self:EncodeEZMString(macroName)
    if not encoded then
        return
    end

    -- EncodeEZMString already persists captured talents back to data.talentLoadout,
    -- so refresh the main frame in case Load Build button should now appear
    self:RefreshMainFrame()

    if exportFrame then
        exportFrame:ReleaseChildren()
    else
        exportFrame = AceGUI:Create("Frame")
        exportFrame:SetTitle("EZMacro: Export")
        exportFrame:SetWidth(500)
        exportFrame:SetHeight(300)
        exportFrame:SetLayout("List")
        exportFrame.frame:SetFrameStrata("HIGH")
        exportFrame.frame:SetClampedToScreen(true)
        exportFrame:SetCallback("OnClose", function(widget)
            widget:Hide()
        end)
    end

    local desc = AceGUI:Create("Label")
    desc:SetText("Copy the string below (Ctrl+A, then Ctrl+C):")
    desc:SetFullWidth(true)
    exportFrame:AddChild(desc)

    local editBox = AceGUI:Create("MultiLineEditBox")
    editBox:SetLabel(macroName)
    editBox:SetText(encoded)
    editBox:SetNumLines(10)
    editBox:SetFullWidth(true)
    editBox:DisableButton(true)
    local resetting = false
    editBox:SetCallback("OnTextChanged", function(widget)
        if resetting then return end
        resetting = true
        widget:SetText(encoded)
        resetting = false
    end)
    exportFrame:AddChild(editBox)

    exportFrame:Show()
    self:Print("|cFF00FF00" .. macroName .. " ready to copy.|r")
end
