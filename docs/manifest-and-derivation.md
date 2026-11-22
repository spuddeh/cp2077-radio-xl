# The manifest, and what is derived from it

A station mod ships a manifest, its audio files and at most an icon archive. Everything else a
station needs is derived from the manifest or read from the engine at load. No modder has to work
out a value the game already knows, and nothing in a manifest can disagree with a file.

## The manifest

```json
{
  "name": "radio_station_yourstation",
  "frequency": 104.9,
  "displayName": "Your Station",
  "icon": "yourstation",
  "atlas": "yourmod\\gui\\yourstation.inkatlas",
  "news": true,
  "tracks": [
    { "file": "audio/first.mp3", "title": "Artist - First Song" }
  ]
}
```

| Field | What it is |
| --- | --- |
| `name` | The station's `CName`. Letters, digits and underscores only, because it is also an event-name prefix and a TweakDB record id. It must be unique across every installed station mod. The first one found wins, and the log names the one that lost |
| `frequency` | A number from 10 to 999, required. The game has no field for a frequency, so this is the only place it is written. It decides where the station sits on the dial, in the vehicle list and in every receiver's next/previous order. Two stations on one frequency keep slot order, the game's own first, and the tie is logged |
| `displayName` | Plain text, required. Only the station's name. The game shows the label as `<frequency> <name>` (`Label` in `Manifest.hpp`, one decimal, two when written), so every station reads the same way. The manifest is refused when the name is empty or untidy (a space at an end, two in a row, a control character), contains the frequency, or starts or ends with a number that reads as a frequency. A band's own number (`30H!3 Radio`) passes |
| `news` | Optional, default `false`. `true` writes the station's `speaker` as `Stanley`, so Stanley's news and greetings can reach it under the engine's own rules. `false` writes `None`, which gets no announcements. No other speaker is offered, because Mike's lines name Morro Rock and Ash is tied to Growl FM by name. A `speaker` key is an unknown key, logged and ignored |
| `gain` | Optional level trim on the samples, 0 to 4 (`kMaxGain`), clamped. Above 1 it is safe only while the file's peak times the gain stays under full scale. AudioXL scales 16-bit samples without clamping, so a value past the top wraps. The builder checks that against the file. The plugin can't. Default 1, because the framework's `radioxl_radio` type cites a vanilla station's Broadcast Sends, so the level stages are vanilla's. Only when the routing bank fails to load and a station falls back to `mod_sfx_radio` is the gain multiplied by 0.56 (-5 dB). That keeps the hotter sends of that type inside the vanilla range (see `audio-path.md`). The gain is applied through AudioXL's `SetGain` once the row exists, because `RegisterSoundEx`'s gain never reaches the samples |
| `showFrequency` | Optional, default `true`. `false` makes the label the name alone. The frequency still places the station on the dial |
| `description` | Optional. One text for every language, or an object of language codes (`en-us`, `de-de`), each up to 1000 characters. It is there for other mods to read. RadioXL shows it nowhere |
| `extensions` | Optional object, one key per mod that reads it. Each value is handed to that mod as JSON text and never read here |
| `addUnlistedFiles` | Optional, default `false`. `true` keeps `tracks` in step with the folder at each load. Every WAV/MP3/OGG/FLAC under the folder that no track names is added (titled from its file name, gain 1). Every listed `file` that is gone is removed. `station.json` is rewritten in place, only when something changed and only when the new text reads back as a valid manifest (`Folder.hpp`, `SyncStationFolder` in `Main.cpp`). A stream station is left alone, and `ident` is never guessed |
| `icon` / `atlas` | Optional. An inkatlas part and the atlas holding it, or `icon` alone naming an existing `UIIcon.` record (no atlas, and no record of the station's own). A record that does not exist falls back to the glyph. The default is the RadioXL glyph, part `radioxl` in `radioxl\gui\radioxl_icons.inkatlas`, shipped in the framework's own `archive/pc/mod/RadioXL.archive` |
| `tracks[].file` | An audio file, relative to the manifest's folder: WAV, MP3, OGG, FLAC |
| `tracks[].url` | Instead of `file`, an `http://` or `https://` MP3 stream. A live stream has no length to read, so its schedule length is a fixed 3600 s (`kStreamDuration`). When AudioXL ends the voice, the engine posts the same slot again, which reconnects. A station with a `url` track has that track only, so it has no schedule to resume |
| `tracks[].title` | Optional plain text, shown as written in the Radioport's radio popup. A song with no title plays everywhere a titled one does, and its title shows blank. World radios and the car dashboard show no song title for any station. The order of `tracks` does not decide play order. The engine draws each pick at random from the tracks not yet played (`audio::RadioStation::SelectCurrentSong`, `0x672698`, confirmed in game on Body Heat and PHONKWAVE with no reordering) |
| `tracks[].gain` | Optional, 0 to 4, clamped, default 1. This track's own level, multiplied with the station's `gain` |
| `tracks[].ident` | Optional `true`. The track's event goes into the station entry's `blips` instead of `tracks`, with no `audioRadioTrack` row. It still gets an event row with its duration, and an AudioXL row. The engine plays one blip after every third song pick (a byte counter at station `+0x170`, `cmp 3` at `0x321418` in `audio::RadioStation::Update`). It cycles the blips in an order drawn when the station starts, adds the blip's event-table duration to the gap, and takes no song slot. A blip with no event-table row never times out and holds the station in state 5, so the row is required. Neither a custom nor a vanilla blip shows a title |

Manifests live at `red4ext/plugins/RadioXL/stations/<Mod>/station.json`, one folder per mod so
nothing is shared. Mod managers throw away empty directories, so `stations/` ships a README to
survive packaging.

## How the manifest is read

The manifest is the one file a station author writes by hand, so it is the one input that will be
malformed. `plugin/src/Json.hpp` is a strict reader of RFC 8259 JSON, plus a leading byte-order
mark. No comments, no trailing commas, no single quotes. A fault is reported as the line and column
of the first one, with a sentence saying what was expected. `plugin/src/Manifest.hpp` then checks
the tree field by field and logs every fault as `<Mod>/station.json:<line>: <what>`.

**A manifest with a fault is skipped whole.** A station that loads with one field missing looks like
a bug somewhere else. The log line is all the author needs.

| Refused | Logged and ignored |
| --- | --- |
| `name` missing, not a string, or holding a character outside `[A-Za-z0-9_]` | a key the framework does not know, at top level or in a track |
| `frequency` missing, not a number, or outside 10 to 999; `displayName` missing, empty, untidy, or carrying a frequency at either end or inside (checked last, so an earlier fault is the first logged) | |
| `tracks` missing, not an array, or empty; a track that is not an object or has no `file` | `gain` outside 0 to 4, clamped |
| a track with both `file` and `url`; a `url` not starting `http://` or `https://`; a `url` track beside any other track | |
| `ident` not a boolean; an `ident` on a `url` track; every track an ident | |
| `news`, `showFrequency` or `addUnlistedFiles` not a boolean | `atlas` with no `icon`; a `speaker` key |
| `description` not a string or an object, or a language's text not a string; `extensions` not an object | a `description` past 1000 characters; a `description` key that is not a language code |
| a track `gain` not a number; a `file` that is empty | a track `gain` outside 0 to 4, clamped |
| `gain` not a number; `icon` part name with no `atlas` | `atlas` beside an `icon` that is a record |

`plugin/tests/ManifestTests.cpp` holds one case per row and runs under `ctest`.

## Everything derived

| Value | Derived as | Why not in the manifest |
| --- | --- | --- |
| roster slot, `ERadioStationList` value | 26 + the order the manifest was found in (`kFirstCustomEnum`, one past Kurtz at 25, so the police scanner at 16 and Kurtz are skipped). The shard slot takes the value after the last manifest | it depends on which other station mods are installed |
| dial position | every station sorted by frequency, the fifteen in the game's own order, the shard slot last | the same reason. It is also what makes a car, a world device and the pocket radio agree |
| internal station id | slot + 8 | an engine bias, see the [roster page](compiled-station-roster.md) |
| track event name | `<name>_<id>`, where `<id>` is 8 hex digits of FNV-1a 32 over the track's `file` (forward slashes, ASCII lower case) or its `url` | a file name with a space or an accent must never reach an event name. A player's per-song settings are stored under it, so adding, removing or reordering files must not rename the other tracks. When two tracks in a station have one identity, the second is dropped and logged |
| Wwise id of the event | FNV-1 32-bit of the lowercased event name, from AudioXL | it follows from the name |
| track duration | read from the file's headers at plugin load and kept in `red4ext/plugins/RadioXL/cache.json`, keyed by the file's size and modified time, so an unchanged file is not read again. A missing or stale entry means the header is read | the file is the only thing that can be right (see [station set](station-set-and-load-order.md)) |
| station label key | `Gameplay-Devices-Radio-RadioXL-<name>` | the engine's name table holds a key, and a key only resolves by string under `Gameplay-`, `UI-` or `Common-` (see [localization](localization-keys.md)) |
| title key | `Gameplay-Devices-Radio_tracks-RadioXL-<name>-<id>` | `audioRadioTrack` holds a key, in the same namespace as vanilla track keys |
| both hashes of each key | FNV1a32 keeping the key text, FNV1a64 with it cleared | that is how `onscreens` rows are found (see [localization](localization-keys.md)) |
| `RadioStation` record | `RadioStation.RadioXL_<name>` with the composed label as `displayName`, `icon`, `index` = dial position | `index` is a UI index, not the enum. The popup hands `record.Index()` to `SendRadioEvent`, which converts it through `GetRadioStationByUIIndex`. Vanilla carries fixed numbers, 0 for 88.9 to 14 for 107.5, so **the fifteen vanilla records are rewritten to their new positions** whenever a custom station is installed. Otherwise two records share an index, both light up, and either one plays the station now at that position |
| `UIIcon` record | `UIIcon.RadioXL_<name>` with `atlasPartName`, `atlasResourcePath`, unless `icon` names a record | the selector and the device logo load the atlas and part from it |

`[M]` TweakDB records must be created from `ScriptableTweak.OnApply`, never from a
`ScriptableService`. Records written earlier do not survive TweakDB load, and the station then plays
but shows in no list.

## Cross-station guarantees

- **Slots never collide**, because one plugin assigns them in one pass.
- **Record ids never collide**, because they carry the station name.
- **Event names never collide**, because they carry the station name. AudioXL's registry is
  first-registered-wins by name across every mod, so a prefix on `name` is the one thing the modder
  has to do.
- **Nothing vanilla is replaced, and the one archive the framework ships holds only its own glyph.**
  Two station mods can't conflict on a file.

## The script side, and what it wraps

The plugin hands the manifest to redscript through registered natives, `RadioXL_Station*`. `[M]` A
native declared inside `module X` must be registered as `X.Name`. Registered bare, it fails script
validation with *Missing native global function*, and **that stops every redscript mod on the
machine from compiling**. Installing the `.reds` without the DLL does the same damage, so the two
always ship as one archive.

`RadioStationDataProvider` (station count, name, channel name, UI index both ways) and
`VehiclesManagerDataHelper.GetRadioStations` are game redscript that hold the fifteen as switch
bodies and a literal push, with no table behind them. They are wrapped with `@wrapMethod`. A custom
station's enum value and its UI index are different numbers: the enum starts at 26, and the UI index
is the dial position. The wraps read both from the plugin (`RadioXL_DialPosition`,
`RadioXL_DialStation`).

The three cycling functions (`GetNextStationTo`, `GetPreviousStationTo`,
`GetNextStationPocketRadio`) have `% 15` written in their bodies, so they are `@replaceMethod`.
Vanilla is asymmetric there, and the replacements keep that. Going forward, UI index 4 maps to 5.
Going back, 6 maps to 5. It is also why the framework can't run alongside RadioExt or RadioXL 0.1.0,
which replace the same functions.

`[M]` The vehicle radio list is in frequency order. Vanilla pushes No Station, then its fifteen in
dial order (88.9, 89.3, 89.7 …). So the list is the dial with one row in front, and a custom station
goes in at its dial position plus one. The cycling functions and the vehicle's native next-station
step read the same dial, so every receiver steps through the stations in one order. Vanilla's skip
of Samizdat Radio is kept, and tied to the station rather than its number.

`[M]` `RadioInkGameController.SetupStationLogo` (the world device) sets only the texture part, on a
widget that already has the vanilla atlas. A custom station needs both atlas and part.
`InkImageUtils.RequestSetImage` with the `UIIcon` record id supplies both. Whether that works is
still open ([#6](https://github.com/spuddeh/cp2077-radio-xl/issues/6)).

## Icon assets

`[M]` The vanilla station atlas is 1008x1184 (2.31), `TEXG_Generic_UI` / `TRF_TrueColor` /
`TCM_QualityColor`, with no mipchain and parts roughly 240 to 400 px wide.
`inkatlas.textureResolution` is an enum string (`UltraHD_3840_2160`), not a number. A station mod's
icon archive uses paths with no `base\` prefix (`yourmod\gui\yourstation.xbm`). WolvenKit warns
about this, and the warning is wrong for a UI asset that a TweakDB record references by depot path.
