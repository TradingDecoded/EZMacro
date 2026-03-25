# Talent Build Import & EZM Export Format

**Date:** 2026-03-24
**Status:** Approved

## Summary

Add talent build import/export to EZMacro. A new `!EZM!` string format bundles compiled macro steps and a WoW talent loadout string into a single shareable string. Users import one string to get both the macro and the talent build, bind a key, click "Load Build" to apply talents, and they're done.

## 1. `!EZM!` Format

**Encoding pipeline:** `!EZM!` + Base64(Compress(CBOR(payload)))
Uses `C_EncodingUtil` — same APIs used for GSE decoding, now in both directions.

**Payload:**
```lua
{
    formatVersion = 1,
    name = "Fury ST",
    classID = 1,
    specID = 72,                    -- WoW spec ID (e.g., 72 = Fury Warrior)
    talentLoadout = "CkEAA...",     -- WoW talent export string
    steps = {
        {type = "macro", macrotext = "/cast Rampage"},
        {type = "macro", macrotext = "/cast Bloodthirst"},
    }
}
```

Stores compiled steps (not raw GSE sequence data). Keeps the format simple and decoupled from GSE internals.

**Import auto-detection** in ImportDialog:
- `!GSE3!` prefix → GSE import (no talents)
- `!EZM!` prefix → EZMacro import (macro + talents)
- `{` prefix → raw Lua table (no talents)

## 2. Storage

One new field on `EZMacro_CharDB.macros[name]`:

```lua
{
    sequence = { ... },          -- existing (GSE imports)
    compiledSteps = { ... },     -- existing (raw Lua / EZM imports)
    classID = 1,                 -- existing
    keybind = "F1",              -- existing
    source = "!EZM!...",         -- existing (original import string)
    warnings = {},               -- existing
    talentLoadout = "CkEAA...",  -- NEW (nil if none)
}
```

No migration needed. Existing macros without `talentLoadout` simply won't show the Load Build button.

## 3. UI Changes

### Button widths
Widen all macro row buttons to fix "Bind Key" text cutoff. Window has plenty of room.

### Macro row layout
```
[Macro Name] [F1]     [Load Build] [Export] [Bind Key] [Delete]
```

### Load Build button
- Only visible when `talentLoadout` is present on the macro.
- Opens the WoW talent UI with the build pre-filled for player to confirm/apply. Exact API to be verified against live WoW client (`C_ClassTalents.ImportLoadout` or `ClassTalentFrame` equivalent).
- Uses `InCombatLockdown()` check-and-print pattern (same as Bind Key / Delete buttons).
- Class/spec mismatch: if macro's `classID` or `specID` doesn't match the player, show a warning in chat but still allow the action (the WoW talent UI will reject incompatible builds anyway).

### Export button
- Encodes macro's compiled steps + `talentLoadout` into `!EZM!` string.
- If no `talentLoadout` stored on the macro, captures player's current talent build via `GetLoadoutExportString()` (loading `Blizzard_PlayerSpells` first if needed, calling `UpdateTreeInfo()` before export). If capture fails (nil/empty/no talents), export without `talentLoadout` and print warning.
- Shows an export dialog with a pre-selected editbox containing the `!EZM!` string (WoW has no clipboard API — user does Ctrl+C from the editbox). Chat message confirms: "EZMacro: [name] ready to copy."

## 4. Addon Compartment Registration

Register EZMacro with WoW's addon compartment (minimap dropdown):

**TOC addition:**
```
## AddonCompartmentFunc: EZMacro_OnAddonCompartmentClick
```

**Init.lua:** Add global `EZMacro_OnAddonCompartmentClick` function that toggles the main frame.

## 5. Encoding (New)

New file `Core/Encoder.lua` — add to `EZMacro.toc` after `Core\Decoder.lua`.

- `EZMacro:EncodeEZMString(name)` — takes a macro name, builds the payload table, serializes via CBOR → Compress → Base64, prepends `!EZM!`.
- `EZMacro:CaptureCurrentTalents()` — loads `Blizzard_PlayerSpells` addon if needed, calls `UpdateTreeInfo()` then `GetLoadoutExportString()`, returns the talent string. Returns nil if capture fails.

## 6. Decoding Changes

`Core/Decoder.lua` gains:

- `EZMacro:DecodeEZMString(text)` — strips `!EZM!` prefix via `text:sub(6)`, Base64 → Decompress → CBOR deserialize. If `formatVersion > 1`, error: "This macro requires a newer version of EZMacro. Please update." Returns payload.
- `EZMacro:ImportEZMString(text)` — calls `DecodeEZMString`, stores in `EZMacro_CharDB.macros[name]` with `compiledSteps`, `talentLoadout`, `classID`, `specID`, `source`. Preserves existing keybind if re-importing same name (matching GSE import behavior). Warns on class mismatch but still imports.

## Backwards Compatibility

- Existing `!GSE3!` and raw Lua table imports continue to work unchanged.
- Macros without `talentLoadout` behave exactly as before (no Load Build button shown).
- No SavedVariables migration required.
