# Talent Build Import & EZM Export Format — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bundle macro steps + WoW talent loadout into a single `!EZM!` import/export string, with Load Build and Export buttons in the UI, plus addon compartment registration.

**Architecture:** New `Core/Encoder.lua` handles encoding + talent capture. `Core/Decoder.lua` gains `!EZM!` decode/import. `UI/MainFrame.lua` gets wider buttons + Load Build + Export. `UI/ExportDialog.lua` shows a copyable editbox. `Init.lua` gets addon compartment handler. `EZMacro.toc` updated for new files + compartment.

**Tech Stack:** Lua 5.1 (WoW runtime), Ace3 (AceGUI), `C_EncodingUtil` (CBOR/Base64/Compress), `C_ClassTalents`, `PlayerSpellsFrame`

**Spec:** `docs/superpowers/specs/2026-03-24-talent-build-import-design.md`

---

### Task 1: Create `Core/Encoder.lua` — Talent Capture + EZM Encoding

**Files:**
- Create: `EZMacro/Core/Encoder.lua`
- Modify: `EZMacro/EZMacro.toc:12-13` (add Encoder.lua after Decoder.lua)

- [ ] **Step 1: Create `Core/Encoder.lua` with `CaptureCurrentTalents()`**

```lua
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
```

- [ ] **Step 2: Add `EncodeEZMString()` to `Core/Encoder.lua`**

```lua
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
        specID = specID,
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
```

- [ ] **Step 3: Add `Core\Encoder.lua` to TOC file**

In `EZMacro.toc`, add after line 12 (`Core\Decoder.lua`):
```
Core\Encoder.lua
```

- [ ] **Step 4: Test in-game**

`/reload`, verify no errors. Encoder is passive (no calls yet) — just confirm it loads.

- [ ] **Step 5: Commit**

```bash
git add EZMacro/Core/Encoder.lua EZMacro/EZMacro.toc
git commit -m "feat: add Core/Encoder.lua with talent capture and EZM string encoding"
```

---

### Task 2: Add `!EZM!` Decoding + Import to `Core/Decoder.lua`

**Files:**
- Modify: `EZMacro/Core/Decoder.lua` (append two new functions at end of file)

- [ ] **Step 1: Add `DecodeEZMString()` to `Decoder.lua`**

Append at the end of the file:

```lua
--- Decode an !EZM!-prefixed string into a payload table.
-- @param data string The !EZM!-prefixed encoded string
-- @return boolean success
-- @return table|string payload or error message
function EZMacro:DecodeEZMString(data)
    if type(data) ~= "string" then
        return false, "Input must be a string"
    end
    data = strtrim(data)
    if data:sub(1, 5) ~= "!EZM!" then
        return false, "Not a valid EZM string (missing !EZM! prefix)"
    end
    local ok, result = pcall(function()
        local encoded = data:sub(6)
        local decoded = C_EncodingUtil.DecodeBase64(encoded)
        local decompressed = C_EncodingUtil.DecompressString(decoded)
        return C_EncodingUtil.DeserializeCBOR(decompressed)
    end)
    if not ok then
        return false, "Failed to decode: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return false, "Decoded data is not a table"
    end
    if result.formatVersion and result.formatVersion > 1 then
        return false, "This macro requires a newer version of EZMacro. Please update."
    end
    return true, result
end
```

- [ ] **Step 2: Add `ImportEZMString()` to `Decoder.lua`**

Append after `DecodeEZMString`:

```lua
--- Import an !EZM! string, storing the macro into EZMacro_CharDB.
-- @param inputString string The raw pasted !EZM! string
-- @return boolean success
-- @return string message
function EZMacro:ImportEZMString(inputString)
    local ok, payload = self:DecodeEZMString(inputString)
    if not ok then
        return false, payload
    end

    local name = payload.name
    if not name or name == "" then
        return false, "EZM string has no macro name"
    end

    if not payload.steps or #payload.steps == 0 then
        return false, "EZM string has no macro steps"
    end

    -- Warn on class mismatch but still import
    local _, _, playerClassID = UnitClass("player")
    if payload.classID and payload.classID > 0 and payload.classID ~= playerClassID then
        self:Print("|cFFFF8800Warning: This macro was created for a different class.|r")
    end

    local existing = EZMacro_CharDB.macros[name]
    EZMacro_CharDB.macros[name] = {
        sequence = nil,
        compiledSteps = payload.steps,
        classID = payload.classID or 0,
        specID = payload.specID,
        keybind = existing and existing.keybind or nil,
        source = inputString,
        warnings = {},
        talentLoadout = payload.talentLoadout,
    }

    return true, "Imported macro: " .. name
end
```

