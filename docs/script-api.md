# RadioXL script API

Read RadioXL's stations and songs, change what plays, and hear when things change, from redscript or
CET. Everything is on one class, `RadioXLAPI`, and ten events.

**Only `RadioXLAPI` and the events are a promise.** Every other class, function and native in
RadioXL is public because RadioXL needs it to be, and changes between releases without notice.

## Quick start

**Redscript**

```swift
import RadioXL.*

let titles: array<String>;
let tracks = RadioXLAPI.Tracks(n"radio_station_12_growl_fm");
for track in tracks {
  if RadioXLAPI.IsSongPlayable(track) {
    ArrayPush(titles, RadioXLAPI.TrackTitle(track));
  }
}
```

**CET (Lua)**

```lua
local API = RadioXL_RadioXLAPI
for _, track in ipairs(API.Tracks("radio_station_12_growl_fm")) do
  if API.IsSongPlayable(track) then print(API.TrackTitle(track)) end
end
```

In CET the class is `RadioXL_RadioXLAPI`. A Lua string works wherever a `CName` is asked for, and a
returned `CName` reads as text through `.value`.

## Four rules

1. **Stations and songs are named, never numbered.** A station is its CName
   (`radio_station_12_growl_fm`), a song its track event (`mus_radio_12_killshot`, or
   `radio_station_20_tool_3fa29c01` for a custom one, named from the track's file). A dial position moves when a station mod is added.
2. **Put a returned array into a `let` before `ArraySize`, `ArrayContains` or an index.** Redscript
   otherwise reads it from uninitialised memory, which can crash the game.
3. **Check `IsReady()`, or wait for `RadioXL/Ready`**, before reading. The station list is built
   when the first session is ready.
4. **Check `Version()`.** It goes up only when something here changes in a way that breaks a caller.
   It is `1`.

## Reading

### Stations

| Function | Returns |
| --- | --- |
| `Version()` | `Int32` |
| `IsReady()` | `Bool`, true once every station is read |
| `Stations()` | `array<CName>`, every station, vanilla and custom, in dial order |
| `StationName(station)` | `String`, the label the game shows, frequency first |
| `StationFrequency(station)` | `Float`, `-1` for an unknown station |
| `StationDialPosition(station)` | `Int32`, from 0. Moves when a station mod is added |
| `StationIcon(station)` | `TweakDBID` of the station's `UIIcon` record |
| `IsCustomStation(station)` | `Bool` |
| `RegisterStation(name)` | nothing. Kept so a RadioXL 0.1.0 station's script compiles; it logs the name and creates no station |
| `StationMod(station)` | `String`, the folder the station's manifest is installed in; `""` for vanilla |
| `StationHasNews(station)` | `Bool`, true for every vanilla station |
| `StationDescription(station)` | `String` in the player's language; `""` when none, which every vanilla station is |
| `StationExtension(station, mod)` | `String`, the JSON the station carries for your mod; `""` when none. See [Station data for your mod](#station-data-for-your-mod) |
| `IsStreamStation(station)` | `Bool` |
| `StreamState(station)` | `RadioXLStreamState`: `NotStream`, `Blocked` (AudioXL.ini does not allow http), `Connecting`, `Live`, `Failed` |

### Songs

| Function | Returns |
| --- | --- |
| `Tracks(station)` | `array<CName>`, the station's songs, idents left out. Includes songs a quest adds during play |
| `Idents(station)` | `array<CName>`, the station's idents, jingles and ads |
| `TrackTitle(track)` | `String` in the player's language; an untitled song answers its event name |
| `TrackLength(track)` | `Float` seconds. A vanilla song's is its schedule slot, a little under the recording |
| `TrackFile(track)` | `String`, a custom song's audio file, full path; `""` for vanilla songs and streams |
| `TrackGain(track)` | `Float`, the level RadioXL plays a custom song at; `1` for vanilla |
| `IsStreamingFriendly(track)` | `Bool`, the game's own Streamer Mode flag |

### The player's choices

| Function | Returns |
| --- | --- |
| `SongState(track)` | `RadioXLSongState`: `On`, `Off`, `StreamerOff` (hidden while Streamer Mode is on) |
| `IsSongPlayable(track)` | `Bool`, whether RadioXL would play it now. **Check this before playing a song of your own**: it is false for a song the player switched off |
| `MyStation()` | `CName`, `n"None"` when unset |
| `IsStationSkipped(station)` | `Bool`, whether the station keys step over it |
| `IdentsMuted()`, `NewsMuted()` | `Bool` |
| `SilencedBy()` | `array<CName>`, the restrictions silencing the Radioport now, by `PocketRadioRestrictions` member name such as `PhoneCall`. A restriction held only by situations the player switched off is not listed |

### Sound

The Sound tab and each station's equaliser. A preset is named by its file's `name`; `"Custom"` is the
global equaliser's nine custom bands.

| Function | Returns |
| --- | --- |
| `EqPresets()` | `array<String>`, every loaded preset, Flat first |
| `EqPreset()` | `String`, the global equaliser: a preset's name or `"Custom"` |
| `StationEqPreset(station)` | `String`, the station's own choice: a preset's name, `"Custom"` for its own bands, `""` when it follows the global equaliser |
| `StationEqBand(station, band)` | `Int32`, one of the station's own bands in dB, heard while it is on `"Custom"` |
| `SuggestedEqPreset(station)` | `String`, RadioXL's suggestion for one of the game's stations, `""` for none or when that preset is not loaded |
| `ActiveEqPreset()` | `String`, the preset the radio playing now uses: its station's own, else the global one |
| `EqBand(band)` | `Int32`, a custom band's gain in dB, -12 to 12. Bands 0 to 8 are 63, 125, 250, 500 Hz, 1, 2, 4, 8 and 16 kHz |
| `Processing()` | `RadioXLProcessing`: `Off`, `Broadcast` (every stage), `Custom` (each stage's own switch) |
| `ProcessingStage(stage)` | `Bool`, a `RadioXLProcessingStage` (`Agc`, `PeakCompressor`, `Limiter`) switch, used while `Processing()` is `Custom` |
| `Boost()` | `Int32`, dB above the game's own level, 0 to 12 |
| `RadioportLikeCar()` | `Bool`, the "Sound like a car radio" switch |

### Mute switches and traffic

Every mute switch defaults to true, the game's own behaviour.

| Function | Returns |
| --- | --- |
| `SituationMuted(situation)` | `Bool`, whether the radio is silenced in a `RadioXLSituation`, as the game does: `Calls`, `Scenes`, `DrivingScenes`, `Clubs`, `SafeAreas`, `Quests` |
| `MixMuted(mix)` | `Bool`, whether the radio is lowered or muted in a `RadioXLMix` part of the mix, as the game does: `CombatMusic`, `PoliceMusic`, `Voices`, `Megabuilding`, `Menus` |
| `TrafficStations()` | `RadioXLTrafficMode`: `Shared` (cars whose list holds the stations most cars share), `All`, `Off` |
| `RandomWorldRadios()` | `Bool`, whether a world radio or jukebox that starts at random may land on a custom station |
| `RandomStreams()` | `Bool`, whether that pick may land on a stream station |

### What is playing

| Function | Returns |
| --- | --- |
| `Receiver()` | `RadioXLReceiverKind`: `None`, `Vehicle`, `Radioport` |
| `CurrentStation()`, `CurrentTrack()` | `CName`, `n"None"` with no radio on |
| `Position(station)` | `Float`, seconds into the station's current song. A station runs whether or not anyone listens. `-1` when unreadable |
| `Remaining(station)` | `array<CName>`, songs not yet played this cycle. The station picks among them at random, so the order means nothing |
| `History()` | `array<CName>`, the songs played on the current station, oldest first, at most 32 |
| `HistoryCursor()` | `Int32`, the song in `History()` playing now; before the end after a previous-song press |

## Changing things

Each returns `Bool`: false when nothing happened (no radio on, an unknown name, a refused request, or
the value was already set). Song changes go through RadioXL's own song keys, so the station's
schedule, its idents and the history stay right.

| Function | Does |
| --- | --- |
| `NextSong()`, `PreviousSong()` | what the song keys do |
| `PlaySong(station, track)` | plays a song on its station now. **Refused for a song the player switched off** |
| `NextStation()`, `PreviousStation()` | what the station keys do |
| `TuneStation(station)` | tunes the radio that is playing |
| `SetSongState(track, state)` | sets a song as the Stations tab does, and saves it. Switching off the song playing moves on |
| `SetStationSkipped(station, skipped)` | saved |
| `SetMyStation(station)` | `n"None"` clears it |
| `SetIdentsMuted(muted)`, `SetNewsMuted(muted)` | saved |
| `ShowNowPlaying(popup)` | the radio popup when `popup` is true, else the on-screen line |
| `SetEqPreset(name)` | a preset's name or `"Custom"`. Refused for a name not loaded. Saved |
| `SetStationEqPreset(station, name)` | `""` sets the station back to the global equaliser; `"Custom"` to its own bands, which start from what it plays the first time. Refused for an unknown station or preset. Saved |
| `SaveEqPreset(name, bands)` | writes the nine gains (dB, -24 to 24) as a new preset file in `red4ext/plugins/RadioXL/presets` and loads it. Returns `RadioXLPresetSave`: `Saved`, `BadName` (empty, over 40 characters, a space at an end, or `"Custom"`), `NameTaken` (ignoring case) or `WriteFailed` |
| `SetStationEqBand(station, band, db)` | clamped to -12 to 12. Puts the station on `"Custom"`, its other bands starting from what it played. Saved |
| `SetEqBand(band, db)` | a custom band, clamped to -12 to 12; heard while the global equaliser is `"Custom"`. Saved |
| `SetProcessing(mode)`, `SetProcessingStage(stage, on)` | saved |
| `SetBoost(db)` | clamped to 0 to 12. Saved |
| `SetRadioportLikeCar(on)` | a Radioport that is playing is retuned to its station so the change is heard at once. Saved |
| `SetSituationMuted(situation, muted)` | a restriction in force takes the change at once. Saved |
| `SetMixMuted(mix, muted)` | saved |
| `SetTrafficStations(mode)`, `SetRandomWorldRadios(on)`, `SetRandomStreams(on)` | saved |

## Events

| Event name | Class | Fields |
| --- | --- | --- |
| `RadioXL/Ready` | `RadioXLReadyEvent` | `Version()`, `Stations()`: the number of stations (`Int32`) |
| `RadioXL/SongChanged` | `RadioXLSongChangedEvent` | `Station()`, `Track()`, `Receiver()`, `Requested()`: true for a key press or `PlaySong`, false for the station's own pick |
| `RadioXL/StationChanged` | `RadioXLStationChangedEvent` | `Station()`, `Previous()`, `Receiver()` |
| `RadioXL/RadioPower` | `RadioXLRadioPowerEvent` | `Receiver()`, `On()` |
| `RadioXL/CatalogRefreshed` | `RadioXLCatalogRefreshedEvent` | `Station()`, `Added()`: a quest added songs |
| `RadioXL/SongStateChanged` | `RadioXLSongStateChangedEvent` | `Track()`, `State()` |
| `RadioXL/MutesChanged` | `RadioXLMutesChangedEvent` | `Idents()`, `News()` |
| `RadioXL/Silenced` | `RadioXLSilencedEvent` | `Restriction()`, `Silenced()` |
| `RadioXL/MyStationChanged` | `RadioXLMyStationChangedEvent` | `Station()` |
| `RadioXL/StationSkipChanged` | `RadioXLStationSkipChangedEvent` | `Station()`, `Skipped()` |
| `RadioXL/EqChanged` | `RadioXLEqChangedEvent` | `Station()`, `Preset()`: the preset the radio plays, whenever it or the station changes |

**Redscript:** register by name. Register `RadioXL/Ready` with `sticky` set, so a mod that loads after
RadioXL still gets it.

```swift
public class MyRadioListener extends ScriptableService {
  private cb func OnLoad() {
    let cs = GameInstance.GetCallbackSystem();
    cs.RegisterCallback(n"RadioXL/Ready", this, n"OnReady", true);
    cs.RegisterCallback(n"RadioXL/SongChanged", this, n"OnSong");
  }
  private cb func OnReady(evt: ref<RadioXLReadyEvent>) { /* safe to read now */ }
  private cb func OnSong(evt: ref<RadioXLSongChangedEvent>) {
    let title = RadioXLAPI.TrackTitle(evt.Track());
  }
}
```

**CET:** CET cannot receive these events, so `Observe` the matching method on the `RadioXLEvents`
service. It is called with the event's fields, in the order the table gives them.

```lua
Observe("RadioXL.RadioXLEvents", "OnSongChanged", function(self, station, track, receiver, requested)
  print(station.value, track.value, requested)
end)
```

The methods are `OnReady`, `OnSongChanged`, `OnStationChanged`, `OnRadioPower`,
`OnCatalogRefreshed`, `OnSongStateChanged`, `OnMutesChanged`, `OnSilenced`, `OnMyStationChanged`,
`OnStationSkipChanged` and `OnEqChanged`. A CET mod that starts after `Ready` has fired reads `IsReady()` instead.

## Station data for your mod

A station author can put data for your mod in their `station.json`, under `extensions` and your mod's
name. RadioXL passes it on as written and reads none of it.

```json
"extensions": {
  "MyMod": { "weight": 2, "districts": ["Watson", "Kabuki"] }
}
```

`RadioXLAPI.StationExtension(station, "MyMod")` returns `{"weight":2,"districts":["Watson","Kabuki"]}`.
Parse it with any JSON reader. Choose your mod's key once and tell station authors what goes in it.

## Recipe: a pool of songs to play yourself

A mod playing station songs somewhere else (NPC car stereos, a jukebox) builds its pool like this, so
a song the player switched off never plays:

```swift
let pool: array<CName>;
let stations = RadioXLAPI.Stations();
for station in stations {
  if RadioXLAPI.IsCustomStation(station) && !RadioXLAPI.IsStreamStation(station) {
    let tracks = RadioXLAPI.Tracks(station);
    for track in tracks {
      if RadioXLAPI.IsSongPlayable(track) { ArrayPush(pool, track); }
    }
  }
}
// TrackFile(track) is the audio to register with AudioXL, TrackGain(track) the level to play it at.
```

Listen for `RadioXL/SongStateChanged` to drop a song the moment the player switches it off.

## Version history

| Version | RadioXL | Changes |
| --- | --- | --- |
| 1 | 0.6.0 | First release |
| 2 | 0.8.0 | Sound: the equaliser, its presets and each station's own preset or bands, processing, the volume boost and the Radioport switch, and `RadioXL/EqChanged`. The mute situations and mix switches. The traffic and random-pick settings (0.7.0) |
