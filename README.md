# RadioXL

RadioXL lets you add your own radio stations to Cyberpunk 2077, and they behave like the game's own. Each one sits on
the dial at its own frequency and plays in cars, on the Radioport and on the radios out in the world, through the
game's own radio. It also gives the radio an equalizer, the Library (pick exactly which song plays on any station),
and shards, your own playlists made from any song you have installed.

Download it from Nexus: [RadioXL - Native Radio Stations](https://www.nexusmods.com/cyberpunk2077/mods/33983).

## Playing

Requirements, install, every setting and troubleshooting are on the
[Nexus page](https://www.nexusmods.com/cyberpunk2077/mods/33983). The same guide is in game: open the Redscript
Configuration Framework hub and pick RadioXL under DOCS.

## Making a station

The quickest way is the [station builder](https://spuddeh.github.io/cp2077-radio-xl/). It runs in your browser,
takes a folder of songs, levels them, makes the icon, and gives you a zip ready for your mod manager.

By hand, a station is one folder holding a `station.json` and the audio files it names:

```text
red4ext/plugins/RadioXL/stations/<YourMod>/station.json
red4ext/plugins/RadioXL/stations/<YourMod>/audio/*.mp3
archive/pc/mod/<YourMod>.archive          (optional, the station's icon)
```

```json
{
  "name": "radio_station_yourstation",
  "frequency": 104.9,
  "displayName": "Your Station",
  "tracks": [
    { "file": "audio/first.mp3", "title": "Artist - First Song" },
    { "file": "audio/second.flac", "title": "Artist - Second Song" },
    { "file": "audio/ident.mp3", "ident": true }
  ]
}
```

The game shows the name and frequency together, `104.9 Your Station`. Songs can be MP3, OGG, FLAC, or WAV as 16-bit
PCM. Every field is in [stations/README.md](red4ext/plugins/RadioXL/stations/README.md), and
[example-station/](example-station/) is a working station to start from.

## For mod authors

Other mods can read RadioXL's stations and songs, change what plays and listen for changes, from redscript or CET.
The script API is in [docs/script-api.md](docs/script-api.md).

## How it works

Three parts, each extending a different part of the game:

- **The plugin** (`plugin/src/`), a RED4ext plugin. At load it reads every `station.json`, reads each song's length
  from its file, and extends the game's compiled list of radio stations and their name table, so a custom station
  is a real station to every radio. It checks every byte it changes first and changes nothing if one doesn't match.
  It also adds the equalizer, the mix switches and the shard station.
- **The scripts** (`r6/scripts/RadioXL/`). They add each station to the game's radio data as it loads, create its
  records, and hold the settings, the keys, the Library, shards and the script API.
- **AudioXL** by DigitalVixen plays every song. RadioXL registers the files with it and never plays audio itself.

What was measured about the game's radio on the way, and why each part works the way it does, is in
[docs/](docs/README.md).

## Building the plugin

You need Visual Studio 2022 (or its Build Tools) with CMake, and a clone of
[RED4ext.SDK](https://github.com/WopsS/RED4ext.SDK).

```powershell
pwsh -File plugin\build.ps1 -SdkRepo <path to your RED4ext.SDK clone>
```

It builds the plugin for game 2.5 against the SDK commit pinned in `plugin/builds.json`, into
`red4ext/plugins/RadioXL/`, and keeps its PDB in `symbols/<version>/<game>/`.

## What's in the repository

```text
plugin/src/                  the RED4ext plugin
plugin/build.ps1, builds.json, red4ext-plugin.cmake, CMakeLists.txt
                             the build
r6/scripts/RadioXL/          the scripts
r6/storages/RedscriptConfigFramework/
                             the settings panel's card and the in-game docs page
red4ext/plugins/RadioXL/     the built plugin, the routing bank, the presets and stations/README.md
archive/pc/mod/RadioXL.archive
                             the RadioXL glyph and the UI's widgets
symbols/                     the PDB for every released DLL
docs/                        notes on how the game's radio works
example-station/             a working station, the Nexus optional download
site/                        the station builder
```

## License

[MIT](LICENSE). Take what's useful.

The RadioXL glyph is the exception: it's DigitalVixen's artwork and not covered by MIT. See [NOTICE](NOTICE.md).

## Credits

- DigitalVixen, for RadioXL 0.1.0, the groundwork this rework stands on, and for AudioXL, which plays every song.
- CozmiNU for Always My Radio Station and infinitY0369 for Better Vehicle Radio: My station, the keys and the
  per-song switches grew from what those two mods do.
- keanuWheeze for RadioExt: he got there first and showed everyone that people want their own stations.
- psiberx for Codeware and TweakXL, and WopsS for RED4ext.

## Disclaimer

This mod was developed with the assistance of an LLM. All in-game testing and code validation was
performed by a human. No rogue AIs were permitted through the Blackwall.