- [ ] **Step 3: Test in-game**

`/reload`, verify no errors. Decoder functions are passive (not called from UI yet).

- [ ] **Step 4: Commit**

```bash
git add EZMacro/Core/Decoder.lua
git commit -m "feat: add EZM string decode and import to Decoder.lua"
```

---

### Task 3: Wire `!EZM!` Import Into `UI/ImportDialog.lua`

**Files:**
- Modify: `EZMacro/UI/ImportDialog.lua:56-69` (add `!EZM!` detection branch)

- [ ] **Step 1: Add `!EZM!` auto-detection to the import button click handler**

In `ImportDialog.lua`, find the format detection block (lines 57-68). Change from:

```lua
        if text:sub(1, 5) == "!GSE3" then
            ok, msg = EZMacro:ImportString(text)
        elseif text:sub(1, 1) == "{" then
```

To:

```lua
        if text:sub(1, 5) == "!EZM!" then
            ok, msg = EZMacro:ImportEZMString(text)
        elseif text:sub(1, 5) == "!GSE3" then
            ok, msg = EZMacro:ImportString(text)
        elseif text:sub(1, 1) == "{" then
```

- [ ] **Step 2: Update the error message for unrecognized format**

Change line 67 from:
```lua
            EZMacro:Print("|cFFFF0000Unrecognized format. Paste a !GSE3! string or a Lua table starting with {|r")
```
To:
```lua
            EZMacro:Print("|cFFFF0000Unrecognized format. Paste an !EZM!, !GSE3!, or Lua table starting with {|r")
```

- [ ] **Step 3: Update dialog description label**

Change line 23 from:
```lua
    desc:SetText("Paste a GSE macro string OR a raw Lua step table below.\nFor Lua tables, enter a macro name first.")
```
To:
```lua
    desc:SetText("Paste an EZMacro string, GSE macro string, or raw Lua step table.\nFor Lua tables, enter a macro name first.")
```

- [ ] **Step 4: Test in-game**

`/reload`, open import dialog, verify description text updated. Full round-trip test will be done after Export is wired up in Task 6.

- [ ] **Step 5: Commit**

```bash
git add EZMacro/UI/ImportDialog.lua
git commit -m "feat: wire EZM string import into ImportDialog auto-detection"
```

---

### Task 4: Widen Buttons + Add Load Build Button in `UI/MainFrame.lua`

**Files:**
- Modify: `EZMacro/UI/MainFrame.lua:74-127` (`AddMacroRow` function)

- [ ] **Step 1: Widen main frame and adjust button widths**

First, widen the main frame to accommodate the new buttons. In `ShowMainFrame`, change line 21:
```lua
        mainFrame:SetWidth(500)
```
To:
```lua
        mainFrame:SetWidth(600)
```

Then in `AddMacroRow`, change label and button widths. Change line 87:
```lua
    label:SetWidth(220)
```
To:
```lua
    label:SetWidth(160)
```

Change line 92 (Bind Key button):
```lua
    bindBtn:SetWidth(80)
```
To:
```lua
    bindBtn:SetWidth(90)
```

Change line 104 (Delete button):
```lua
    deleteBtn:SetWidth(70)
```
To:
```lua
    deleteBtn:SetWidth(80)
```

- [ ] **Step 2: Add Load Build button (before Bind Key)**

Insert after the label (`row:AddChild(label)`, line 88) and before the `bindBtn` creation (line 90):

