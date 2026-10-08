# Feature List - RadioXL

## Implemented

- Custom stations are real engine stations: the compiled roster and station name table are extended
  at plugin load, so the Radioport, world radios and the vehicle radio all play them unwrapped.
- A station is one manifest per mod, plus its audio files and at most an icon archive. Any number of
  station mods coexist; nothing vanilla is replaced, and the framework's one archive holds only its
  own glyph.
- A station's `icon` may name an existing UIIcon record (`UIIcon.RadioHipHop`) and ship no archive;
  a record that does not exist falls back to the glyph (#21).
- A track marked `ident` plays between songs as a station ident, with no title and no song slot (#29).
- A station's track can be a live MP3 stream URL, as its only track; it joins the stream live on
  tune-in and reconnects on its own (#23).
- A station that names no icon shows the RadioXL glyph, shipped in the framework's archive; the
  record `UIIcon.RadioXL` exists for a RadioXL 0.1.0 station yaml that names it.
- Resume: tuning back to a custom station picks the song up where the station has got to, the
  way a vanilla station does. The plugin reads the engine's own station clock four times a second
  and arms the current track's row with it as the next voice's start (`PlayFrom`, AudioXL 0.3.0).
  Nothing runs on a script timer, so a station picked from an open selector resumes too. Verified
  in game: a tune-back after a minute away landed on the next song as the schedule said, and swaps
  from an open selector resumed every time.
- "Mute the radio when..." - eleven switches in the Redscript Configuration Framework panel, all on
  by default (= the game), acting on every station. Six situations decide the Radioport's
  restrictions by cause (calls, scenes, driving scenes, clubs, weapons-free areas, quests); five
  mix switches in the plugin lift Wwise rules (combat music, police music, voices, H10's building
  music, menus). Verified in game: apartment, club, scene, combat, wanted star, voices, H10 and the
  inventory, map and hub. RCF is optional.
- Equaliser (Sound tab, #70): nine bands, a preset or Custom, global and per station (Stations
  tab, with a suggested preset for 13 game stations), on the car, Radioport and metro radio buses.
  Presets are JSON files in `red4ext/plugins/RadioXL/presets`, 16 shipped, level-trimmed. Verified
  in game: heard switching; probe bands match every station's preset across 19 stations.
- Processing (Sound tab, #70, #52): AGC, peak compressor and limiter; Off, Broadcast or Custom.
  Verified in game: level-matched with the probe, heard.
- Script API version 2: Sound, mute situations, mix switches and traffic settings, `RadioXL/EqChanged`.
  Verified in game by `tests/api`: 97 of 97 on foot and in a car.
- Volume boost (Sound tab, #70): 0 to 12 dB on the two player radio buses, after both game sliders; the
  car's cabin reverb send takes the boost and the Car Radio slider too. Verified in game: +13 dB at the
  output at +18, silent at slider 0 with +18, nothing clipped (the game's own output limiter).
- "Sound like a car radio" (Sound tab, #70): the Radioport on foot plays at a car radio's level
  with no low- or high-pass, by flattening its mixer's `veh_radio_tier` curves below tier 2, and
  retunes a playing Radioport so the change is heard at once. Verified in game: level with the car
  on the same station, no Radioport under the car radio, and switching back restores the game's sound.
- `RadioXLAPI.RegisterStation(name)`: a RadioXL 0.1.0 station's script compiles and is logged; the
  station is not created (#10).
- The script API (#39): `RadioXLAPI` reads, deck-backed acts and ten events, reachable from CET as
  `RadioXL_RadioXLAPI` and `Observe("RadioXL.RadioXLEvents", ...)`. Verified in game by
  `tests/api`, run both ways: 63 checks pass in a car, and 75 on foot, where it also reads an
  installed station's description (API and `-desc` key, through Codeware and GetLocalizedTextByKey),
  its extensions, 19 idents while muted, and a stream station's reads. Every event reached a CET
  Observe as often as a redscript listener; in a car no Radioport power event arrives. A song
  switched off through the API stays off after a save load. Not reached: CatalogRefreshed,
  Silenced, and StreamState Connecting and Live. Blocked and Failed seen, each with its warning in
  game (the Failed one both from the test and by hand). The description checked in `en-us` and `de-de`,
  switched live without a restart.
- Manifest `description` (#60) and `extensions`, with builder support for the first.
- Each track's length is read from its file at load, so a station runs on the world clock like a
  vanilla one. No durations, event names, Wwise ids or records in a manifest.
- Station name and song titles are real localization entries, resolved wherever a vanilla one is.
- A song's title is optional: an untitled song plays at world radios and in Streamer Mode, and its
  name reads blank in the radio popup (#33). Verified in game.
- The station appears in the vehicle's station selection UI, sorted by frequency, with its own name and icon.
- A vehicle radio switched off and on stays on the custom station it was on. Verified in game.
- `news: true` lets Stanley's news and greetings reach a station, under the same engine rules as
  vanilla stations (#16). A greeting reaching a custom station is verified in game.
- Each track has an optional `gain` of its own, multiplied with the station's, so a loud file
  comes down and a quiet one goes up without re-encoding (#42). The builder measures every file
  and suggests the value that lands it on the game's own level, bounded by the file's peak.
- A station's level is a send trim, the way every vanilla station's is: the framework loads its own
  bank, defining the `radioxl_radio` custom-sound type carrying copies of a vanilla station's two
  Broadcast Sends. No game file is replaced, and the game's own `mod_sfx_radio` type remains the
  fallback if the bank does not load.
- An optional level trim per station (`gain`, 0..4), applied in the samples through AudioXL on top of
  the send trim. Above 1 it must keep the file's peak under full scale, because AudioXL wraps a
  16-bit sample past it (#41); the builder is where that is checked.
- The level target a track aims at is derived offline from the game's own files
  (`tools/level-target.py`, #44): every vanilla radio track measured and put on the broadcast chain
  with its station's send trim. A custom sound adds nothing of its own: on the Radioport a RadioXL
  row lands on Vexelstrom's copied trims within the method's noise against seven vanilla stations.
  A file at about -11 LUFS lands on the game's median through `radioxl_radio`. The receivers are
  measured too: the Radioport and a car pass both channels straight through; a world radio sums
  them into one.
- A manifest is read by a strict JSON parser and checked field by field. Every fault is logged with
  the file and the line, and a manifest with one is skipped whole. Covered by `plugin/tests/`.
- One dial on every receiver: a custom station sits at the frequency at the front of its display
  name, between the vanilla stations, in the vehicle list and in the next/previous order of a car,
  a world device and the pocket radio.
- Custom stations on traffic car radios, by setting: Most cars (the shared nine-station lists),
  Every car, Off; and world radios and jukeboxes that start at random can land on one. Stream
  stations join both only with their own switch (#63). A traffic radio is tuned but not heard in
  the game; this is groundwork for making traffic radios heard.
- A car taken from traffic keeps the custom station it was playing, and a car saved on a custom
  station loads on it (#68).
- Custom stations broadcast on channels 256 and up, on a broadcaster widened to 1024 channels, so
  none shares a channel with the game's stations, TVs, world music or ambience (#69).
- Custom stations start at enum 26, past the police scanner (23) and Kurtz (33), which keep their
  own slots; up to 101 custom stations (#71).
- A station with `addUnlistedFiles` keeps its track list in step with its folder, rewriting
  `station.json` in place (#66); track lengths are cached between launches.
- A custom track's name and the player's settings for it follow its file, not its position (#65).
- Keys for next/previous song, next/previous station, show what's playing, never play this song
  again and jump to my station. One set serves both radios, picked by whether a car radio is on;
  each key can carry a held modifier, and the Radioport can have its own set. Next and previous
  song default to F3 and F2; the rest start unbound (#35).
- Every song on every station, vanilla included, is On, Off or Off while streaming; the game's
  streamer-unfriendly songs start on Off while streaming, and a song hidden while Streamer Mode is
  on is marked in its row. The deck skips past a song that is off (#35).
- A station can be set aside so the station keys step over it; it stays pickable from the radio.
- My station: the radio tunes to a remembered station, by name, on getting into a car, on car radio
  power-on or on Radioport power-on; a car radio that is off is switched on.
- The car's song popup can show for the Radioport too, on a song change and as it comes on, and the
  station and song can show as an on-screen message.
- Mute station idents (from the next song), and mute DJ announcements (Stanley's news, Maximum Mike,
  Growl FM's Ash; Kurt Hansen's Dogtown broadcasts are kept), both kept in `state.json`.
- A stream station that cannot play puts a red warning on screen once per launch, naming the
  AudioXL.ini line it needs (#55).
- `showFrequency: false` shows the station's name alone as its label; the frequency still places it
  on the dial (#49). `description` is one text or an object of language codes, 1000 characters each.
- A second track naming the same file as an earlier one is dropped and logged.
- The station builder (`site/`, its own version and `site/CHANGELOG.md`) writes a station.json, icon
  archive and zip from a form, imports RadioExt stations, measures each file to the game's level,
  previews the station on a Radioport and world radios, and on opening a station offers to add audio
  files its tracks miss and remove tracks whose file is gone (#67).

## Verified in game

- Traffic cars pick custom stations (4 of 34, then 149 of 337 with the player's car on one);
  Off applies mid-session (0 in 36); jukeboxes started on OutrunWaves and PHONKWAVE (#63).
- 113 song settings migrated to file-based names; removing Tool FM's first file left the others'
  settings in place (#65).
- `addUnlistedFiles` added a dropped file and removed a missing one, writing `station.json` in the
  mod's own MO2 folder; the relaunch took 131 lengths from the cache (#66).

- The player controls folded in from Simple Radio Control (#35): the four-tab panel with the modifier and Radioport key rows appearing behind their
  switches; a song switched Off and skipped; next and previous song on Tool FM in a car and on the
  Radioport, and the station keys stepping over a station set aside; My station tuning on getting
  into a car; both talk mutes; the remembered station and the mutes back after a relaunch from
  `state.json`.

- Idents play between songs, show no title, and leave song slots alone (#29).
- A stream station plays on the Radioport, a car and a world device, reconnects on tune-back, and at
  gain 1 sits inside the vanilla loudness range (#23).
- A station naming an existing UIIcon record shows that icon; one naming a missing record shows the RadioXL glyph (#21).
- Audio on all three receivers, three stations installed side by side, MP3, WAV, FLAC and OGG tracks.
- Station name and icon on the Radioport, the vehicle selector, the dashboard and world devices.
- No crackle at a world device: 0 wrap artefacts in 550 s of capture, true peak -1.4 dBFS, a custom
  station inside the vanilla loudness spread.
- Each track plays once, over three slot boundaries.
- The radio system owns the sound: switching station stops the previous track, a vehicle takes the
  station over from the Radioport, a world device attenuates with distance, a wanted star ducks the
  audio and combat stops it, and the Music slider moves it.
- The routing bank survives loading a second save without restarting.
- One dial on every receiver: a custom station at 104.9 sits between 103.5 and 106.9 in a car, on a
  world radio and in the vehicle list, and cycling wraps at the end of the roster. World radios skip
  Samizdat as vanilla does; cars and the pocket radio reach it.

- Next draws from the station's own remaining list and takes what it plays out of it, counting a
  key press toward the next ident (#36). Measured: four presses on Growl FM took the list from 15
  to 11 and the pick counter from 1 to 5; on Body Heat an ident followed the third press at the
  next natural song end. A list the keys drain is refilled by the next request, as the engine
  refills it on its own pick (measured: Tool FM 0, then 11 on the press that followed).
- The catalog follows a station whose track list changes during a session: Body Heat gains two
  songs once the Kerry quest fact is set, and they appear on the Stations tab and under the next
  key without a relaunch (#38). Measured.
- Previous and next walk a history cursor over what played. Measured at a 3 s pace (12, 4, 12, 4,
  12, then forward to 15) and after five sub-second presses (previous retraced 7, 10, 11, 2).

## Awaiting in-game verification

- The CatalogRefreshed and Silenced events (#39).
- The never-again key's switch surviving a save load; previous stepping back over station picks.

- The never-again key says "Switched off: <song>" on screen; the panel's long labels are one-line
  rows.


## Planned

- Mute news only, leaving the rest of the DJ talk: the announcement graph names its scenes, so a
  filter on `radio_00_news.scene` is possible.
- Panel translations beyond English (`translations/`).
- Replace the two roster readers rather than patching their bounds, which lifts the 101-custom-station
  ceiling (127 roster slots, custom stations from 26). The vehicle step already carries a 32-bit total.
- The Escape menu still silences the radio: it adds a pause-all action and direct voice pauses.
- Build a playlist station in game from any installed song, saved as a manifest and read at the next launch (#19).
- Open enhancement issues: stream song titles (#51), radio processing presets (#52), a shared ident
  pool (#56), an all-news station (#57), a rotating song subset (#58), a segment-started event (#61).
