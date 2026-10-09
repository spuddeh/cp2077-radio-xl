# RadioXL

A custom radio station for Cyberpunk 2077 that is a **real engine station**, not a mod-authored music
player. The engine's station roster is a fixed 14-slot array compiled into the binary. Earlier
station mods each brought a player of their own, and reached only the receivers they wrapped. This
framework extends that array instead, so a custom station plays on the Radioport, the vehicle radio
and world device radios through the game's own radio system, with nothing wrapped around them.

**This is RadioXL from 0.3.0 on.** DigitalVixen's RadioXL 0.1.0, the script player, is what it
replaces: the name carries over to a new Nexus page, the audio side stays DigitalVixen's in AudioXL,
and a station written for 0.1.0 is rewritten as the manifest below (its script still compiles and
the log names it).

On Nexus: [RadioXL - Native Radio Stations](https://www.nexusmods.com/cyberpunk2077/mods/33983).
Stations play on every receiver with their own names, icons and song titles; tuning back in lands
mid-song on the station's own clock; the settings panel carries the keys, the per-song switches, My
station, the mutes and which random picks may land on a custom station. What is still open is in
the [issues](https://github.com/spuddeh/cp2077-radio-xl/issues), the working board, with what has
been measured on each.

**Writing a mod that works with RadioXL?** The script API, for redscript and CET, is in
[docs/script-api.md](docs/script-api.md).

## What a station mod ships

One manifest, its audio files, and at most an icon archive:

```text
red4ext/plugins/RadioXL/stations/<YourMod>/station.json
red4ext/plugins/RadioXL/stations/<YourMod>/audio/*.mp3
archive/pc/mod/<YourMod>.archive          (optional - the station icon)
```

```json
{
  "name": "radio_station_yourstation",
  "frequency": 104.9,
  "displayName": "Your Station",
  "icon": "yourstation",
  "atlas": "yourmod\\gui\\yourstation.inkatlas",
  "news": true,
  "tracks": [
    { "file": "audio/first.mp3",   "title": "Artist - First Song" },
    { "file": "audio/second.flac", "title": "Artist - Second Song" }
  ]
}
```

The frequency is its own field and the name is the name alone; the framework composes the label the
game shows, `104.9 Your Station`, and refuses a name that carries a frequency.

A track can also be a `url`, a live MP3 stream, as a station's only track; the player allows its
host in AudioXL's `AudioXL.ini`. No durations, event names, Wwise ids, indices, TweakDB records,
yaml or redscript. The framework
derives or reads all of it. The full field reference is
[stations/README.md](red4ext/plugins/RadioXL/stations/README.md), which ships with the
framework so the `stations/` folder survives packaging.

## Requirements

- Cyberpunk 2077 2.31
- [RED4ext](https://www.nexusmods.com/cyberpunk2077/mods/2380)
- [redscript](https://www.nexusmods.com/cyberpunk2077/mods/1511)
- [Codeware](https://www.nexusmods.com/cyberpunk2077/mods/7780) - resource callbacks and localization
- [AudioXL](https://www.nexusmods.com/cyberpunk2077/mods/33442) 0.4.3 or later - plays the audio
  files, streams long tracks from disk, plays a stream URL, and carries the per-row start offset a
  resume needs
- [TweakXL](https://www.nexusmods.com/cyberpunk2077/mods/4197) - the station's records for the dial

Optional: [Redscript Configuration Framework](https://www.nexusmods.com/cyberpunk2077/mods/30726)
shows the settings panel and captures the keys; without it the defaults apply, with the next and
previous song on F3 and F2. [RedFunctions](https://www.nexusmods.com/cyberpunk2077/mods/32312)
0.13.0 or later keeps the remembered station and the two talk mutes across launches; without it
the station is remembered for the session only and the mutes stay off. It is a dependency of the
framework above, so a player with the panel has it.
[RedLogger](https://www.nexusmods.com/cyberpunk2077/mods/31920): with it installed the framework
writes what it registered to `r6/logs/mods/`; without it the logging compiles away.

## Settings

Five tabs in the Redscript Configuration Framework panel, every station and song on them read from
the game when a save loads.

- **Controls** - next and previous song, next and previous station, show what is playing, never
  play this song again, jump to my station, each on a key of the player's own with an optional
  modifier and an optional Radioport set; the song popup and an on-screen line for the Radioport.
- **My station** - the station the radio comes on to, at any of three moments.
- **Stations** - every station in dial order, the game's own included: a step-over switch, and
  On / Off / Off while streaming per song.
- **Sound** - one page: a line saying where the equaliser opens, **Volume boost** (0 to 12 dB past
  the game's maximum, for the car radio and the Radioport), and under a **Processing** heading three
  switches: Even out loudness, Soften peaks and Limiter. None on is off, all three is the processing
  a radio station puts on its sound before it goes out, and any mix is custom. Processing applies to
  the radio as a whole, not per station.
- **Mute** - station idents, DJ announcements, and **Mute the radio when...**: eleven switches,
  all on by default, which is what the game does. Six are situations that silence the Radioport (a
  call, a scene, a driving scene, a club, a weapons-free area, a quest blocking the radio); four
  lower or silence the car radio and the Radioport (combat music, police chase music, someone
  speaking, an open menu); one turns the Radioport down in Megabuilding H10. They apply to every
  station, the game's own included. The Escape menu still pauses the radio.

### The equaliser panel

The equaliser is set only in its own panel, which opens beside the Radioport's station list and
closes with it. It is built from the game's own widgets. Top to bottom: the station playing ("Radio
off" with none), **Per-station EQ**, the preset, nine band faders from 63 Hz to 16 kHz with up and
down arrows, the three processing switches, Volume boost, and the Reset key at the foot (the
popup's Z, Y on a controller). Picking a station redraws it at once. The equaliser plays on the car
radio, the Radioport and the metro; a preset changes the tone, not the volume, and presets are JSON
files in `red4ext/plugins/RadioXL/presets`.

**Per-station EQ** is one switch for every station, off by default. On, every station plays its own
equaliser: the one set for it, else RadioXL's suggested preset, else Flat (Growl FM and custom
stations have no suggestion), and Reset clears the station's own. Off, every station plays the
global equaliser, each station's own is kept, and Reset puts the global one back on Flat.

The panel works with the mouse, the keys and a controller. R (X on a controller) moves between the
station list and the panel; the arrow keys or d-pad move the game's own cursor between its controls,
and Enter or A presses one. The station list takes the mouse too: the wheel scrolls it, pointing at a
station selects it, a click plays it, and the volume arrows take a click.

## How it works

What the framework measured about the engine on the way - the compiled roster and its readers, the
boot-time window a station must be registered in, why every label is a key, what `mod_sfx_radio`
is and what AudioXL's renderer does with it - is written up in [docs/](docs/README.md), each claim
marked measured or inferred.

Several of those measurements are numbers a game patch can move, and none of them fails loudly.
[MAINTAINING.md](MAINTAINING.md) is the list of what to re-derive and how to tell it has gone wrong.

Three layers. The split matters, because each one extends a different engine system.

### The plugin - `plugin/src/`

A RED4ext plugin. At load it reads every station manifest, reads each track's length from the audio
file's headers (`Duration.hpp`: MP3, FLAC, Ogg Vorbis, WAV, nothing decoded; kept between launches in
`red4ext/plugins/RadioXL/cache.json`, keyed by each file's size and modified time, `Cache.hpp`), and **patches the
binary before any script runs**:

| Table | Holds | Patched sites |
| --- | --- | --- |
| the station roster, 14 `CName` slots | a station's identity | name-to-index and index-to-name readers, and the vehicle receiver's bound |
| the station name table, 14 `CName` slots | a station's label as a localization key | two readers, each of which reduces the index modulo 14; the division is erased |
| the vehicle receiver's next-station step | which station a car steps to | detoured to a stub reading the plugin's own dial tables, because the step runs the index through two dial-order switches on 0..13 around a modulo 14 |

Addresses resolve through RED4ext's shipped hash database, never hardcoded. Every byte is verified
first and the whole patch is abandoned on a single mismatch, because a half-patched radio system is
worse than an unpatched one. Both bounds are 8-bit immediates, so 127 stations is the ceiling.

A station manifest is read by a strict JSON parser and checked field by field. Every fault is logged
with the file and the line, and a manifest with one is skipped whole rather than half-loaded.

A station with `addUnlistedFiles` has its `tracks` brought in step with its folder and its
`station.json` rewritten in place (`Folder.hpp`).

The plugin exposes the manifest to redscript through registered natives (`RadioXL_Station*`). It does
not touch audio, TweakDB or UI.

### `RadioXL.reds` - assembly, as the resources load

Three of the game's own resources are patched **while they load**, because the engine builds its
station set once, at boot, and anything added afterwards is never constructed:

| Resource | What is added |
| --- | --- |
| `eventsmetadata.json` | one event row per track, carrying its duration |
| `cooked_metadata.audio_metadata` | membership in `radioStations`, an `audioRadioStationMetadata`, an `audioRadioTrack` per title |
| `onscreens.json` | the station name and every song title, inserted in sorted position under both hash widths |

Every label the game shows is a localization key, never text. The framework mints a key per station
and per title and registers the text against it, so the UI resolves a custom station the way it
resolves a vanilla one.

`Audio.reds` is the only place the framework talks to AudioXL: it registers each file on the
framework's own custom-sound type, `radioxl_radio` in `radioxl_routing.bnk`, which carries copies of
a vanilla station's Broadcast Sends so a station sits at vanilla's level on every receiver, and asks
AudioXL for the Wwise id. The game's own `mod_sfx_radio` type is the fallback when that bank is not
loaded.

### `Dial.reds` - records and the script-side dial

Creates the `RadioStation` and `UIIcon` TweakDB records from the manifest at load, with the index the
roster assigned, and wraps the game's redscript where the fourteen stations are written into switch
bodies and a literal array push. Three cycling functions are replaced rather than wrapped because
their bodies carry `% 14`. That makes this framework an alternative to RadioExt and RadioXL 0.1.0,
not a companion.

## Building the plugin

Header-only against [RED4ext.SDK](https://github.com/WopsS/RED4ext.SDK). The CMake file expects the
SDK at `../../../_source/RED4ext.SDK/include`; point `target_include_directories` at your own copy.

```powershell
cmake -S plugin -B plugin\build -G "Visual Studio 17 2022" -A x64
cmake --build plugin\build --config Release
Copy-Item plugin\build\Release\RadioXL.dll red4ext\plugins\RadioXL\
```

The SDK's exports are version-qualified (`RED4ext::v1::PluginInfo`, `RED4EXT_V1_SEMVER`).

## The probe

`probe/` holds `RadioStationProbe`, a read-only RED4ext plugin that reads the engine's radio station
objects and logs what changes. It writes nothing into the game. It logs:

- each station's listeners, active flag and voice handles
- each station's schedule: state, current song, the remaining list, picks since the last ident, the
  RNG state, and the track list again whenever the engine changes it
- the station array order, and the DJ table the engine picks announcement stations from
- a station's queued and playing announcement
- the engine's custom-sound voice slots

The log is RED4ext's plugin log, `red4ext/logs/radiostationprobe-*.log`. It is a development tool, not
for players, and works on game 2.31 only. It is never part of a RadioXL download. Build it the same way
from `probe/plugin`.

## Design rules

- **Extend what the engine already stores. Never mimic it.** If a label is wrong, find the table the
  engine reads and extend it; do not wrap the UI to substitute a string.
- **Wrap only where no table exists.** `RadioStationDataProvider` and `VehiclesManagerDataHelper`
  hold the fourteen as literals, with nothing behind them to extend.
- **No parallel audio path.** A station is a voice on the game's own radio emitter. A sound played
  alongside the radio is wrong even when it is audible.
- **The manifest is the whole station.** Nothing a modder has to compute goes in it.

## Known limits

- The DLL and the scripts ship together, always. A `.reds` that declares natives fails script
  validation without its plugin, and that stops every redscript mod on the machine.
- Three `@replaceMethod` on the cycling functions, so RadioExt and RadioXL 0.1.0 cannot coexist with it.
- 127 stations, because both roster bounds are 8-bit immediates.
- A world radio saves its station as an `ERadioStationList` value (`RadioControllerPS.activeStation`),
  so adding or removing a station mod can move one that was on a custom station. Cars save the
  station by name and are unaffected.
- Traffic car radios are tuned to a station but not heard: the game keeps a station whose only
  listeners are traffic cars silent. The traffic setting decides which stations they are on.

## Repository layout

```text
plugin/src/Main.cpp          the binary patch, the dial, the natives
plugin/src/Clock.hpp         the engine's station clock, handed to AudioXL as each track's start
plugin/src/Schedule.hpp      a station's remaining-tracks list, read and consumed for the song keys
plugin/src/Manifest.hpp      the manifest checks, every fault by file and line
plugin/src/Json.hpp          a strict JSON reader, every fault by line and column
plugin/src/Duration.hpp      a track's length from its file headers
plugin/src/Cache.hpp         those lengths kept between launches in cache.json
plugin/src/Folder.hpp        a station's tracks kept in step with its folder (addUnlistedFiles)
plugin/tests/                the manifest reader's tests, run by ctest
probe/                       RadioStationProbe, a development tool, never shipped
r6/scripts/RadioXL/
  RadioXL.reds               the three resource patches, and the natives' declarations
  Audio.reds                 the AudioXL bridge
  Dial.reds                  TweakDB records and the script-side dial
  Restrictions.reds          the "Mute the radio when..." switches
  Traffic.reds               custom stations on traffic car radios and world radios' random pick
  Warnings.reds              the on-screen warning for a stream station that cannot play
  Controls.reds, Input.reds, Deck.reds, Catalog.reds, MyStation.reds, Notifications.reds, State.reds
                             the keys, the song deck, the station list, My station, the popups
  Settings.reds              the settings panel, one provider, five tabs
  Eq.reds                    the equaliser: presets, Per-station EQ and the suggested presets
  EqPanel.reds               the equaliser panel beside the Radioport's station list
  EqPanelAnim.reds           its open and close, and its rows' hover
  StationListMouse.reds      the station list with the mouse
  Localization.reds, translations/
                             the station names and titles, and the panel's strings
  API.reds                   the script API (RadioXLAPI); see docs/script-api.md
  Events.reds                the script API's events
r6/storages/RedscriptConfigFramework/
                             the panel's card and the in-game docs page
red4ext/plugins/RadioXL/
  RadioXL.dll                the built plugin
  radioxl_routing.bnk        the framework's custom-sound type
  stations/README.md         the manifest reference, ships with the framework
archive/pc/mod/RadioXL.archive
                             the RadioXL glyph, the fallback station icon, and the equaliser
                             panel (radioxl\gui\eq_panel.inkwidget)
docs/                        what was measured about the engine
example-station/, tools/make-example-station.py
                             the Nexus optional download, a working station with generated audio
tools/                       the routing bank builder, the loudness meter, the RadioExt converter,
                             the equaliser panel's widget builder (eq-panel-ink.py)
site/                        the station builder page
```

The example station package is the worked example: `python tools/make-example-station.py` builds it.

## License

[MIT](LICENSE). Take what is useful.

The RadioXL glyph is the exception: it is DigitalVixen's artwork and not covered by MIT. See
[NOTICE](NOTICE.md).

## Credits

RED4ext by WopsS. AudioXL and RadioXL 0.1.0 by DigitalVixen. Codeware and TweakXL by psiberx.
Always My Radio Station by CozmiNU and Better Vehicle Radio by infinitY0369, which the keys, My
station and the per-song switches grew from. RadioExt by keanuWheeze, for getting there first.

## Disclaimer

This mod was developed with the assistance of an LLM. All in-game testing and code validation was
performed by a human. No rogue AIs were permitted through the Blackwall.