```lua
    if data.talentLoadout then
        local loadBtn = AceGUI:Create("Button")
        loadBtn:SetText("Load Build")
        loadBtn:SetWidth(100)
        loadBtn:SetCallback("OnClick", function()
            if InCombatLockdown() then
                EZMacro:Print("Cannot load build during combat.")
                return
            end
            -- Warn on class/spec mismatch
            local _, _, playerClassID = UnitClass("player")
            if data.classID and data.classID > 0 and data.classID ~= playerClassID then
                EZMacro:Print("|cFFFF8800Warning: This build is for a different class.|r")
            end
            local specIndex = GetSpecialization()
            local playerSpecID = specIndex and GetSpecializationInfo(specIndex) or nil
            if data.specID and playerSpecID and data.specID ~= playerSpecID then
                EZMacro:Print("|cFFFF8800Warning: This build is for a different specialization.|r")
            end
            -- Open talent UI with the build pre-filled
            local loaded = C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
            if loaded and PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame then
                if not PlayerSpellsFrame:IsShown() then
                    TogglePlayerSpellsFrame()
                end
                local success = PlayerSpellsFrame.TalentsFrame:LoadLoadout(data.talentLoadout)
                if success then
                    EZMacro:Print("Talent build loaded — review and click Apply.")
                else
                    EZMacro:Print("|cFFFF0000Failed to load talent build. It may be for a different spec.|r")
                end
            else
                EZMacro:Print("|cFFFF0000Could not open talent frame.|r")
            end
        end)
        row:AddChild(loadBtn)
    end
```

Note: The exact talent import API (`LoadLoadout` vs `ImportLoadout` etc.) needs verification against the live WoW client. The above uses `LoadLoadout` based on the talent frame's expected interface — adjust if the actual API differs. Test by checking `PlayerSpellsFrame.TalentsFrame` methods in-game via `/dump`.

- [ ] **Step 3: Test in-game**

`/reload`, open main frame. Existing macros should show wider buttons with no cutoff. Macros without `talentLoadout` should NOT show Load Build button.

- [ ] **Step 4: Commit**

```bash
git add EZMacro/UI/MainFrame.lua
git commit -m "feat: widen buttons, add Load Build button to macro rows"
```

---

### Task 5: Create `UI/ExportDialog.lua`

**Files:**
- Create: `EZMacro/UI/ExportDialog.lua`
- Modify: `EZMacro/EZMacro.toc` (add ExportDialog.lua after `UI\KeyBindDialog.lua`)

- [ ] **Step 1: Create `UI/ExportDialog.lua`**

```lua
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
    editBox:SetCallback("OnTextChanged", function(widget)
        -- Prevent editing — reset to encoded string
        widget:SetText(encoded)
    end)
    exportFrame:AddChild(editBox)

    exportFrame:Show()
    self:Print("|cFF00FF00" .. macroName .. " ready to copy.|r")
end
```

- [ ] **Step 2: Add `UI\ExportDialog.lua` to TOC file**

In `EZMacro.toc`, add after `UI\KeyBindDialog.lua`:
```
UI\ExportDialog.lua
```

- [ ] **Step 3: Test in-game**

`/reload`, verify no load errors.

- [ ] **Step 4: Commit**

```bash
git add EZMacro/UI/ExportDialog.lua EZMacro/EZMacro.toc
git commit -m "feat: add ExportDialog with copyable EZM string output"
```

---

### Task 6: Add Export Button to `UI/MainFrame.lua`

**Files:**
- Modify: `EZMacro/UI/MainFrame.lua` (`AddMacroRow` function — after Load Build button, before Bind Key)

- [ ] **Step 1: Add Export button to macro row**

Insert **after** the closing `end` of the `if data.talentLoadout then` block and **before** the `bindBtn` creation. This ensures the Export button always appears regardless of whether Load Build is shown:

```lua
    local exportBtn = AceGUI:Create("Button")
    exportBtn:SetText("Export")
    exportBtn:SetWidth(80)
    exportBtn:SetCallback("OnClick", function()
        EZMacro:ShowExportDialog(name)
    end)
    row:AddChild(exportBtn)
```

