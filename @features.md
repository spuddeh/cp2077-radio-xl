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
- "Mute radio when..." - twelve switches in the Redscript Configuration Framework panel, one per
  `PocketRadioRestrictions` member, all on by default, applying to every station on the Radioport.
  A switch is a situation: off also lifts the companions its situation raises (a call, a vehicle
  scene and a scene are measured). Verified in game: a call and a Delamain ride play through with
  their switch off. RCF is optional.
- Shuffle: a four-way setting (Off, Every station, Vanilla only, Custom only), next launch, and a
  manifest's `shuffle: true` / `false` for one station. Verified in game.
- `RadioXLAPI.RegisterStation(name)`: a RadioXL 0.1.0 station's script compiles and is logged; the
  station is not created (#10).
- Each track's length is read from its file at load, so a station runs on the world clock like a
  vanilla one. No durations, event names, Wwise ids or records in a manifest.
- Station name and song titles are real localization entries, resolved wherever a vanilla one is.
- The station appears on the vehicle radio wheel, sorted by frequency, with its own name and icon.
- A vehicle radio switched off and on stays on the custom station it was on. Verified in game.
- An optional DJ per station (`speaker`), defaulting to none.
- A station's level is a send trim, the way every vanilla station's is: the framework loads its own
  bank, defining the `radioxl_radio` custom-sound type carrying copies of a vanilla station's two
  Broadcast Sends. No game file is replaced, and the game's own `mod_sfx_radio` type remains the
  fallback if the bank does not load.
- An optional level trim per station (`gain`, 0..1), applied in the samples through AudioXL on top of
  the send trim.
- A manifest is read by a strict JSON parser and checked field by field. Every fault is logged with
  the file and the line, and a manifest with one is skipped whole. Covered by `plugin/tests/`.
- One dial on every receiver: a custom station sits at the frequency at the front of its display
  name, between the vanilla stations, in the vehicle list and in the next/previous order of a car,
  a world device and the pocket radio.

## Verified in game

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

## Awaiting in-game verification

- The Radioport level against a vanilla station, by capture rather than by ear.

## Planned

- Station idents and ads aside, the only vanilla DJ a custom station could reuse is Stanley, whose
  227 lines name no station. His announcements target a selector the engine resolves, and declaring
  `speaker: Stanley` does not reach it (#16).
- Replace the two roster readers rather than patching their bounds, which lifts the 127-station
  ceiling. The vehicle step already carries a 32-bit total.
- Adopt RadioXL station definitions unchanged, starting with Outrun Waves 93.7.
- Build a playlist station in game from any installed song, saved as a manifest and read at the next launch (#19).
- The RadioExt parity audit is `concepts/radioext-parity-audit` in the vault (#20); both gaps it
  left, shuffle (#22) and an existing `UIIcon` record as the icon (#21), are implemented.
