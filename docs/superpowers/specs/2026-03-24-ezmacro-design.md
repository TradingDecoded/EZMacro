# EZMacro Design Spec

## Problem

GSE (GnomeSequencer-Enhanced) is powerful but complex. Non-technical WoW players just want to paste a macro string, bind it to a key, and play. EZMacro strips away the editor, transmission, recording, and configuration overhead to deliver exactly that.

## Target

- Retail WoW only (TWW/Midnight, Interface 120001+)
- Uses modern `C_EncodingUtil` API for GSE string decoding
- Ace3 framework for addon structure and UI

## Features

### 1. Import GSE Macro Strings

Users paste a `!GSE3!`-prefixed string. EZMacro decodes it using the same pipeline GSE uses:

```
!GSE3! prefix → string.sub(data, 6) → DecodeBase64 → DecompressString → DeserializeCBOR → Lua table
```

Note: The prefix strip starts at position 6 (the trailing `!`), matching GSE's `string.sub(data, 6, #data)`.

**Decoded formats:**

- **Single sequence:** Decoded table is `{sequenceName, sequenceTable}`. Store directly.
- **Collection:** Decoded table has `type == "COLLECTION"` with `payload` containing:
  - `payload.Sequences` — table of `name → sequence` pairs
  - `payload.Variables` — table of `name → variable` pairs (stored but not used in v1)
  - `payload.Macros` — table of `name → macro` pairs
  - `payload.ElementCount` — total count

On collection import, all sequences in the collection are imported. Variables and Macros sub-tables are stored for future use.

**Import flow:**
1. `/ezm` opens main panel
2. Click "Import" → paste dialog appears
3. Paste GSE string → decode → validate → store
4. Macro appears in the main panel list

### 2. Talent/Spell Validation

After import and on `PLAYER_TALENT_UPDATE` events, EZMacro scans each macro's compiled action list for spell references.

**Spell resolution:** Macro actions reference spells by name (localized strings). Use `C_Spell.GetSpellInfo(spellName)` to resolve name → spellID, then `IsSpellKnown(spellID)` or `IsPlayerSpell(spellID)` to check availability.

**Warnings shown for:**
- Spells the player doesn't know (missing talent or wrong spec)
- Class mismatch (warrior macro imported on a mage, checked via `GetClassID()` vs stored `classID`)

Warnings appear as orange text next to the macro in the main panel, and optionally as a chat message on login.

### 3. Key Binding

Simple "press a key" flow:

1. Select macro in main panel
2. Click "Bind Key"
3. Dialog captures next keypress
4. `SetBindingClick(key, buttonName, "LeftButton")` wires the key to the macro's secure button
5. Binding saved per-character in SavedVariables
6. On login (`PLAYER_ENTERING_WORLD`), `SetBindingClick` is re-called for each saved binding — WoW does not persist `SetBindingClick` across sessions

**Simplification:** Keybinds are per-character, not per-spec. One bind per macro regardless of specialization. This keeps the UX dead simple.

### 4. Macro Execution (Runtime)

Uses the same proven pattern as GSE:

1. **Button creation (out of combat only):**
   ```lua
   local btn = CreateFrame("Button", name, nil, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
   btn:RegisterForClicks("AnyUp", "AnyDown")
   btn:SetAttribute("type", "spell")
   btn:SetAttribute("step", 1)
   ```

2. **Version selection:** GSE sequences contain multiple `Versions` and a `MetaData` block that maps content contexts (Raid, Dungeon, PVP, Arena, Mythic+, Default) to version numbers. EZMacro v1 uses the `Default` version. If no Default is specified, use version 1.

3. **Sequence compilation:** Flatten the selected version's action blocks into a step table. Each action block can contain:
   - `spell` — `/cast SpellName` type actions
   - `macrotext` — raw macro text (multi-line `/cast`, `/use`, etc.)
   - Repeat counts — action repeated N times in the compiled table
   - Action types: `Action`, `Pause`, `Loop` (v1 supports Action and Pause; Loop deferred)

   Compiled result: `steps[n] = {type="spell"|"macrotext"|"macro", spell="X", macrotext="/cast X", unit="target", ...}`

4. **WrapScript OnClick (restricted Lua environment):**
   The WrapScript body runs in WoW's restricted secure environment — no access to addon globals, only `self`, `GetAttribute`, `SetAttribute`, `CallMethod`.

   ```
   Read step from self:GetAttribute("step")
   Load attributes from compiled step table
   Set attributes on self: type, spell/macrotext/macro, unit
   Clear conflicting attributes (e.g., clear macrotext when setting spell)
   Advance: step = step % totalSteps + 1
   self:SetAttribute("step", step)
   ```

5. **WoW handles casting:** The secure button's attributes trigger WoW's spell casting engine automatically after the OnClick handler completes.

