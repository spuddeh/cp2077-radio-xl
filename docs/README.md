# Documentation

**For mod authors:** [the script API](script-api.md) covers reading RadioXL's stations and songs,
changing what plays, and listening to its events, from redscript or CET.

Everything else in this folder is engine measurements.

## Engine measurements

These pages record what building the framework showed about Cyberpunk 2077's radio system.
They are about the engine, not about this code, so they help anyone who extends the radio, RadioXL
included. The code proves the parts that work. These pages say why it is shaped the way it is,
and what is still unknown.

**Game build 2.5 (Steam), `Cyberpunk2077.exe`, 66,704,848 bytes.** Every address is an RVA. The plugin uses
none of them: it finds every site by hash, through the address database RED4ext ships. They are here
for reading.

Every claim carries one of two marks:

- `[M]` **measured**: seen in the binary, in a log, or heard in game.
- `[I]` **inferred**: the best reading of the evidence, not checked yet.

| Page | What it covers |
| --- | --- |
| [The compiled station roster](compiled-station-roster.md) | the two 15-slot tables, their readers, the resolver, the bounds, the three divide-by-fifteen sites, and the patch |
| [The station set and load order](station-set-and-load-order.md) | what a station needs, what kills every radio, the boot-time window, and where a duration has to come from |
| [Labels are localization keys](localization-keys.md) | the name table holds keys, a key resolves by string only in three namespaces, and the lookup that still misses |
| [The audio path](audio-path.md) | `mod_sfx_radio`, what AudioXL's renderer does and does not do, and the symptoms that follow from it |
| [The manifest and what is derived from it](manifest-and-derivation.md) | every value a station needs and where the framework gets it, so a manifest never has to carry one |

## Tools that produced these

- **RED4ext's address database**, `cyberpunk2077_addresses.json` beside the executable. It has one
  entry per address, with a hash the maintainers carry from one game build to the next. Every patched
  site is in it, and the roster arrays resolve as data symbols, so nothing is signature-scanned.
- **Static disassembly** of the executable, with no debugger. A station name is an FNV1a64 constant,
  so the roster turned up in a search for the hash of `radio_station_12_growl_fm`.
- **[cp2077-symbols](https://codeberg.org/bartmoss/cp2077-symbols)** gives the C++ name of a function
  or variable at an address. Its names come from matching candidates against both hashes in the
  address database, so a listed name is exact. About a quarter of functions have no name.
- **The RTTI dump** (NativeDB) for every class and enum named here.
- **SoundDB** (<https://sounddb.redmodding.org>) for what a Wwise event does.
- **AudioXL's source** (<https://github.com/DigitalVixenSWE/cp2077-audio-xl>) for what its renderer does.
- **A probe mod**: a `ScriptableService` with every write behind its own flag, so each game launch
  moved one variable. The nine-variant table on the station-set page came from it.
