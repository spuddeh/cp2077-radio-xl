# Labels are localization keys

Every label the game shows for a station is a key, never text. The UI resolves it. The engine's
name table holds one per station, `audioRadioTrack` holds one per track, and the script providers
return one per channel. Put text where the game expects a key and the label vanishes, and the
vehicle popup's selection matches nothing.

## Where the keys are

| Place | Holds | Resolved by |
| --- | --- | --- |
| the compiled name table, slot per station | `Gameplay-Devices-Radio-RadioStation*` | the native `GetRadioReceiverStationName` returns it as a `CName`; the dashboard does `SetText(NameToString(name))` and the widget resolves the string, the popup calls `GetLocalizedTextByKey` |
| `audioRadioTrack.localizationKey` / `primaryLocKey` | the track title key, and its numeric hash | the popup and dashboard, by the numeric key |
| `RadioStationDataProvider.GetChannelName` (script) | the same station key, as a `String` | device UI, `GetLocalizedText` |
| `RadioStation.<x>.displayName` (TweakDB) | `LocKey#<n>` | the station selection UI, `GetLocalizedText` |

`[M]` The vehicle popup marks the playing station by comparing `GetLocalizedText(record.DisplayName())`
with `GetLocalizedTextByKey(receiverStationName)`. Both sides have to resolve to the same text.

The framework makes one key per station (`Gameplay-Devices-Radio-RadioXL-<name>`) and one per title
(`Gameplay-Devices-Radio_tracks-RadioXL-<name>-<id>`, where `<id>` is the track's identity from its file). It puts the station key in the name table and the
title key in the track row, and registers the text against them. A manifest never sees a key.

## A key resolves by string only inside the game's three namespaces

`[M]` on 2.31, then read again in the 2.5 `Cyberpunk2077.exe`. `OnScreensRepositoryBase::Load`
(RVA `0x65619c`) loads each onscreens resource, then walks every entry of the loaded list (0x68
bytes each) and calls a register-entry function at `0x6562c8`. That function fills two maps on the
repository:

| Map | Keyed by | Filled from |
| --- | --- | --- |
| `+0x38` | `primaryKey` | every entry |
| `+0x08` | FNV1a64 of the `secondaryKey` text | every entry with a secondary key |

On 2.31 the load is `LoadTexts` (RED4ext hash `3550098299`, RVA `0x261018`), which only loads the
resource and returns its root. Its one caller, at `0x58dd6c`, does the walk, the register-entry
function is at `0x58ddf0`, and the second map sits at `+0x40` on the localization manager.

**Before hashing, a secondary key that starts with `ui-`, `gameplay-` or `common-` (compared
case-insensitively, the literals at `0x306a5b4`) is UPPERCASED (`0x656ff0`, an ASCII `a-z` loop).
A key outside those namespaces is hashed as written.** The string lookups (`GetLocalizedText`,
`inkText.SetText`, `SetLocalizedTextString`) uppercase what they are asked for, so a key outside the
three namespaces never matches. `GetLocalizedTextByKey(CName)` goes by the CName hash and does
not care. So a title, looked up by hash, resolves, and a station name looked up by string echoes
its key. It is also why an ArchiveXL key starting `Gameplay-` resolves from the console while `RadioXL-Station-...`
does not.

The walk runs after the resource has loaded, so rows added by an after-hook (ArchiveXL, Codeware) and
rows inserted while the resource loads all get indexed. The namespace is the only gate.

## Two rows per string

`localizationPersistenceOnScreenEntries.entries` in `base\localization\<lang>\onscreens\onscreens.json`
is sorted by `primaryKey` on disk, and ArchiveXL's merge keeps it sorted with a `lower_bound`.
`[M]` The engine does not need the order: the register walk above visits every row wherever it
sits. We once read an appended row as unreachable. That came from the namespace gate, not from
where the row sat.

A string is registered as two rows, the same as ArchiveXL does:

| Row | `primaryKey` | `secondaryKey` |
| --- | --- | --- |
| 32-bit | `FNV1a32(key)` | the key text |
| 64-bit | `FNV1a64(key)` | empty |

**A `primaryKey` of 0 is indexed by nothing.** ArchiveXL fills it from the secondary key, and a mod
that writes rows itself has to do the same.

`audioRadioTrack.primaryLocKey` is a `Uint64`. Vanilla rows carry small numeric keys, and ArchiveXL
uses the 64-bit hash. The framework writes the 32-bit hash there, and it resolves because the
32-bit row exists. It differs from vanilla, but it is not a fault.

**For the other two resources, appending is correct.** `eventsmetadata`'s event array and
`cooked_metadata`'s entry list are scanned in order. Patching a resource at load is not one
technique. Find out how the game looks up a row in that list before you decide where to put yours.

## What a failed lookup looks like

`[M]` A failed lookup fails in more than one way, and each one points you at the wrong cause:

- **A widget handed a key that resolves to nothing keeps its previous text.** It does not go blank. So a
  world device shows the *previous* station's name, which looks like a refresh-order bug.
- **`inkText.SetText` and `GetLocalizedText` hand back the string they were given when it is not a
  key they know.** So the in-car stereo prints the key.
- **`GetLocalizedTextByKey(CName)` returns an empty string for a CName it cannot resolve**, and that
  includes a `LocKey#<n>` form, which it does not parse.

## Why no label is wrapped

Five UI wrappers were written to swap in a station's name at the widget. They were deleted once the
name table was found. A wrong label means a table that was not extended, and that holds in general:
look for another 15-slot array before you write a script wrapper to fix the output. The only
wrappers left are on `RadioStationDataProvider` and `VehiclesManagerDataHelper`. Those are game
redscript that hold the fifteen vanilla stations as literals with nothing behind them.
