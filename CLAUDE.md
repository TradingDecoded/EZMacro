# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EZMacro is a World of Warcraft addon that aims to be a simplified alternative to GSE (GnomeSequencer-Enhanced). The goal is to let normal, non-technical players:

1. **Import GSE macro strings** — parse and use existing GSE-format macro sequences
2. **Import WoW talent builds** — load talent build strings
3. **Bind to a key** — simple one-click key binding for imported macros

The full GSE addon source (v3.3.08 by TimothyLuke) is included under `old-addon/` as a reference implementation.

## WoW Addon Development

- **Language:** Lua (WoW uses Lua 5.1)
- **Entry point:** `.toc` files define addon metadata, dependencies, and file load order
- **Saved data:** `SavedVariables` in TOC persist data between sessions (stored by WoW client)
- **UI framework:** XML-defined frames or Lua-created frames; WoW provides its own widget API
- **No external build tools** — WoW loads addons directly from the `Interface/AddOns/` directory

## GSE Reference Architecture (`old-addon/`)

GSE is split into 5 addon modules that load via dependency chain:

| Module | Purpose | Load |
|--------|---------|------|
| `GSE/` | Core API — init, storage, serialization, events, string/character functions | Always |
| `GSE_GUI/` | Editor UI — import/export, macro editor, keybind editor, recorder | On demand |
| `GSE_Utils/` | Utilities — minimap icon, shared media, tracker, popups | Always |
| `GSE_Options/` | Settings panel | Depends on GSE_Utils |
| `GSE_LDB/` | LibDataBroker minimap feed | Depends on GSE + GSE_Utils |

### Key GSE internals

- **Ace3 framework** — AceAddon, AceConsole, AceGUI, AceEvent, AceComm, AceTimer, AceLocale via LibStub
- **Serialization format:** `!GSE3!` + Base64(Compress(CBOR(lua_table))) using `C_EncodingUtil` (WoW 11.x+ API)
- **Decode flow:** strip `!GSE3!` prefix → DecodeBase64 → DecompressString → DeserializeCBOR → Lua table
- **Storage:** Sequences stored compressed in `GSESequences[classID][name]`, lazily decompressed into `GSE.Library[classID][name]`
- **Import flow:** paste string → `GSE.DecodeMessage()` → if type is `COLLECTION`, show checkboxes for sequences/variables/macros → `GSE.ImportSerialisedSequence()`
- **Macro execution:** GSE creates WoW macro buttons that cycle through spell sequences on each keypress

### Key files for understanding import/export

- `GSE/API/Serialisation.lua` — `EncodeMessage()` / `DecodeMessage()` encode/decode protocol
- `GSE/API/Storage.lua` — sequence storage, lazy loading, migration
- `GSE_GUI/Import.lua` — import UI and collection processing
- `GSE_GUI/Export.lua` — export UI
- `GSE/API/Events.lua` — WoW event handling and macro button creation

### Supported WoW versions

Interface: 11508 (Classic), 20505 (SoD), 50503 (WoD), 120001 (TWW/Midnight)