- [ ] **Step 2: Test full round-trip in-game**

1. `/ezm` → open main frame
2. Click Export on an existing macro → export dialog appears with `!EZM!` string
3. Copy the string
4. `/ezm import` → paste the `!EZM!` string → should import successfully
5. Verify the re-imported macro has `talentLoadout` set
6. Verify Load Build button appears on the re-imported macro

- [ ] **Step 3: Commit**

```bash
git add EZMacro/UI/MainFrame.lua
git commit -m "feat: add Export button to macro rows in MainFrame"
```

---

### Task 7: Addon Compartment Registration

**Files:**
- Modify: `EZMacro/EZMacro.toc:1-7` (add AddonCompartmentFunc metadata)
- Modify: `EZMacro/Core/Init.lua` (add global click handler)

- [ ] **Step 1: Add compartment metadata to TOC**

Add after line 5 (`## Version: 1.0.0`):
```
## AddonCompartmentFunc: EZMacro_OnAddonCompartmentClick
```

- [ ] **Step 2: Add global click handler to `Init.lua`**

Add at the end of `Init.lua` (after the StaticPopupDialogs block):

```lua
--- Addon Compartment click handler (minimap addon dropdown).
function EZMacro_OnAddonCompartmentClick(addonName, buttonName)
    local EZM = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
    EZM:ToggleMainFrame()
end
```

- [ ] **Step 3: Test in-game**

`/reload`, check that EZMacro appears in the addon compartment dropdown (click the addon bag icon near the minimap). Clicking it should toggle the main frame.

- [ ] **Step 4: Commit**

```bash
git add EZMacro/EZMacro.toc EZMacro/Core/Init.lua
git commit -m "feat: register EZMacro with addon compartment for minimap dropdown"
```

---

### Task 8: Version Bump + Update CLAUDE.md

**Files:**
- Modify: `EZMacro/EZMacro.toc:5` (version)
- Modify: `EZMacro/Core/Init.lua:2` (version string)
- Modify: `CLAUDE.md` (update architecture section with new files)

- [ ] **Step 1: Bump version to 1.1.0**

In `EZMacro.toc` line 5, change:
```
## Version: 1.0.0
```
To:
```
## Version: 1.1.0
```

In `Init.lua` line 2, change:
```lua
EZMacro.Version = "1.0.0"
```
To:
```lua
EZMacro.Version = "1.1.0"
```

- [ ] **Step 2: Update CLAUDE.md file tree**

Add `Core/Encoder.lua` and `UI/ExportDialog.lua` to the file tree in CLAUDE.md, and add a note about the `!EZM!` format under Data flow.

- [ ] **Step 3: Commit**

```bash
git add EZMacro/EZMacro.toc EZMacro/Core/Init.lua CLAUDE.md
git commit -m "chore: bump version to 1.1.0, update CLAUDE.md with new files"
```

---

### Task 9: Verify Talent Import API In-Game

**BLOCKING:** This task must be completed before any release. The `LoadLoadout` API name used in Task 4 is unverified and may need correction.

**Files:** None (manual verification task)

- [ ] **Step 1: Verify `C_ClassTalents` and talent frame APIs**

Run these in-game via `/dump` or `/run`:
```lua
/dump type(C_ClassTalents)
/dump type(C_ClassTalents.ImportLoadout)
/run for k,v in pairs(PlayerSpellsFrame.TalentsFrame) do if type(v)=="function" and k:find("oad") then print(k) end end
```

Look for the correct method name — it may be `ImportLoadout`, `LoadLoadout`, or something else. Update the `Load Build` button handler in `MainFrame.lua` if the API differs from what's in the plan.

- [ ] **Step 2: Test Load Build end-to-end**

1. Import an `!EZM!` string that has a `talentLoadout`
2. Click Load Build
3. Verify the talent UI opens with the build pre-filled
4. Confirm or cancel — both should work cleanly

- [ ] **Step 3: Fix API if needed and commit**

```bash
git add EZMacro/UI/MainFrame.lua
git commit -m "fix: correct talent import API call after live verification"
```
