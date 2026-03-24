# EZMacro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a simplified WoW addon that imports GSE macro strings, validates talent/spell requirements, and binds macros to keys with a dead-simple UI.

**Architecture:** Single WoW addon using Ace3 framework. Core pipeline: decode GSE string → store per-character → compile to step table → create SecureActionButton with WrapScript → bind key. UI is three AceGUI dialogs: main panel, import, keybind.

**Tech Stack:** Lua 5.1 (WoW), Ace3 (AceAddon, AceConsole, AceEvent, AceGUI, AceTimer), WoW retail API (120001+), C_EncodingUtil for CBOR/compression.

**Spec:** `docs/superpowers/specs/2026-03-24-ezmacro-design.md`

---

## File Structure

```
EZMacro/
├── EZMacro.toc              # Addon descriptor, load order, SavedVariables
├── Libs/                     # Copied from old-addon/GSE/Lib/
│   ├── LibStub/
│   ├── CallbackHandler-1.0/
│   ├── AceAddon-3.0/
│   ├── AceConsole-3.0/
│   ├── AceEvent-3.0/
│   ├── AceGUI-3.0/
│   └── AceTimer-3.0/
├── embeds.xml                # Library load manifest
├── Core/
│   ├── Init.lua              # AceAddon bootstrap, SavedVariables defaults, slash commands, event wiring
│   ├── Decoder.lua           # GSE string decode + collection parsing
│   └── Engine.lua            # SecureActionButton lifecycle, step compilation, WrapScript, keybinds
├── UI/
│   ├── MainFrame.lua         # Main panel with macro list, action buttons
│   ├── ImportDialog.lua      # Paste box for GSE strings
│   └── KeyBindDialog.lua     # Key capture dialog
└── Validation/
    └── TalentCheck.lua       # Spell availability checking
```

---

## Task 1: Scaffold Addon — TOC, Libs, embeds.xml

**Files:**
- Create: `EZMacro/EZMacro.toc`
- Create: `EZMacro/embeds.xml`
- Copy: `EZMacro/Libs/` (from `old-addon/GSE/Lib/`)

WoW addons can't be unit-tested outside the client. Testing is manual: copy addon to `Interface/AddOns/`, `/reload` in-game. Each task ends with a verification step describing what to check in-game.

- [ ] **Step 1: Copy Ace3 libraries**

Copy these directories from `old-addon/GSE/Lib/` to `EZMacro/Libs/`:
- `LibStub/`
- `CallbackHandler-1.0/`
- `AceAddon-3.0/`
- `AceConsole-3.0/`
- `AceEvent-3.0/`
- `AceGUI-3.0/`
- `AceTimer-3.0/`

- [ ] **Step 2: Create embeds.xml**

Create `EZMacro/embeds.xml`:

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\FrameXML\UI.xsd">
    <Script file="Libs\LibStub\LibStub.lua"/>
    <Include file="Libs\CallbackHandler-1.0\CallbackHandler-1.0.xml"/>
    <Include file="Libs\AceAddon-3.0\AceAddon-3.0.xml"/>
    <Include file="Libs\AceConsole-3.0\AceConsole-3.0.xml"/>
    <Include file="Libs\AceGUI-3.0\AceGUI-3.0.xml"/>
    <Include file="Libs\AceEvent-3.0\AceEvent-3.0.xml"/>
    <Include file="Libs\AceTimer-3.0\AceTimer-3.0.xml"/>
</Ui>
```

- [ ] **Step 3: Create EZMacro.toc**

```toc
## Interface: 120001
## Title: EZMacro
## Notes: Simple GSE macro importer with one-click keybinding.
## Author: Jimmy
## Version: 1.0.0
## SavedVariables: EZMacro_GlobalDB
## SavedVariablesPerCharacter: EZMacro_CharDB

embeds.xml

