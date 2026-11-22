# The station set and load order

A station is a live object in a container. The engine builds it once, while the audio metadata
loads, from three things that must all be there at that moment. Two of the three plays nothing. One
combination kills every radio in the game. Anything that arrives after that moment is ignored, and
no log says so.

## What a station needs

| | Where it lives | Who supplies it |
| --- | --- | --- |
| **Identity** | its `CName` in the compiled roster ([roster page](compiled-station-roster.md)) | the plugin, at load |
| **Membership** | its name in `audioRadioStationMetadataMap.radioStations`, an `array:CName` in `cooked_metadata.audio_metadata` | script, as that resource loads |
| **Content** | an `audioRadioStationMetadata` entry: `name`, `tracks` (event `CName`s), `speaker`, `blips` | script, as that resource loads |

The shipped map `radio_stations_config` names seventeen stations. **For positions 0 to 9, a
station's position in that array is its UI index.** `RadioStation.MinimTech` carries `index: 5`, and
`radioStations[5]` is `radio_station_06_minim_techno`. Police and kurtz sit at 14 and 15 and have no
`RadioStation` record. HKGN (`radio_station_15_edgerunners`) is last, at 16. Its UI index is 10
(`RadioStation.HKGN` carries `index: 10`). From 10 up, the array and the UI order differ.

## What kills every radio

`[M]` Nine variants against a working baseline on 2.31, each changing one thing:

| Map change | Metadata entry | Route | Radios |
| --- | --- | --- | --- |
| none | none | - | work |
| none | added | script | work |
| append a name | none | archive | work |
| replace slot 15 (kurtz) | none | archive | work |
| replace slot 5 with a name the engine knows | - | archive | work, the displaced station silent |
| append a name | **added** | archive + script | **dead** |
| replace slot 15 | **added** | archive + script | **dead** |
| replace slot 5, new identity | added | archive + script | **dead** |
| any write to `radioStations` from script | - | script | **dead** (before the roster patch) |

**How it fails.** The engine walks `radioStations` and looks up each name among the metadata
entries. A name with no entry is skipped and costs nothing. A name **with** an entry is a station to
build, and building fails for an identity that is not in the compiled roster. That failure takes
down the whole radio system, the Radioport and world devices alike, and nothing reports it. **Half a
station is ignored. A whole one is fatal.** Extend the roster first and the same combination works.

`[M]` `GetRadioStationCurrentTrackName(CName)` reads a container off a global singleton at
`0x3bbfb38` (`0x342ac00` on 2.31) and returns the `NoneTrack` CName when the lookup misses. A station is an object in that
container, not a row in a table. Every station runs all the time on one clock, so a real station
answers whether or not a receiver is tuned to it.

## The window is the resource load

`[M]` **Membership and the entry must be in place while `cooked_metadata.audio_metadata` is
loading.** Register them a few seconds later and the data is there, every log line reads as
success, and the station is silent on every receiver:

```
19:28:22  registered radio_station_20_tool: 11 track(s)   -> plays on all three receivers
20:14:15  registered radio_station_20_tool: 11 track(s)   -> silent on all three
```

Same code, same data. Only the timing changed.

`Resource/Load` (Codeware's callback system) fires while a resource is loading, before the engine
reads it, and that is the window. It does not fire for a resource another mod already pulled in,
so the framework also asks the depot for a token and makes every write safe to run twice.

The same goes for `eventsmetadata.json`. An event needs a row there to be posted by name, and the
station schedules the next track against that row's `minDuration`/`maxDuration`. `[I]` The engine
reads those durations when it builds the station, not at play time. A station built while its rows
were missing picked a random track on every tune-in, even though the rows had arrived, with the
right durations, minutes before anyone listened.

## Durations, and where they can come from

`[M]` **A station built against zero durations picks a random track each time it is selected.**
With real durations it picks the track the world clock says. Vanilla trims one to eight seconds off
several tracks and declares the trimmed length. A declared length longer than the audible one makes
the station wait out the silence.

**AudioXL cannot supply the length in time.** Its `Duration()` is frames over sample rate, read from
the engine's custom-sound row table. That row exists only once the engine's audio system has
started (AudioXL's `AudioInit` hook flushes a queue of registrations then) and the file has been
decoded. Both happen seconds after the metadata loads. So:

| Register early | Register late |
| --- | --- |
| the station plays | the station is never constructed |
| durations are 0, random track each time | durations right, nothing plays |

The framework reads the length from the audio file's own headers at plugin load instead
(`plugin/src/Duration.hpp`), before any script runs:

| Format | Read |
| --- | --- |
| MP3 | ID3v2 skipped; the Xing/Info or VBRI frame count when present, else a walk of every frame header |
| FLAC | STREAMINFO total samples over sample rate |
| Ogg Vorbis | identification header rate, last page's granule position |
| WAV | `data` chunk size over `fmt` byte rate |

`[M]` Checked against ffprobe on eleven album tracks and six synthetic files: every MP3 within one
frame (26 ms), FLAC, Ogg and WAV exact, eleven files in 70 ms. A track whose length cannot be read
is dropped at manifest load and named in the log. It is never registered against zero.

## Order of operations, as shipped

```
plugin load      identity (roster), label key (name table), every track's length
eventsmetadata   one row per track, with that length            <- while it loads
cooked_metadata  membership, the station entry, a title row per track   <- while it loads
onscreens        the station name and every title              <- while it loads
TweakDB apply    RadioStation and UIIcon records
whenever ready   AudioXL registration of each file
```

Only the last step can wait. The engine finds the sound at play time, so a row that turns up
seconds later still plays. A station that turns up seconds later never exists.

## Other things measured on the way

- `speaker` is `audioRadioSpeakerType`: Stanley 0, MaximumMike 1, PoliceDispatch 2, Kurtz 3, Ash 4,
  None 5. Thirteen vanilla stations are Stanley. **`None` plays**: a station ran with no DJ for the
  whole of development. The manifest's `news` picks between `Stanley` and `None`.
- `radio_station` and `radio_port_station` are **not Wwise switch groups**. Neither is in
  `init.bnk`'s `STMG` chunk, and no object in the radio banks refers to their ids. The game's own
  audio layer handles both, through one handler at `0x442358` (`audio::RadioEmitter::HandleSwitchLogic`).
  It calls the roster resolver
  and parks the requested station at `+0x110` of a state object with a dirty flag.
- **A traffic car picks its station from its own vehicle metadata's
  `matchingStartupRadioStations`** (`audio::TrafficVehicleEmitter::PlayRadio` through the span form of
  `audio::RadioSystem::GetRandomStation`, `0x4407e0`), and never picks a station missing from that
  list. No vanilla list names a custom station. `Traffic.reds` adds them, behind a setting. The game
  keeps a station silent when its only listeners are traffic cars (the radio mode 1 gate), so a
  traffic radio is tuned but not heard. Measured.
- **A world radio or jukebox set to randomise picks in script**, through
  `RadioStationDataProvider.GetRandomStation` (the fifteen less Samizdat), which `Traffic.reds`
  wraps. The native world-device form (`0x2750310`) is reached only on the value `station_random`,
  and no vanilla radio sends it. Measured for jukeboxes.
- **`RequestSongOnRadioStation(CName station, CName song)`** on the audio system works from script.
  It forces a registered song onto a named station on demand.
- `audioPlaylistEmitterMetadata` / `audioPlaylistMetadata` (157 and 53 entries) are a second audio
  path, for world emitters with numbered broadcast channels: clubs, markets, the Phantom Liberty
  hangout. A world device radio does not use it. It goes through the roster, like the Radioport.
