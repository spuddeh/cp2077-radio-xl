# Changelog - RadioXL

## [Unreleased]

### Changed
- The manifest's `gain` runs 0 to 4 instead of 0 to 1 (#41). `Manifest.hpp` gains `kMaxGain`; the
  clamp message reads `"gain" is 0 to 4 - clamped`; a raised gain is read as written and tested.
  The station README grows a Level section stating the rule a raise must obey: AudioXL scales
  16-bit samples with a bare cast on the unity-rate path (`AudioFeed.cpp`), so peak + gain past
  0 dBFS wraps rather than clips. The plugin reads headers only, so the check lives in the builder.
- Builder: the Volume slider runs 0 to 400 % with the dB shown either side of 100 %;
  `buildManifest` writes any gain other than 1; a RadioExt `volume` above 1 imports as written up to
  4 with a note that RadioExt's value was tuned against its own player; an opened manifest's gain is
  clamped to 4, not 1. `manifest-rules.test.ts` accepts a gain above 1.

### Added
- `tools/level-target.py` (#44): the offline level target. Reads `audio_2_soundbanks.archive`
  directly (every entry is stored uncompressed), dumps `radio.bnk`, `cp_music.bnk` and `init.bnk`
  with wwiser, walks every `mus_radio_*` event from `eventsmetadata.json` to its segment, track and
  `.wem`, decodes each through `wwtools.dll` by ctypes, measures it with ffmpeg `ebur128`, and puts
  it on the chain with the station's send trim. `report` writes `tools/level-target/vanilla-levels.{json,md}`
  and `target.json`; `check` compares a capture against the model; `file` measures any audio the
  way the builder will and prints the peak-bounded gain. Result: 188 music tracks at -19.3 to -5.2
  LUFS (median -11.0), a file target of -10.9 LUFS on `radioxl_radio`, no dynamics on either radio
  bus, and `3803692087` is the master bus itself.
- `tools/measure-loudness.py report --json <file>` writes the capture in the shape `check` reads.
- `tools/level-target.py align <capture.wav> --route mono|stereo [--station DIR] [--track NN=<audio>]`
  (#44): the capture check done per track, because a station's own tracks spread 3 to 8 dB and a
  median comparison cannot reach 1 LU. Finds which track plays when by spectral fingerprint (32 log
  bands, 25 ms frames, 2 s mean removed, 20 s chunks correlated by FFT) over every decoded vanilla
  track, each `--station`'s files and any `--track` another mod adds to a vanilla station; measures
  capture and source over the same stretch; reports chain, model and residual per passage; measures
  the recording's floor and does not count a passage the room lifts by more than 1 dB. Vanilla
  fingerprints are cached in `work/fingerprints.npz`. No probe log. Needs numpy and scipy.
  `measure_one` takes an optional excerpt. On the captures already on disk: five Growl FM tracks at
  the Radioport put the method's own noise at about 1 LU per passage; the one RadioXL-against-vanilla
  pair (a world device, 2026-09-09) has RadioXL 2 dB under the model, with the standing spot unrecorded.

## [0.3.0] - 2026-09-16

### Changed
- The manifest's `speaker` is replaced by `news` (#16). `news: true` writes the station's
  `audioRadioSpeakerType` as `Stanley`, false or absent writes `None`; the native
  `RadioXL_StationSpeaker` (String) becomes `RadioXL_StationNews` (Bool) and `RadioXLSpeaker` is
  gone. No other speaker is offered: Mike's lines name Morro Rock, Ash is bound to Growl FM by
  name, and Stanley's name no station. A `speaker` key is reported as an unknown key. Traced
  on 2.31: a queued announcement resolves through the token table (`0x4fe680`, last station in hash
  order with any listener), an unqueued one through `0xb44688` (first match in the nearby list);
  both require the station's speaker to match. A Stanley greeting was heard on Tool FM.
- Renamed from Native Radio Framework to RadioXL: the framework takes over DigitalVixen's RadioXL
  name and Nexus page (33488) from the 0.1.0 script player. Plugin `RadioXL.dll`, redscript module
  `RadioXL`, natives `RadioXL_*`, records `RadioStation.RadioXL_<name>` / `UIIcon.RadioXL_<name>`,
  localization keys `...-RadioXL-<name>`, custom-sound type `radioxl_radio` in `radioxl_routing.bnk`
  (rebuilt; ids are FNV of the new strings), station manifests under
  `red4ext/plugins/RadioXL/stations/`. GitHub repo `spuddeh/cp2077-radio-xl`.
- AudioXL 0.4.0 is the minimum, for stream stations; 0.3.0 streams compressed tracks of 45 s or more from disk, which
  removes the resident-PCM cost that made WAV the recommendation (#4), and adds `PlayFrom`,
  `Position`, `IsPlaying` and `Pause`.

### Fixed
- A song with no `title` was silent at world radios and with Streamer Mode on (#33). `AddTitle`
  skipped the `audioRadioTrack` row for an untitled song, so it had no `isStreamingFriendly`, and the
  engine refuses such a track when no player receiver listens or Streamer Mode is on. Every song now
  gets a row; an untitled one registers a single space as its text, so the radio popup reads blank
  instead of the widget's `TRACK NAME` placeholder. Verified in game on a three-song untitled station.
- Toggling a vehicle radio off and on while on a custom station landed on a random vanilla one
  (#27). The receiver's turn-on block treats a stored station at or past 14 as none chosen; the
  bound is raised to the station total with the other three. The block has no RED4ext hash, so
  the plugin follows the enable routine's own `jne` to it and verifies the bytes there.

### Removed
- Shuffle (#22): the setting, the manifest `shuffle` field, the plugin's read of RCF's file at boot
  (`ReadShuffleMode`), the `RadioXL_ShuffleVanilla` native, and the script's reorder of vanilla
  `tracks` with its EP1 metadata callbacks. The engine draws songs at random itself: the picker
  (`0x6bcdfc`, 2.31) rolls from a remaining-tracks list and refills it when empty, and the station
  probe logged Body Heat and PHONKWAVE picks out of stored order with RadioXL not reordering
  anything. A `shuffle` key in a manifest is now logged as unknown and ignored. Tool FM's manifest
  drops it.

### Added
- `frequency` is its own manifest field, a number from 10 to 999, required, and `displayName` is
  the name alone, required (#40). The plugin composes the label (`Label`, `FrequencyText`: one
  decimal, two when written), so every station reads the same way on the dial, and `Manifest.hpp`
  refuses a name that starts or ends with a number reading as a frequency, contains the
  frequency, is empty, or has a space at an end, two in a row or a control character
  (`ReadsAsFrequency`, `NameIsUntidy`). A 0.3.0 manifest with the number at the front of the name
  is refused, and the log says to move it. The checks run last so an earlier fault stays the first
  logged; every test manifest gained both fields on lines it already had. `BuildDial` orders by the
  field and logs a shared frequency. `stations/README.md` states the rules. The builder page writes
  the field, faults a missing or badly formed name, opens a 0.3.0 manifest by moving the number into
  the field with a note (`importStation.ts`), maps RadioExt's `fm` straight across, and
  `manifest-rules.test.ts` carries the refused and accepted cases. Tool FM and Hangouts FM manifests
  moved to the field.
- The catalog follows a station whose track list the engine changes during a session (#38).
  Body Heat's metadata entry is swapped for `radio_station_05_pop_completed_sq017` (the same 13
  tracks plus `off_the_leash` and `user_friendly`) once `sq017_enable_kerry_usc_radio_songs` is
  set, about a minute after load; the pairing is hardcoded in the exe and it is the only such
  variant, so no other station changes. `RadioXL_StationTracks` (`Schedule.hpp`) hands the
  catalog the live list through the station object; `Catalog.Refresh` rebuilds one station's
  tracks in place, keeping known track objects and titling new ones from the same table as at
  build, and runs when the deck or the never-again key meets a track it does not know and, for
  every station, when the Stations tab draws (`RefreshAll`, the schema is rebuilt per open). The
  swap also leaves the remaining list with no buffer, so `Consume`'s refill grows the list through
  the SDK `DynArray` (Clear, Reserve, PushBack: the engine's own allocator by hash) instead of
  requiring capacity. Measured: the tab lists both songs after the swap, the next key draws them,
  and the probe's `remain` line (now with `cap=`) went 0 cap 13 to 14 cap 19 on the first press.
- A song the keys request leaves the station's own remaining list and counts as a pick (#36).
  Two natives in `plugin/src/Schedule.hpp` on the station object the clock resolves, any state:
  `RadioXL_StationRemaining(station: CName) -> array<CName>` maps the entries of `+0x160` (count
  `+0x16c`, 4-byte track indices, measured) through the metadata's `tracks` (RTTI offset, `+0x38`
  on 2.31) to event names; `RadioXL_StationConsume(station, track, countPick) -> Int32` erases the
  entry (tail moved down, then the size dropped) and, when `countPick`, adds one to `+0x170`; 1
  erased, 0 known but not listed, -1 unknown. `Deck.DrawFromStation` draws at random among the
  list's playable, switched-on entries and `Draw` keeps the bag as the fallback for an empty or
  unreachable list; `Play` consumes every request, a key press counting and the automatic skip not,
  because the engine counted the song it skipped past. Both SEH-guarded; a fault disables them
  with one log line. Measured with the probe's new `remain` line: four presses on Growl FM took
  remaining 15 to 11 and picks 1 to 5 with the RNG untouched; on Body Heat a blip followed the
  third press at the next natural song end and the counter went back to 0. Also seen: Body Heat's
  track list grew from 13 to 15 about a minute after load (the two songs the Kerry quest unlocks, fact set on the save) and
  the engine emptied its remaining list when it did.
  A third run then showed a list the keys drained staying empty for good (Tool FM at 0 through 25
  presses: the engine refills only on its own pick), and the history jumbling under sub-second
  presses. So `Consume` gained `refill`: the deck draws among every song when the list is empty
  or holds nothing switched on, and the request writes `0..n-1` back first (capacity `+0x168`
  permitting) before erasing its pick, as the picker does; the script bag is gone. And the one
  pending key became a set of the keys requested in the last two seconds, so a late report of an
  older request reads as a request answered, not as an engine pick that truncates the history.
- Simple Radio Control folded in (#35), on a four-tab panel: Controls, My station, Stations,
  Mute. `Controls.reds` holds every setting and the bind table (one set of keys for both radios,
  ids `nextKey`..`myStationKey`; the Radioport set `pocket*` and the `mod:<id>` modifiers exist
  behind `separateRadioportKeys` and `useModifiers`, both `Rebuilds`); `Input.reds` matches a
  press on Codeware's Input/Key with the receiver decided at the press; `Deck.reds` is next,
  previous, never-again and the automatic skip through `RequestSongOnRadioStation`;
  `Catalog.reds` reads every station and track from the cooked metadata at session ready and
  owns the ident and announcement mutes; `MyStation.reds` tunes the remembered station on the
  three receiver-on moments; `Notifications.reds` the popup, the on-screen line and the 1 s
  Radioport poll; `State.reds` the mod's own `state.json` in RedFileSystem storage `RadioXL`.
  The Stations tab folds each station's songs behind a `show:<station>` switch. Panel strings
  are keys (`RadioXL.*`) in `translations/English.reds`, read through `RadioXLText`; the
  twelve situation switches moved onto the same keys. The master Enabled switch was dropped.
  RCF's restore is ignored for `rememberStation`, `muteIdents` and `muteNews`, bracketed by
  `BeginRestore`/`EndRestore` around both `RestoreInto` and `Register`. Optional dependencies
  RedFileSystem and RedData added. Run in game the same day: every feature passed. After the
  run: the songs are listed under every station with no fold (`show:` rows gone), the situation
  switches' note is three label rows, and the Radioport poll shows the popup on the first read
  too, so switching the Radioport on shows what is playing.
  Then the next key was changed from walking the track list to a random pick (`RandRange`,
  exclusive upper bound as the game's own scripts use it), avoiding the song playing and the last
  four heard while enough others remain; previous pops a per-station history of eight that the
  arrival handler keeps, with a `m_backing` flag so the landing does not push the song it left.
  The automatic skip past a switched-off song picks the same way. The Radioport keys became a
  heading inside Keys, the long labels became one-line rows, a divider separates a station's
  step-over switch from its songs, and never-again puts "Switched off: <song>" on screen.
  The random pick then became a per-station shuffle bag (Fisher-Yates over the enabled,
  playable tracks minus the current one; a song the station plays itself leaves the bag through
  `Record`) and the history a cursor over every song that played: `Seek` walks it either way,
  `Draw` refills the bag past its end, and a song the engine picks while the cursor is back
  truncates the forward part. A requested arrival is told apart from an engine pick by the
  pending key.
- Station idents (#29): a track with `"ident": true` goes into `audioRadioStationMetadata.blips`
  (`audioRadioBlip.blipEventName`) instead of `tracks`, with no `audioRadioTrack` row. It keeps its
  event-table row and AudioXL row. New native `RadioXL_StationTrackIsIdent`. `Manifest.hpp` refuses
  a non-bool `ident`, an ident `url` track, and a station of idents only. `Clock.hpp` gives an ident
  track key 0, logs every song change and every ident start with the station clock. Measured on a
  test station (three 45 s tones, idents of 5.0 and 6.1 s): 2 idents in 7 song changes, each between
  two songs, song-to-song gaps 45.2 / 49.5 / 45.0 / 45.3 / 50.5 / 45.2 s, no title shown.
- Web streams (#23): a track may be `{ "url": "http(s)://...", "title": ... }` in place of `file`,
  as its station's only track. `Manifest.hpp` refuses `file` and `url` together, a non-http URL and
  a URL beside other tracks, and gives the track `kStreamDuration` (3600 s); `Main.cpp` skips the
  header read for it and hands the URL through `RadioXL_StationTrackFile`; `Clock.hpp` leaves the
  station out, since a URL row refuses `PlayFrom`. `Audio.reds` registers it with `RegisterSound`,
  logs `HttpStatus` when `HttpAllowed` is false, and calls `Poll` and `PendingRemote` from the
  level-trim retry. A URL row appears seconds to minutes after registration; a diagnostic build
  calling neither saw both stream rows 13 s after boot, so the calls are not a requirement. The retry bound is 60 polls. Verified on the Radioport,
  a car and a world device; tune-back reconnects (`Position` 15.9 before a 60 s tune-away, 5.9
  after). Loudness measured with the new `tools/measure-loudness.py`: vanilla -16.3 to -19.6 LUFS,
  a loud stream at gain 1 -17.8, so streams take the default gain.
- `tools/measure-loudness.py`: records the game's loopback channel and splits it by the station
  probe's log into per-station integrated loudness and true peak.
- A manifest's `icon` may name an existing UIIcon record (`UIIcon.RadioHipHop`) with no `atlas`
  (#21). `Manifest.hpp` accepts `UIIcon.<name>` without an atlas, warns and drops an `atlas`
  beside one; `Dial.reds` points `RadioStation.RadioXL_<name>.icon` at the record and makes no
  `UIIcon.RadioXL_<name>`. A record missing at `OnApply` is logged and the glyph is used; yaml
  records import before any `OnApply`, so another mod's record is visible there. `Build` is split
  into the station record and `BuildIcon`. Tests in `ManifestTests.cpp` (`TestIconRecord`).
- Shuffle (#22): a four-way setting (Off, Every station, Vanilla only, Custom only), read by the
  plugin from RCF's own file at boot because RCF restores settings after the metadata has loaded;
  the script reorders vanilla `tracks` arrays as the base and EP1 metadata load, the plugin
  reorders custom stations as manifests are read. A manifest's `shuffle` is three-valued: `true`
  always, `false` never, absent follows the setting. Measured: a session-time reorder is ignored,
  so it takes effect on the next launch. DJ song nodes post by name and are unaffected.
- The mute switches apply to every station on the Radioport, vanilla included, and a switch is a
  situation: a lifted switch also lifts the companion restrictions its situation raises. Measured
  sets: a holo call brings `BlockFastTravel` and `QuestContentLock`; a vehicle scene brings
  `PhoneNoCalling`, `UpperBodyState` and the skip prompt; a scene brings `UpperBodyState` and the
  skip prompt. A wrap on `OnStatusEffectApplied` records every tag an effect carries before the
  game walks them, so the first companion already sees its situation and the radio never drops
  for the unlock delay. Every hint names its trigger in the game's code and its default; tab text
  is a `Label` row, since a `Tip` attaches to the last row built.
- Resume on tune-back (#1), from the engine's own station clock. The engine posts a custom track
  from 0 and hands no offset; the station object's clock (`+0x14c`) counts seconds since its slot
  began, on engine time, whether or not anyone listens. `plugin/src/Clock.hpp` reads it four times
  a second from the plugin's game-state update, asks the engine which track the station is on
  (`GetRadioStationCurrentTrackName`, matched by the track's localization key), and arms that row
  through AudioXL's `PlayFrom` over RTTI. Replaces `Clock.reds`, a DelaySystem watch that wrote the
  playing voice's position back each tick: the station selector on foot stops sim time while it is
  open, the watch stopped with it, and the second station picked from an open selector started from
  0. Verified in game: a tune-back lands at the station clock and swaps from an open selector resume.
- "Mute radio when..." (`Settings.reds`, `Restrictions.reds`): twelve switches in the Redscript
  Configuration Framework panel, one per `PocketRadioRestrictions` member, all on by default. Off
  lifts that restriction for a custom station only, through a wrap of `PocketRadio.HandleRestriction`
  that records the world's value and hands the pocket radio the switched one; a `TurnOn` wrap gives a
  vanilla station the restriction back. RCF is optional; without it the defaults apply. Combat and
  police heat, RadioXL 0.1.0's other two switches, are Wwise mix states on the radio buses and have no
  switch on the game's own radio route.
- The RadioXL glyph as the fallback icon (#18): `archive/pc/mod/RadioXL.archive` (DV's, one 256x256
  part) replaces the game's `no_station` part, and `UIIcon.RadioXL` is created at `OnApply` so a
  RadioXL 0.1.0 station yaml naming it stays valid. The vanilla atlas is still put back on a world
  device's logo widget for a vanilla station.
- `RadioXLAPI.RegisterStation(name)`: a RadioXL 0.1.0 station's script compiles and is logged rather
  than failing script validation for every redscript mod on the machine. The station is not created;
  adopting the old shape is #10.
- `r6/storages/RedscriptConfigFramework/RadioXL.card.json` and `RadioXL.docs.txt`: the RCF card and
  the in-game documentation, written for the framework.

## [0.2.0] - 2026-09-08

### Added
- `plugin/src/Json.hpp` and `plugin/src/Manifest.hpp`: the manifest is read by a strict JSON parser
  (RFC 8259 plus a byte-order mark; no comments, trailing commas or single quotes) and checked field
  by field. Every fault is logged as `<Mod>/station.json:<line>: <what>`, a syntax fault with its
  column too, and a manifest with one is skipped whole. Refused: `name` missing or outside
  `[A-Za-z0-9_]`, `tracks` missing, empty or not an array, a track with no `file`, a `speaker` the
  game does not have, `gain` not a number, `icon` without `atlas`. Logged and ignored: an unknown
  key, `gain` outside 0..1, `atlas` without `icon`. Replaces the substring scanner, which read a
  title containing `"file"` as the file and stopped an array at a `]` inside a title.
  `plugin/tests/ManifestTests.cpp` covers one case per rule, run by `ctest`. (#8)
- The vehicle receiver's next-station step is detoured. The block at `+0x68..+0x92` of the
  set-station function maps the current index through a dial-order switch on 0..13, adds one modulo
  14, and maps back through the inverse switch; both switches misanswer a custom index and the
  remainder is used, so neither erasing nor retuning the division works. The 42 bytes become a `jmp`
  to a 55-byte stub, allocated within rip-relative reach and made executable before any game byte
  is written, that calls the game's own switches for the fourteen, uses the slot index as the dial
  position past them, and takes the total as a 32-bit immediate. Eight more bytes verified first;
  the stub's call targets are read from the verified block. The dial order the switches encode is
  88.9 to 107.5. (#7)
- The plugin owns the dial order. `BuildDial` asks the game's switch for the fourteen's order at
  patch time, then inserts each custom station before the first station whose frequency is above
  the number at the front of its display name, against the fourteen vanilla frequencies in
  `kVanillaFrequency`; a station with no number goes last. The next-station stub reads two tables
  behind its code (`position[total]`, `dial[total]`) instead of calling the switches, and two new
  natives, `RadioXL_DialPosition` and `RadioXL_DialStation`, hand the same tables to `Dial.reds`:
  `GetRadioStationUIIndex` / `GetRadioStationByUIIndex` map every station through them, the
  cycling replacements keep vanilla's Samizdat skip anchored to the station rather than position
  5, and the vehicle list inserts a custom station at its dial position plus one. One order on
  every receiver. (#14)
- A `RadioStation` record's `index` is written as the station's dial position, not its enum
  value. The popup hands `record.Index()` to `SendRadioEvent`, which converts it through
  `GetRadioStationByUIIndex`, so the field is a UI index; vanilla carries 0 for 88.9 to 13 for
  107.5. The enum value equalled the position only while custom stations were appended, and the
  first station inserted inside the vanilla dial made every station above it play the content of
  the one below. (#14)
- The fourteen vanilla `RadioStation` records are rewritten to their new dial positions at load.
  Their `index` flats are fixed vanilla positions, so a custom station inserted below one left two
  records on one index: the popup lit both and selecting either played the station now holding
  that position. Measured with a station at 97.5: it and Body Heat both lit and both played it,
  Tool FM at 104.9 and Morro Rock did the same, and every vanilla station above played the
  station one position below. (#14)
- `tools/audioxl-feed-probe.patch`: the AudioXL measurement build behind #1, #3 and #15. Logs how the
  engine pulls from `AudioFeed::Execute`, the slot position at voice start and every retire.
- The engine's station NAME table is extended alongside the roster, so a custom station's label is
  a native localization key. Both of its readers reduce the index modulo 14; the division is erased.
- Station name and song titles registered as real localization entries, inserted into
  `onscreens.json` in sorted position under both hash widths.
- `RadioStation` and `UIIcon` TweakDB records built from the manifest in `ScriptableTweak.OnApply`,
  with the index the roster assigned. A station naming no icon gets the game's own `no_station` part.
- The vehicle radio list sorted by the frequency at the front of the display name.
- A per-station DJ through the manifest's `speaker`, defaulting to `None`.
- `plugin/src/Duration.hpp`: each track's length read from the audio file's headers at plugin load
  (MP3 via Xing/Info/VBRI or a frame walk, FLAC, Ogg Vorbis, WAV), exposed as
  `RadioXL_StationTrackDuration`. A track with no readable length is dropped and logged.

### Fixed
- Every rip-relative displacement the roster patch writes is range-checked before the cast, and the
  patch is abandoned if one does not fit. Each table is allocated within reach of one reader; the
  other reader of the same table was only in reach by the layout of the 2.31 image. (#11)
- World-device crackle: `mod_sfx_radio`'s stereo Broadcast Send is trimmed +2.9 dB where every
  vanilla station sits between -4 and +0.9 dB, so a master on 0 dBFS wrapped in the next 16-bit
  stage at world devices. First trimmed to 0.56 in the samples through `AudioXLNative.SetGain`,
  which corrects one receiver at a time: the stereo path needs -4.95 dB and the mono path -3.0.
  The level now comes off the samples entirely - see the routing bank below. New optional manifest
  key `gain` (0..1) and native `RadioXL_StationGain`. (#3)
- A station's level is a send trim, carried by `red4ext/plugins/RadioXL/radioxl_routing.bnk`
  and the `radioxl_radio` custom-sound type it defines: a byte clone of `mod_sfx_radio`'s Event, Play
  action and CAkSound, citing the bank's **own copies** of Radio Vexelstrom's two Broadcast Sends
  (-2.0 dB stereo, -5.0 dB mono) rather than `radio.bnk`'s objects, which a patch could move out
  from under it. Built by `tools/make_routing_bank.py`; every id is FNV-derived from an `radioxl_`
  string. `kDefaultGain` is 1.0, and the 0.56 applies only on the `mod_sfx_radio` fallback, where it
  multiplies a station's own gain rather than replacing it. Measured: 0 wrap artefacts in 550 s
  against 6,250 in 160 s, true peak -1.4 dBFS, a custom station inside the vanilla loudness spread.
  Confirmed in game: station switching stops the previous track, a vehicle takes over from the
  Radioport, a world device attenuates with distance, a wanted star ducks and combat stops the audio,
  the Music slider still moves it, WAV tracks play, and the bank survives loading a second save. (#17)
- The custom-sound TYPE gets its own row in the audio event table. AudioXL stores a row's type as the
  CName hash of the type string and the engine resolves that name through `eventsmetadata.json`, so
  a type absent from it plays nothing and reports nothing: the bank loaded, all 84 tracks registered,
  both stations built, every log line read as success, and every station was silent. (#17)
- Each track played twice on world devices: not the LAME gapless trim, which made the declared
  duration *exact* and so put every track on a coin flip. The engine re-posts a slot's track when the
  voice ends while that slot is still current, and the event row holds a 32-bit float whose step is
  15 microseconds at three minutes. Measured on two tracks four microseconds either side of their own
  length: the one rounded up played twice, the one rounded down played once. The row is now written
  at `duration - 0.5 s`, as vanilla does by seconds (`mus_radio_12_afterlife` declares 166 for 169.7).
  Verified over three boundaries at ratios 1.000 and 0.998. (#15)
- The station clock observer (`Clock.reds`) reads a station's position from
  `GetRadioStationCurrentTrackName`, which returns the track's **localization key** rather than its
  event name, resolved through `GetLocalizedTextByKey`. Restarts on every `Session/Ready` with a
  generation retiring the old chain, because a session's delay callbacks do not outlive it and the
  main menu is a session of its own. Instrument only; not for release. (#1)
- The station was silent on every receiver when its registration waited for AudioXL to report
  durations: the engine builds its station set while `cooked_metadata` loads, and a station added
  afterwards is never constructed. Event rows, membership, the station entry and the text are now all
  written as their resources load; only the AudioXL registration polls.
- AudioXL routing is `mod_sfx_radio`, the game's own radio route. An `axl_*` type is a 2D sound the
  radio system does not own.
- Natives are registered module-qualified (`RadioXL.RadioXL_*`); a bare registration fails
  script validation for every redscript mod on the machine.
- `RED4EXT_HEADER_ONLY` is no longer defined twice (the SDK's `Common.hpp` defines it).


## [0.1.0] - 2026-09-07

### Added
- RED4ext plugin that extends the engine's compiled radio station roster, so a custom station is a
  real station rather than a separate player.
- Vehicle receiver bound raised, so a custom station can be selected in a car.
- Station manifests discovered from `red4ext/plugins/RadioXL/stations/<Mod>/station.json`.
- Redscript service that registers each station's metadata entry and its membership of the station
  map at runtime.

### Notes
- Nothing vanilla is replaced. No archive ships, so station mods cannot conflict with each other.