## Combat Lockdown

`InCombatLockdown()` restricts all secure frame operations. EZMacro must:

- **Disable** Import, Bind Key, and Delete buttons when `InCombatLockdown()` is true
- **Re-enable** on `PLAYER_REGEN_ENABLED` (combat ends)
- **Queue** any operations attempted during combat and execute them when combat ends
- **Never** call `CreateFrame` for secure templates, `SetAttribute`, or `SetBindingClick` during combat

## Architecture

Single addon, no sub-modules:

```
EZMacro/
├── EZMacro.toc            # Addon metadata, file load order
├── Libs/                   # Ace3 subset
│   ├── LibStub/
│   ├── CallbackHandler-1.0/
│   ├── AceAddon-3.0/
│   ├── AceConsole-3.0/
│   ├── AceEvent-3.0/
│   ├── AceGUI-3.0/
│   └── AceTimer-3.0/
├── embeds.xml              # Library load manifest
├── Core/
│   ├── Init.lua            # AceAddon init, slash command /ezm, SavedVariables setup
│   ├── Decoder.lua         # GSE string decode (!GSE3! → Lua table), collection handling
│   └── Engine.lua          # SecureActionButton creation, step compilation, execution WrapScript, keybind wiring
├── UI/
│   ├── MainFrame.lua       # Main panel: macro list with status, Import/Bind/Delete buttons
│   ├── ImportDialog.lua    # Paste box + Import button
│   └── KeyBindDialog.lua   # "Press a key to bind" capture dialog
└── Validation/
    └── TalentCheck.lua     # Spell/talent validation against player's known abilities
```

## Data Model

```lua
-- SavedVariablesPerCharacter: EZMacro_CharDB
EZMacro_CharDB = {
    macros = {
        ["MacroName"] = {
            sequence = { ... },       -- Full decoded GSE sequence table (Versions, MetaData, etc.)
            classID = 1,              -- Class the macro was created for
            keybind = "F1",           -- Bound key (nil if unbound)
            source = "!GSE3!...",     -- Original import string for re-export
            warnings = {},            -- Populated by TalentCheck: list of {spell="X", reason="not known"}
        },
    },
}

-- SavedVariables: EZMacro_GlobalDB
EZMacro_GlobalDB = {
    options = {
        showWarningsInChat = true,    -- Print talent warnings to chat on login
    },
}
```

## Slash Commands

- `/ezm` — Toggle main panel
- `/ezm import` — Open import dialog directly
- `/ezm list` — Print imported macros to chat
- `/ezm reset` — Clear all macros for current character (with confirmation)

## Event Handling

| Event | Action |
|-------|--------|
| `ADDON_LOADED` | Initialize SavedVariables defaults, create secure buttons for stored macros |
| `PLAYER_ENTERING_WORLD` | Re-apply keybinds via `SetBindingClick`, run talent validation |
| `PLAYER_TALENT_UPDATE` | Re-run talent validation on all macros |
| `PLAYER_REGEN_ENABLED` | Re-enable UI buttons, flush any queued operations |
| `PLAYER_REGEN_DISABLED` | Disable Import/Bind/Delete buttons |

## Key Technical Decisions

1. **No editor** — Import only. Users create macros in GSE or copy from community sites.
2. **Per-character storage** — Each character has independent macros and keybinds via `SavedVariablesPerCharacter`.
3. **Per-character keybinds (not per-spec)** — Simplifies UX. One bind per macro regardless of specialization.
4. **Default version only** — v1 always uses the Default version from GSE sequences. Context-aware version switching (Raid/Dungeon/PVP) deferred to future versions.
5. **Class mismatch warning** — Import is allowed cross-class but shows a warning, since some macros are class-agnostic.
6. **Store original string** — Keeping the source `!GSE3!` string allows re-export or sharing without data loss.
7. **Retail-only** — Simplifies the codebase by relying on `C_EncodingUtil` (not available in Classic).
8. **No AceDB** — Raw SavedVariables with manual defaults initialization. Keeps dependencies minimal.

## Testing Plan

Since WoW addons can't be unit-tested outside the client:

1. **Manual in-game testing:**
   - Import a known GSE string → verify it decodes and appears in the panel
   - Bind to a key → verify the key triggers the macro in combat
   - Swap talents → verify warnings appear/disappear correctly
   - Log on an alt → verify different character sees different macros
   - Import a collection → verify all macros in the collection appear
   - Try importing/binding during combat → verify operations are blocked/queued

2. **Edge cases:**
   - Import the same macro twice (should update, not duplicate)
   - Import invalid/corrupted string (should show error, not crash)
   - Bind a key already bound to something else (should warn and override)
   - Import a macro for a different class (should import with warning)
   - Relog and verify keybinds are restored correctly
