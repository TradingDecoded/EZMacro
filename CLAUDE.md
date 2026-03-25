# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EZMacro is a World of Warcraft addon — a simplified alternative to GSE (GnomeSequencer-Enhanced). It lets players:

1. **Import GSE macro strings** (`!GSE3!` encoded), **raw Lua step tables**, or **EZMacro strings** (`!EZM!` encoded — bundles macro + talent loadout)
2. **Validate talents** — warns when imported macros reference spells the player doesn't know
3. **Bind to a key** — simple one-click key binding with persistence across sessions
4. **Load talent builds** — import talent loadout strings and pre-fill the WoW talent UI
5. **Export macros** — encode macro + talents into a single `!EZM!` string for sharing

**GitHub:** https://github.com/TradingDecoded/EZMacro
**Target:** Retail WoW only (Interface 120001+, TWW/Midnight)

## EZMacro Architecture

Single addon, Ace3 framework (AceAddon, AceConsole, AceEvent, AceGUI, AceTimer).

```
EZMacro/
├── EZMacro.toc            # Addon descriptor, Interface 120001
├── embeds.xml             # Ace3 library load manifest
├── Libs/                  # Ace3 subset (LibStub, CallbackHandler, AceAddon/Console/Event/GUI/Timer)
├── Core/
│   ├── Init.lua           # AceAddon bootstrap, slash commands (/ezm), event wiring, combat lockdown, addon compartment
│   ├── Decoder.lua        # GSE/EZM string decode (C_EncodingUtil) + raw Lua table import (loadstring sandboxed)
│   ├── Encoder.lua        # EZM string encoding (CBOR/Compress/Base64) + talent loadout capture
│   └── Engine.lua         # SecureActionButton creation, step compilation, WrapScript execution, keybinds
├── UI/
│   ├── MainFrame.lua      # Main panel: macro list with Load Build/Export/Bind/Delete buttons
│   ├── ImportDialog.lua   # Paste box with auto-detect (EZM, GSE string, or Lua table)
│   ├── KeyBindDialog.lua  # AceGUI Keybinding widget capture dialog
│   └── ExportDialog.lua   # Copyable editbox showing encoded !EZM! string for sharing
└── Validation/
    └── TalentCheck.lua    # Spell extraction from steps, IsSpellKnown/IsPlayerSpell checks
```

### Data flow

1. **Import:** Paste `!EZM!` string, `!GSE3!` string, or Lua step table → Decoder parses → stored in `EZMacro_CharDB.macros[name]`
   - `!EZM!` imports include talent loadout string (stored in `talentLoadout` field)
2. **Compile:** Engine selects Default version from GSE sequence → flattens actions to step table `{type="macro", macrotext="..."}`
   - Raw Lua imports skip compilation (already in step format, stored as `compiledSteps`)
3. **Execute:** SecureActionButton with WrapScript OnClick cycles through steps on each keypress
4. **Bind:** `SetBindingClick(key, buttonName, "LeftButton")` — re-applied on every login via PLAYER_ENTERING_WORLD
5. **Export:** Encoder captures talent loadout + compiled steps → CBOR serialize → Compress → Base64 → `!EZM!` prefix

### SavedVariables

- `EZMacro_GlobalDB` (global) — addon options
- `EZMacro_CharDB` (per-character) — imported macros, keybinds, warnings

### Critical: Restricted Environment Rules

The SecureActionButton WrapScript runs in WoW's restricted Lua sandbox:
- Variables in `Execute()` must NOT be `local` — use globals so WrapScript can access them
- `WrapScript` stacks (doesn't replace) — only call once on button creation
- Valid button types: `spell`, `item`, `macro`, `action`, `click` — use `type="macro"` with `macrotext`
- Use long-bracket strings `[=======[...]=======]` for embedding macro text in Execute() code
- `newtable()` and `pairs()` are available in the restricted environment

## GSE Reference (`old-addon/`)

The full GSE addon source (v3.3.08) is in `old-addon/` for reference (gitignored).

- **Serialization:** `!GSE3!` + Base64(Compress(CBOR(table))) via `C_EncodingUtil`
- **EZMacro format:** `!EZM!` + Base64(Compress(CBOR(payload))) — same pipeline, bundles macro steps + talent loadout
- **Key files:** `GSE/API/Serialisation.lua` (encode/decode), `GSE/API/Storage.lua` (compilation, buttons, WrapScript)

## Development

- **Language:** Lua 5.1 (WoW runtime)
- **No build tools** — copy `EZMacro/` to WoW's `Interface/AddOns/` and `/reload`
- **No unit tests** — WoW addons require the live client for testing
- **Slash commands:** `/ezm` (toggle UI), `/ezm import`, `/ezm list`, `/ezm reset`