Core\Init.lua
Core\Decoder.lua
Core\Engine.lua
Validation\TalentCheck.lua
UI\MainFrame.lua
UI\ImportDialog.lua
UI\KeyBindDialog.lua
```

- [ ] **Step 4: Create stub Init.lua**

Create `EZMacro/Core/Init.lua` — minimal addon that loads and prints to chat:

```lua
local EZMacro = LibStub("AceAddon-3.0"):NewAddon("EZMacro", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
EZMacro.Version = "1.0.0"

function EZMacro:OnInitialize()
    -- Initialize SavedVariables with defaults
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
```

- [ ] **Step 5: Create empty stub files**

Create these empty files so the TOC doesn't error on missing files:
- `EZMacro/Core/Decoder.lua` — `local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")`
- `EZMacro/Core/Engine.lua` — same one-liner, plus no-op stubs:
  ```lua
  local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
  EZMacro.Buttons = {}
  EZMacro.CompiledSteps = {}
  function EZMacro:InitializeButtons() end
  function EZMacro:RestoreKeybinds() end
  function EZMacro:DeleteMacro() end
  function EZMacro:CompileSequence() return {} end
  ```
- `EZMacro/Validation/TalentCheck.lua` — stub with no-ops:
  ```lua
  local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
  function EZMacro:ValidateAllMacros() end
  function EZMacro:PrintWarnings() end
  ```
- `EZMacro/UI/MainFrame.lua` — stub with no-ops:
  ```lua
  local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
  function EZMacro:ToggleMainFrame() EZMacro:Print("Main frame not yet implemented.") end
  function EZMacro:RefreshMainFrame() end
  ```
- `EZMacro/UI/ImportDialog.lua` — stub:
  ```lua
  local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
  function EZMacro:ShowImportDialog() EZMacro:Print("Import dialog not yet implemented.") end
  ```
- `EZMacro/UI/KeyBindDialog.lua` — stub:
  ```lua
  local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
  function EZMacro:ShowKeyBindDialog() EZMacro:Print("Keybind dialog not yet implemented.") end
  ```

- [ ] **Step 6: Commit**

```bash
git add EZMacro/
git commit -m "feat: scaffold EZMacro addon with Ace3 libs and TOC"
```

- [ ] **Step 7: Verify in-game**

Copy `EZMacro/` to WoW's `Interface/AddOns/` directory. Log in, check:
- Addon appears in addon list
- Chat prints "EZMacro v1.0.0 loaded." on login
- No Lua errors

---

## Task 2: Decoder — GSE String Import

**Files:**
- Modify: `EZMacro/Core/Decoder.lua`

- [ ] **Step 1: Implement DecodeGSEString**

```lua
local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")

--- Decode a GSE3 encoded string into a Lua table.
-- @param data string The !GSE3!-prefixed encoded string
-- @return boolean success
-- @return table|string result or error message
function EZMacro:DecodeGSEString(data)
    if type(data) ~= "string" then
        return false, "Input must be a string"
    end
    data = strtrim(data)
    if data:sub(1, 6) ~= "!GSE3!" then
        return false, "Not a valid GSE3 string (missing !GSE3! prefix)"
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
    return true, result
end
```

- [ ] **Step 2: Implement ImportString — handles both single sequences and collections**

```lua
--- Import a GSE string, storing decoded macros into EZMacro_CharDB.
-- @param inputString string The raw pasted string
-- @return boolean success
-- @return string message (success or error description)
function EZMacro:ImportString(inputString)
    local ok, decoded = self:DecodeGSEString(inputString)
    if not ok then
        return false, decoded
    end

    local count = 0

    if type(decoded) == "table" and decoded.type == "COLLECTION" then
        -- Collection import
        local payload = decoded.payload
        if payload and payload.Sequences then
            for name, sequence in pairs(payload.Sequences) do
                self:StoreSequence(name, sequence, inputString)
                count = count + 1
            end
        end
        -- Store Variables and Macros sub-tables for forward compatibility
        if payload and payload.Variables then
            if not EZMacro_CharDB.variables then EZMacro_CharDB.variables = {} end
            for k, v in pairs(payload.Variables) do
                EZMacro_CharDB.variables[k] = v
            end
        end
        if payload and payload.Macros then
            if not EZMacro_CharDB.rawMacros then EZMacro_CharDB.rawMacros = {} end
            for k, v in pairs(payload.Macros) do
                EZMacro_CharDB.rawMacros[k] = v
            end
        end
    elseif type(decoded) == "table" and decoded[1] and decoded[2] then
        -- Single sequence: {name, sequenceTable}
        local name = decoded[1]
        local sequence = decoded[2]
        self:StoreSequence(name, sequence, inputString)
        count = 1
    else
        return false, "Unrecognized GSE format"
    end

    return true, count .. " macro(s) imported"
end

--- Store a single sequence into per-character DB.
-- @param name string Sequence name
-- @param sequence table The decoded sequence table
-- @param source string Original encoded string
function EZMacro:StoreSequence(name, sequence, source)
    local classID = 0
    if sequence.MetaData and sequence.MetaData.ClassID then
        classID = sequence.MetaData.ClassID
    end

    local existing = EZMacro_CharDB.macros[name]
    EZMacro_CharDB.macros[name] = {
        sequence = sequence,
        classID = classID,
        keybind = existing and existing.keybind or nil,  -- preserve existing keybind
        source = source,
        warnings = {},
    }
end
```

- [ ] **Step 3: Commit**

```bash
git add EZMacro/Core/Decoder.lua
git commit -m "feat: implement GSE string decoder and import logic"
```

- [ ] **Step 4: Verify in-game**

Open WoW, `/reload`. In a macro or via `/script`:
```
/script local ok, msg = LibStub("AceAddon-3.0"):GetAddon("EZMacro"):ImportString("PASTE_A_REAL_GSE_STRING_HERE"); print(ok, msg)
```
Verify it prints `true 1 macro(s) imported` (or collection count).

---

## Task 3: Engine — SecureActionButton + Step Execution

**Files:**
- Modify: `EZMacro/Core/Engine.lua`

This is the most complex task. The engine creates secure buttons, compiles sequences into step tables, and wires the WrapScript that cycles through steps on each keypress.

- [ ] **Step 1: Implement GetActiveVersion — select Default version from a sequence**

```lua
local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")

-- Compiled step tables per button: EZMacro.CompiledSteps["ButtonName"] = { {attrs...}, {attrs...}, ... }
EZMacro.CompiledSteps = {}
-- Secure button references: EZMacro.Buttons["MacroName"] = buttonFrame
EZMacro.Buttons = {}

--- Get the active version table from a GSE sequence.
-- Uses MetaData.Default, falls back to version 1.
-- @param sequence table The full GSE sequence with Versions and MetaData
-- @return table The selected version's action/macro data
function EZMacro:GetActiveVersion(sequence)
    if not sequence or not sequence.Versions then
        return nil
    end
    local versionNum = 1
    if sequence.MetaData and sequence.MetaData.Default then
        versionNum = sequence.MetaData.Default
    end
    if versionNum == 0 then versionNum = 1 end
    return sequence.Versions[versionNum]
end
```

- [ ] **Step 2: Implement CompileSequence — flatten version actions into a step table**

```lua
--- Compile a sequence version into a flat step table.
-- Each step is a table of attributes: {type="spell"|"macrotext", spell="X", ...}
-- @param sequence table The full GSE sequence
-- @return table steps Array of {type, spell/macrotext, ...} tables
function EZMacro:CompileSequence(sequence)
    local version = self:GetActiveVersion(sequence)
    if not version then return {} end

    local steps = {}
    local actions = version.Actions or version

    -- If actions is a numbered array of action blocks
    if type(actions) == "table" then
        for i = 1, #actions do
            local action = actions[i]
            if action and not action.Disabled then
                local compiled = self:CompileAction(action)
                for _, step in ipairs(compiled) do
                    steps[#steps + 1] = step
                end
            end
        end
    end

    -- Fallback: if no steps compiled, try treating the version itself as macro text
    if #steps == 0 and type(version) == "table" then
        for i = 1, #version do
            if type(version[i]) == "string" then
                steps[#steps + 1] = { type = "macrotext", macrotext = version[i] }
            end
        end
    end

    return steps
end

--- Compile a single action block into one or more steps.
-- Handles Action and Pause types. Loops deferred to v2.
-- @param action table A single action block from the sequence
-- @return table Array of step attribute tables
function EZMacro:CompileAction(action)
    local steps = {}
    local actionType = action.Type or "Action"

    if actionType == "Action" then
        local attrs = {}
        if action.macrotext then
            attrs.type = "macrotext"
            attrs.macrotext = action.macrotext
        elseif action.spell then
            attrs.type = "spell"
            attrs.spell = action.spell
        elseif type(action[1]) == "string" then
            -- Legacy format: action is just a macro text string in an array
            attrs.type = "macrotext"
            attrs.macrotext = action[1]
        end

        if next(attrs) then
            local repeat_count = tonumber(action.Repeat) or 1
            for _ = 1, repeat_count do
                steps[#steps + 1] = attrs
            end
        end

    elseif actionType == "Pause" then
        -- Pause: insert a no-op step (empty macrotext)
        local clicks = 1
        if action.Clicks then
            clicks = tonumber(action.Clicks) or 1
        elseif action.MS then
            -- Rough conversion: assume ~250ms per click at typical spam rate
            clicks = math.max(1, math.floor(tonumber(action.MS) / 250))
        end
        local pauseStep = { type = "macrotext", macrotext = "" }
        for _ = 1, clicks do
            steps[#steps + 1] = pauseStep
        end

    elseif actionType == "Loop" then
        -- Loop: recursively compile children
        if action.Actions then
            local loopRepeat = tonumber(action.Repeat) or 1
            for _ = 1, loopRepeat do
                for j = 1, #action.Actions do
                    local child = action.Actions[j]
                    if child and not child.Disabled then
                        local childSteps = self:CompileAction(child)
                        for _, s in ipairs(childSteps) do
                            steps[#steps + 1] = s
                        end
                    end
                end
            end
        end
    end

    return steps
end
```

- [ ] **Step 3: Implement CreateButton — build SecureActionButton with WrapScript**

```lua
--- Sanitize a macro name into a valid WoW global frame name (alphanumeric + underscore).
-- @param name string The raw macro name
-- @return string Sanitized name safe for global frame names
local function SanitizeButtonName(name)
    return "EZMacro_" .. name:gsub("[^%w]", "_")
end

--- Create or update a SecureActionButton for a macro.
-- Must be called out of combat.
-- WrapScript is only applied on initial creation to avoid stacking handlers.
-- Step data is stored as a local in the restricted environment (not via SetAttribute)
-- to match GSE's proven approach.
-- @param macroName string The macro name
-- @param steps table Compiled step table from CompileSequence
function EZMacro:CreateButton(macroName, steps)
    if InCombatLockdown() then
        self:Print("Cannot create buttons during combat. Will retry after combat.")
        return false
    end

    local buttonName = SanitizeButtonName(macroName)
    local btn = self.Buttons[macroName]
    local isNewButton = false

    if not btn then
        btn = CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
        btn:RegisterForClicks("AnyUp", "AnyDown")
        self.Buttons[macroName] = btn
        isNewButton = true
    end

    self.CompiledSteps[macroName] = steps

    if #steps == 0 then
        self:Print("Warning: macro '" .. macroName .. "' compiled to 0 steps.")
        return false
    end

    -- Set initial attributes from first step
    btn:SetAttribute("step", 1)
    for k, v in pairs(steps[1]) do
        btn:SetAttribute(k, v)
    end

    -- Build step data in the restricted environment as a local variable.
    -- Uses long-bracket strings to safely embed macro text (avoids escape issues).
    -- The spelllist local persists in the button's restricted scope for WrapScript access.
    local stepLines = {}
    for i, step in ipairs(steps) do
        local attrLines = {}
        for k, v in pairs(step) do
            -- Use long brackets for values to safely handle special characters
            attrLines[#attrLines + 1] = string.format("spelllist[%d][%q] = [=======[%s]=======]", i, k, tostring(v))
        end
        stepLines[#stepLines + 1] = string.format("spelllist[%d] = newtable()", i)
        stepLines[#stepLines + 1] = table.concat(attrLines, "\n")
    end

    local setupCode = string.format(
        "local spelllist = newtable()\nlocal totalSteps = %d\n%s",
        #steps,
        table.concat(stepLines, "\n")
    )

    btn:Execute(setupCode)

    -- Only wrap the OnClick handler on new button creation to avoid stacking.
    -- The handler reads spelllist/totalSteps locals from the restricted environment scope.
    if isNewButton then
        local clickHandler = [=[
            local step = tonumber(self:GetAttribute("step") or 1)

            if not spelllist or not spelllist[step] then return end

            -- Clear previous attributes to avoid conflicts
            self:SetAttribute("macrotext", nil)
            self:SetAttribute("spell", nil)
            self:SetAttribute("macro", nil)
            self:SetAttribute("unit", nil)

            -- Set current step's attributes
            for k, v in pairs(spelllist[step]) do
                self:SetAttribute(k, v)
            end

            -- Advance to next step (wrap around)
            step = step % totalSteps + 1
            self:SetAttribute("step", step)
        ]=]

        btn:WrapScript(btn, "OnClick", clickHandler)
    end

    return true
end
```

- [ ] **Step 4: Implement keybind functions**

```lua
--- Bind a key to a macro's secure button.
-- Must be called out of combat.
-- @param macroName string The macro name
-- @param key string The key to bind (e.g., "F1", "CTRL-F")
-- @return boolean success
function EZMacro:BindKey(macroName, key)
    if InCombatLockdown() then
        self:Print("Cannot bind keys during combat.")
        return false
    end

    local buttonName = SanitizeButtonName(macroName)
    local btn = self.Buttons[macroName]
    if not btn then
        self:Print("No button exists for macro '" .. macroName .. "'. Import it first.")
        return false
    end

    -- Unbind any previous key for this macro
    local existing = EZMacro_CharDB.macros[macroName]
    if existing and existing.keybind then
        SetBinding(existing.keybind)  -- clear old binding
    end

    SetBindingClick(key, buttonName, "LeftButton")
    -- Persist
    if EZMacro_CharDB.macros[macroName] then
        EZMacro_CharDB.macros[macroName].keybind = key
    end

    self:Print("Bound [" .. key .. "] to " .. macroName)
    return true
end

--- Unbind a macro's key.
-- @param macroName string
function EZMacro:UnbindKey(macroName)
    if InCombatLockdown() then return false end
    local entry = EZMacro_CharDB.macros[macroName]
    if entry and entry.keybind then
        SetBinding(entry.keybind)
        entry.keybind = nil
    end
    return true
end

--- Restore all keybinds from SavedVariables. Called on PLAYER_ENTERING_WORLD.
function EZMacro:RestoreKeybinds()
    if InCombatLockdown() then return end
    for name, data in pairs(EZMacro_CharDB.macros) do
        if data.keybind and self.Buttons[name] then
            SetBindingClick(data.keybind, SanitizeButtonName(name), "LeftButton")
        end
    end
end

--- Create buttons for all stored macros. Called on PLAYER_ENTERING_WORLD.
function EZMacro:InitializeButtons()
    if InCombatLockdown() then return end
    for name, data in pairs(EZMacro_CharDB.macros) do
        local steps = self:CompileSequence(data.sequence)
        self:CreateButton(name, steps)
    end
end

--- Delete a macro: remove button, unbind, remove from DB.
-- @param macroName string
function EZMacro:DeleteMacro(macroName)
    if InCombatLockdown() then
        self:Print("Cannot delete during combat.")
        return false
    end
    self:UnbindKey(macroName)
    -- Hide button (can't destroy frames in WoW, but we can hide and unregister)
    local btn = self.Buttons[macroName]
    if btn then
        btn:Hide()
        btn:SetAttribute("type", nil)
    end
    self.Buttons[macroName] = nil
    self.CompiledSteps[macroName] = nil
    EZMacro_CharDB.macros[macroName] = nil
    self:Print("Deleted macro: " .. macroName)
    return true
end
```

- [ ] **Step 5: Commit**

```bash
git add EZMacro/Core/Engine.lua
git commit -m "feat: implement macro engine with secure buttons, step execution, and keybinds"
```

- [ ] **Step 6: Verify in-game**

After importing a macro (Task 2), test via `/script`:
```lua
/script local E = LibStub("AceAddon-3.0"):GetAddon("EZMacro"); E:InitializeButtons(); E:RestoreKeybinds()
```
Check that no Lua errors occur. Full keybind testing comes after the UI is built.

---

## Task 4: Init.lua — Event Wiring and Slash Commands

**Files:**
- Modify: `EZMacro/Core/Init.lua`

- [ ] **Step 1: Add event handlers and slash commands**

Replace the stub Init.lua with the full version:

```lua
local EZMacro = LibStub("AceAddon-3.0"):NewAddon("EZMacro", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
EZMacro.Version = "1.0.0"

function EZMacro:OnInitialize()
    -- Initialize SavedVariables with defaults
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

    -- Register slash commands
    self:RegisterChatCommand("ezm", "SlashCommand")
    self:RegisterChatCommand("ezmacro", "SlashCommand")
end

function EZMacro:OnEnable()
    -- Register events
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentUpdate")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnRegenDisabled")

    self:Print("EZMacro v" .. self.Version .. " loaded. Type /ezm to open.")
end

function EZMacro:OnPlayerEnteringWorld()
    -- Create buttons for all stored macros (must be out of combat)
    self:InitializeButtons()
    -- Restore keybinds
    self:RestoreKeybinds()
    -- Run talent validation
    self:ValidateAllMacros()
    -- Print warnings if enabled
    if EZMacro_GlobalDB.options.showWarningsInChat then
        self:PrintWarnings()
    end
end

function EZMacro:OnTalentUpdate()
    self:ValidateAllMacros()
end

-- Combat lockdown tracking
EZMacro.PendingActions = {}

function EZMacro:OnRegenDisabled()
    -- Combat started — UI will check InCombatLockdown() before actions
end

function EZMacro:OnRegenEnabled()
    -- Combat ended — flush pending actions
    for _, action in ipairs(self.PendingActions) do
        action()
    end
    wipe(self.PendingActions)
    -- Re-initialize any buttons that were queued
    self:InitializeButtons()
end

function EZMacro:QueueAction(fn)
    if InCombatLockdown() then
        self.PendingActions[#self.PendingActions + 1] = fn
        self:Print("Action queued — will execute after combat.")
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
    elseif cmd == "reset" then
        StaticPopup_Show("EZMACRO_CONFIRM_RESET")
    else
        self:Print("Usage: /ezm [import|list|reset]")
    end
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
        if #data.warnings > 0 then
            for _, warn in ipairs(data.warnings) do
                self:Print("|cFFFF8800" .. name .. ":|r " .. warn.spell .. " — " .. warn.reason)
            end
        end
    end
end

-- Static popup for reset confirmation
StaticPopupDialogs["EZMACRO_CONFIRM_RESET"] = {
    text = "Delete ALL EZMacro macros for this character?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        local EZM = LibStub("AceAddon-3.0"):GetAddon("EZMacro")
        -- Collect names first to avoid modifying table during iteration
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
```

- [ ] **Step 2: Commit**

```bash
git add EZMacro/Core/Init.lua
git commit -m "feat: add event wiring, slash commands, and combat lockdown handling"
```

- [ ] **Step 3: Verify in-game**

- `/ezm` should print "Main frame not yet implemented." (stub from Task 1)
- `/ezm list` should print "No macros imported"
- Login should print "EZMacro v1.0.0 loaded"
- No Lua errors

---

## Task 5: TalentCheck — Spell Validation

**Files:**
- Modify: `EZMacro/Validation/TalentCheck.lua`

- [ ] **Step 1: Implement spell extraction and validation**

```lua
local EZMacro = LibStub("AceAddon-3.0"):GetAddon("EZMacro")

--- Extract spell names from compiled steps.
-- @param steps table Compiled step table
-- @return table Array of unique spell name strings
function EZMacro:ExtractSpells(steps)
    local spells = {}
    local seen = {}
    for _, step in ipairs(steps) do
        local spellName = nil
        if step.spell then
            spellName = step.spell
        elseif step.macrotext then
            -- Parse /cast and /use commands from macrotext
            for line in step.macrotext:gmatch("[^\n]+") do
                local name = line:match("^/cast%s+(.+)") or line:match("^/use%s+(.+)")
                if name then
                    -- Strip conditionals: /cast [mod:shift] Spell Name → Spell Name
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
-- @param macroName string
-- @param data table The macro entry from EZMacro_CharDB
function EZMacro:ValidateMacro(macroName, data)
    data.warnings = {}

    -- Class mismatch check
    if data.classID and data.classID > 0 then
        local _, _, playerClassID = UnitClass("player")
        if data.classID ~= playerClassID then
            data.warnings[#data.warnings + 1] = {
                spell = "(class)",
                reason = "This macro is for a different class",
            }
        end
    end

    -- Spell availability check
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
        -- If spellInfo is nil, the spell name may be invalid or an item — skip silently
    end
end

--- Validate all stored macros.
function EZMacro:ValidateAllMacros()
    for name, data in pairs(EZMacro_CharDB.macros) do
        self:ValidateMacro(name, data)
    end
end
```

- [ ] **Step 2: Commit**

```bash
git add EZMacro/Validation/TalentCheck.lua
git commit -m "feat: implement talent/spell validation with class mismatch detection"
```

- [ ] **Step 3: Verify in-game**

Import a macro, then `/reload`. Check chat for talent warnings (if any spells are missing). Switch specs and `/reload` to verify warnings update.

---

## Task 6: UI — Main Frame

**Files:**
- Modify: `EZMacro/UI/MainFrame.lua`

- [ ] **Step 1: Implement the main panel**

```lua
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

    -- Import button at the top
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

    -- Spacer
    local spacer = AceGUI:Create("Heading")
    spacer:SetText("Imported Macros")
    spacer:SetFullWidth(true)
    scroll:AddChild(spacer)

    -- List each macro
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
    -- Row container
    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")

    -- Macro name label
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

    -- Bind Key button
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

    -- Delete button
    local deleteBtn = AceGUI:Create("Button")
    deleteBtn:SetText("Delete")
    deleteBtn:SetWidth(70)
    deleteBtn:SetCallback("OnClick", function()
        if InCombatLockdown() then
            EZMacro:Print("Cannot delete during combat.")
            return
        end
        EZMacro:DeleteMacro(name)
        EZMacro:ShowMainFrame()  -- Refresh
    end)
    row:AddChild(deleteBtn)

    parent:AddChild(row)

    -- Warnings row (if any)
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
```

- [ ] **Step 2: Commit**

```bash
git add EZMacro/UI/MainFrame.lua
git commit -m "feat: implement main panel UI with macro list and action buttons"
```

- [ ] **Step 3: Verify in-game**

`/ezm` should open the main panel. If no macros imported, shows empty state. If macros exist, shows name/keybind/warnings with Bind Key and Delete buttons.

---

## Task 7: UI — Import Dialog

**Files:**
- Modify: `EZMacro/UI/ImportDialog.lua`

- [ ] **Step 1: Implement the import dialog**

```lua
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
            EZMacro:Print("Nothing to import — paste a GSE string first.")
            return
        end

        local ok, msg = EZMacro:ImportString(strtrim(text))
        if ok then
            EZMacro:Print("|cFF00FF00" .. msg .. "|r")
            -- Create buttons for newly imported macros
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
```

- [ ] **Step 2: Commit**

```bash
git add EZMacro/UI/ImportDialog.lua
git commit -m "feat: implement GSE string import dialog"
```

- [ ] **Step 3: Verify in-game**

`/ezm import` opens the paste dialog. Paste a real GSE string, click Import. Should see success message and macro appears in main panel.

---

## Task 8: UI — Key Bind Dialog

**Files:**
- Modify: `EZMacro/UI/KeyBindDialog.lua`

- [ ] **Step 1: Implement the keybind capture dialog**

```lua
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

    -- Keybind widget
    local keybind = AceGUI:Create("Keybinding")
    keybind:SetLabel("Press a key")
    keybind:SetFullWidth(true)
    keybind:SetCallback("OnKeyChanged", function(widget, event, key)
        if not key or key == "" then return end
        if not pendingMacro then return end

        -- Check if this key is already bound to something
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

    -- Unbind button (if already bound)
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
```

- [ ] **Step 2: Commit**

```bash
git add EZMacro/UI/KeyBindDialog.lua
git commit -m "feat: implement key bind capture dialog with unbind support"
```

- [ ] **Step 3: Verify in-game**

From main panel, click "Bind Key" on an imported macro. Press a key. Verify the keybind shows in the macro list. `/reload` and verify the keybind persists and works in combat.

---

## Task 9: Integration Testing and Polish

**Files:**
- Potentially modify any file for bug fixes

- [ ] **Step 1: Full end-to-end test**

Test the complete flow in-game:
1. `/ezm` → opens main panel (empty state)
2. Click "Import GSE Macro" → paste a real GSE string → Import
3. Macro appears in list with class/spell warnings
4. Click "Bind Key" → press F5 (or any key)
5. Close panel, enter combat, press F5 → verify macro executes
6. Exit combat, `/ezm` → verify macro shows [F5] binding
7. `/reload` → verify macro and binding persist
8. Log on an alt → verify different character has no macros

- [ ] **Step 2: Test edge cases**

1. Import the same macro again → should update (not duplicate)
2. Import an invalid string → should show error message
3. Import a macro for a different class → should import with warning
4. Try to bind/import during combat → should show "after combat" message
5. `/ezm reset` → confirm dialog → all macros cleared

- [ ] **Step 3: Fix any issues found**

Address bugs discovered during testing. Common issues:
- WrapScript attribute parsing errors
- Step advancement off-by-one
- Keybind not restoring after `/reload`
- Combat lockdown taint errors

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "fix: integration testing fixes and polish"
```

---

## Verification Checklist

After all tasks are complete, verify:

- [ ] Addon loads without errors on login
- [ ] `/ezm` opens and closes the main panel
- [ ] GSE string import works for single macros and collections
- [ ] Talent/spell warnings display correctly
- [ ] Key binding works and persists across `/reload`
- [ ] Macro executes in combat when bound key is pressed
- [ ] Per-character storage works (different macros per alt)
- [ ] Combat lockdown prevents unsafe operations
- [ ] Delete and reset work correctly
