# The audio path

The station side belongs to the engine. Sound is the one place a custom station leaves vanilla's
path, and that one difference explains most of what still sounds wrong.

## What a vanilla track is

`[M]` A Wwise `MusicSegment` with one `MusicTrack`, streamed from a `.wem` in the archives, parented
to the station's `MusicPlaylist` container in `radio.bnk` or `cp_music.bnk`. The segment inherits the
station's mix. The engine starts it at an offset worked out from the station clock. That is how a
vanilla station is mid-song when a receiver tunes back in.

Building that shape for new audio takes three things. A `.wem` (Wwise Vorbis, which only Wwise 2023.1
encodes; Wwise's built-in PCM codec is an unmeasured alternative). A generated bank (proven for single
tracks by <https://github.com/spuddeh/cp2077-hardest-to-be-growl-fm>; a multi-track probe bank played
only its first event). And an archive to carry the media, because streamed `.wem` files are fetched
from the archive depot and a loose file is never found.

## What the framework uses instead: `mod_sfx_radio`

`[M]` The engine has a **custom-sound registry** of 4096 rows. It is the path REDmod's `customSounds`
writes into. A row is a name, a type, PCM data and a format. Posting a row's name plays the **type's**
event, with the row's PCM fed through a Wwise Audio Input source. AudioXL fills that registry.

`mod_sfx_radio` is one of the game's own types, in the game's `mod` bank. In SoundDB its PLAY target
is sound object `818835100`, generator `AUDIO_INPUT`, with an RTPC on `volume_music`. REDmod
describes the type as "needs to be tuned to a broadcast channel". **It is CDPR's type for custom
audio that a radio receiver plays**, and it follows the Music slider, not SFX.

`[M]` On this type the radio system owns the sound. A car takes the station over from the Radioport,
a world device plays or stays silent by its own state, and switching stations stops the previous track.

### What the `mod_sfx_radio` object is, decoded from the banks

`[M]` `mod.bnk`, `radio.bnk` and `init.bnk` parsed with wwiser:

| | `mod_sfx_radio` (custom row) | a vanilla station playlist |
| --- | --- | --- |
| object | `CAkSound 529198484`, source Wwise Audio Input | `CAkMusicRanSeqCntr` (`375417660` Growl FM, `440066888`, ...) |
| insert effects | **Wwise Time Stretch** `758059012`, CPR Voice Broadcast Send `772871769` (mono), CPR Voice Broadcast Send `385769109` (stereo) | its own pair of Broadcast Send sharesets, one mono and one stereo (27 pairs in `radio.bnk`, one per playlist) |
| positioning | 3D, attenuation enabled, no attenuation object of its own | same bits |
| bus | `918052088` -> `1151059771` (Parametric EQ) -> `2996874604` -> `1836253337` -> Master | `666212655` (Parametric EQ) -> `music` -> Master |
| sliders | RTPC `volume_music` on the sound: the Music slider, which is the game's own score and touches no radio | the `music` bus in the bank; in the settings menu a station follows Vehicle Radio in a car, Radioport on foot and SFX through a world device, never Music. `radioxl_radio` measures the same `[M]` |
| base props | Volume -96 dB, GameAuxSendVolume -96 dB | none |

### The vanilla rule: the dry path is muted and the send is the station

`[M]` **Every one of the 27 station playlists in `radio.bnk`, HKGN's `160668006` among them, carries `Volume -96 dB` on its own dry
output and two CPR Voice Broadcast Send inserts, without exception.** A station is not a sound with a
send on the side. The send is the only way it is heard at all. So the send trim is not a correction
on top of a level. It *is* the station's level, and matching a station means matching a send trim.

Both dials are narrow. The whole roster spans 4.9 dB on the stereo send and 2 dB on the mono one.

To read the table back after a game patch: dump `radio.bnk` with wwiser, take every
`CAkMusicRanSeqCntr` as a station, read its `OverrideBusId` and its two `NodeInitialFxParams` ids,
resolve each id to a `CAkFxCustom` **or** a `CAkFxShareSet` in the same bank, and take the graph
point at `From = 0.0` on its RTPC for `1631578750`. `fxID 0x000529A3` is the stereo send and
`0x000329A3` the mono one.

`[M]` This matters for anything that adds a track by cloning bank objects. Measured on
<https://github.com/spuddeh/cp2077-hardest-to-be-growl-fm>: **a segment does not inherit that routing
from a parent playlist in another bank.** It plays dry, at the source file's own level, about 15 dB
hot. It holds its level with distance until the emitter's range cuts it at 45 to 50 m. Turning the
device off still stops it, so the station schedules it correctly and only the audio is off the chain,
and every script-side check passes. The node has to carry the station's two send effects, its bus
and its -96 dB Volume itself.

The **CPR Voice Broadcast Send** is CDPR's own plugin, and it is what "tuned to a broadcast channel"
means. Every station has its **own pair** of send sharesets, and so does `mod_sfx_radio`.
The stereo send (`338339`) takes `radio_broadcast_channel_left` and `_right` (defaults 58) and feeds
the Radioport and vehicle radios, which play it as straight stereo. The mono send (`207267`) takes the
RTPC `radio_broadcast_channel` (default 8) and feeds world devices, which sum the two channels into
one. `[M]` A routing bank whose copy of the stereo send sat 12 dB low dropped a custom station 10 dB
on the Radioport and about 9 in a car, and left a world radio unchanged. Both sends carry a curve on `radio_broadcast_mute` (`1631578750`, default
0 = unmuted, 1 = -96 dB), and **the curve's value at 0 is a per-station level trim**. wwiser stores a
dB-scaled curve point as `10^(dB/20) - 1`. Decoded that way, every vanilla trim is a whole or half dB.
The four attenuations in `mod.bnk` belong to the occlusion, room, street and city sounds, not to
this one.

`[M]` **The trims are the difference, and they are the crackle** (issue
[#3](https://github.com/spuddeh/cp2077-radio-xl/issues/3)):

| sound | stereo send (Radioport, vehicles) | mono send (world devices) |
| --- | --- | --- |
| `mod_sfx_radio` | **+2.9 dB** | -2.0 dB |
| hottest vanilla station | +0.9 dB | -5.0 dB |
| Growl FM | -4.0 dB | -5.0 dB |
| quietest vanilla station | -4.0 dB | -7.0 dB |

Samizdat Radio's two playlists sit on a different bus, and two playlists share one mono send
shareset rather than owning one each. So reading only the `CAkFxCustom` objects and not the `CAkFxShareSet` ones misses part of the table.

dr_mp3 decodes to int16 and clamps, so a modern master reaches the send already at 0 dBFS. A world
device hears the mono send, which `mod_sfx_radio` trims to -2.0 dB where every vanilla station sits
at -5 to -7, and it sums the track's two channels into one. A full-scale master's correlated peaks
then land past full scale at the next 16-bit stage and wrap. In the recording, the artefact is a bass
peak whose samples flip sign in runs of one to three while keeping their magnitude. On 2.31 we counted
6,250 half-scale jumps in 160 s of *Afterlife* on Tool FM, against 4 in the same song on Growl FM at
the same device, and 95 % of them where the source peaks above -2.1 dBFS. 2.5's `mod.bnk` is
byte-identical to 2.31's, so the trims behind it are unchanged. The Radioport hears the stereo send,
hotter still at +2.9 dB, but it keeps the two channels apart, so a clamped source stays under the rail
there. `[M]` for which receiver hears which send and for the summing; `[I]` for the sum being what
tips a device over.

The **Time Stretch** is the other structural difference, and it is not the crackle. Its RTPC
(`1400903616`, name unresolved, default 1) maps 0 to 200 % and 1 or more to 100 %. `[M]` Wwise 2023.1
Help says 100 % is no stretch, and the artefact has no grain period. `[I]` It exists so a custom
sound slows with the world, since a bus-level pitch shift cannot reach an Audio Input source.

**One sample gain cannot meet vanilla on both receivers.** Bringing `mod_sfx_radio` to mid-dial takes
-4.95 dB on the stereo send and -3.0 on the mono one. One figure applied to the audio puts the
Radioport mid-dial and leaves world devices at the bottom of the vanilla range. Editing two curve points in
`mod.bnk` is exact on both, but it replaces a vanilla file and moves every REDmod custom station
with it.

`[M]` **The framework takes a third route: its own custom-sound type, in its own bank.** A type is
whatever a loaded bank defines. `radioxl_routing.bnk` clones `mod_sfx_radio`'s Event, Play action and
CAkSound, and cites its own copies of a vanilla station's two Broadcast Sends instead of that object's.
The level then comes from the same mechanism every vanilla station uses, on both receivers, and no
game file is replaced. Measured on 2.31 after the change: **0 wrap artefacts in 550 s** where the same
passage gave 6,250 in 160 s, true peak -1.4 dBFS, and a custom station inside the vanilla spread
rather than above it.

The sends are **copied rather than cited**. A cited id that a patch or another mod moves does not
raise an error. The effect is just absent, the sound leaves the broadcast chain, and it plays dry
about 15 dB hot at every distance while every script-side check still passes. The cost is that a
retuned vanilla dial no longer moves this one. Re-derive the trims after a game patch and rebuild.

`[M]` **The `mod_sfx_radio` fallback is the one place the framework scales samples.** A track on
`radioxl_radio` is handed to AudioXL at the manifest's own gain, which defaults to 1. If the routing
bank fails to load, every station falls to `mod_sfx_radio`, and the framework multiplies each track's
gain by 0.56 (-5 dB, `RadioXLFallbackTrim`). That puts the Radioport send at -2.1 dB and the
world-device send at -7.0, both inside the vanilla range. 0.56 gave 0 wraps in 70 s; 0.63 (-4 dB) let
one full-scale peak through in 65 s.

### A receiver decides what it hears; the source only broadcasts

`[M]` **A world device does not stop the station's voice when it is switched off or retuned. It stops
listening.** `radio.swift`, `speaker.swift`, `jukebox.swift` and `lift.swift` all set the device's
own `radio_station` switch, to the station or to `station_none`. `radio.swift` also starts or
break-loops its `radio_idle` effect. Nothing there reaches the voice. That is why a vanilla station is mid-song when a receiver tunes back
in. It is also why a car taking the station over from the Radioport is a choice between receivers,
not a handover of one sound.

So a bank object does not decide whether the radio system controls the sound. It decides whether the
sound is on the broadcast chain at all.

### The `axl_*` types are not an alternative

`[M]` AudioXL's own routing bank defines `axl_voice_2d`, `axl_music_2d`, `axl_radio_2d`, `axl_sfx_2d`,
`axl_master_2d` and `axl_radioport_2d`. On `axl_radio_2d` the Radioport and a car play at once, a car
cannot take over, and a world device only seems to work because the audio is heard everywhere. A
station on those types is a parallel player, not a station.

`[M]` **The cause is the missing chain, not positioning.** Five of the six carry
`uBitsPositioning 3` and `uBits3d 8`, the same bits `mod_sfx_radio` carries; only `axl_radioport_2d`
is 2D. Against `mod_sfx_radio`, `axl_radio_2d` (`4061179639`) differs in exactly two ways that
matter. It carries **no effects at all**, so neither Broadcast Send. And it has **no `Volume`
property**, so its dry output is not muted. It is heard directly on its own bus, and no receiver
decides anything about it.

So for anything built on this path: **a custom sound keeps the receivers' behaviour for as long as it
keeps the two sends and the -96 dB dry mute.** Changing which send objects it cites changes its level
and nothing else.

## What AudioXL's renderer does, and does not do

From its source, all `[M]`:

1. **It fills the engine's registry** through the engine's own register function, after
   `EnsureEnabled`. That needs the engine's audio system pointer, which is null until the `AudioInit`
   hook fires. Registrations before that are queued.
2. **It replaces the engine's renderer.** `EnsureEnabled` calls the engine's `SetCallbacks` with
   AudioXL's `Execute` and `Format`. From then on every registry row, REDmod's included, is rendered
   by AudioXL's code.
3. **The render is a copy.** 16-bit frames are memcpy'd into Wwise's buffer at the file's own sample
   rate. Bit-exact at gain 1. Wwise resamples.
4. **It seeks only where told.** `AudioFeed::Start` sets the voice position to the row's `start`
   (default 0). The engine keeps a per-slot position field. AudioXL writes it every buffer and never
   reads it. From AudioXL 0.3.0, `PlayFrom(name, seconds)` sets a one-shot start for the next voice
   on a row, and `Position(name)` reads the playing voice's position. The framework's plugin arms
   `PlayFrom` with the engine's station clock (`plugin/src/Clock.hpp`).
5. **A compressed track of 45 s or more streams from disk** from AudioXL 0.3.0. Up to AudioXL 0.9.4,
   shorter ones, and any row with a loop, a start/end region or a rate, are decoded in full at
   registration. From 0.10.0 a streamed row loops, trims and takes a rate (AudioXL's docs card).
   `stream: true` forces streaming. Before 0.3.0 every MP3, OGG and FLAC was resident PCM: eleven
   album tracks came to about 750 MB.
6. **Banks load from memory** through the engine's `LoadBankMemoryCopy`.
7. **A row can be an http or https MP3 stream** from AudioXL 0.4.0. It is registered with
   `RegisterSound` and the URL as its path, and fetched only when the player's `AudioXL.ini` allows
   http and the host. A URL row plays forward only: no `PlayFrom`, and `Duration` is 0.

## A stream row

**How long a URL row takes to appear varies, and no call into AudioXL is known to be needed.**
`RegisterSound` returns true at once and the stream is probed on a worker thread. `[M]` In one
session a row was still missing 30 s after the session began and present minutes later. In another,
with a build that called nothing, both stream rows existed 13 s after boot. `Audio.reds` calls
`Poll` and `PendingRemote` from the level-trim retry. That does no harm and is not shown to matter.
`[I]` A station tuned before its row exists may stay silent until it is tuned again, because the
engine posts the track once for its slot. Unmeasured.

`[M]` **Tune-back reconnects.** `Position` read 15.9 s before a 60 s tune-away and 5.9 s after. That
is a new voice on a new connection, not the frozen voice a file row keeps
([#26](https://github.com/spuddeh/cp2077-radio-xl/issues/26)).

`[M]` **A stream needs no special gain on the framework's type.** Measured on the Radioport with
`tools/measure-loudness.py`: vanilla stations -16.3 to -19.6 LUFS, a future funk stream at gain 1
-17.8, an ambient one -22.6. AudioXL's own advice of 0.2 to 0.4 is for its `axl_*` types.

## The symptoms, mapped

| Heard | Cause | Mark |
| --- | --- | --- |
| Right song after tuning back, from 0:00 | the engine picked the track from its clock; the renderer starts at 0, and the engine hands no offset | `[M]` both sides; the framework's plugin hands AudioXL the offset from the station clock ([#1](https://github.com/spuddeh/cp2077-radio-xl/issues/1)) |
| Each track plays twice on a world device | declared duration longer than the decoded length by the LAME gapless trim; the engine re-posts the slot | `[M]` fixed and verified over three boundaries ([#15](https://github.com/spuddeh/cp2077-radio-xl/issues/15)) |
| World devices quieter; car and Radioport fine | the row's attenuation reach: at `RegisterSoundEx`'s `distance` 0 a station falls off with distance about twice as fast as a vanilla one | `[M]` fixed by `distance` 30 on every row (`Audio.reds`): world devices at vanilla loudness, car and Radioport unchanged ([#2](https://github.com/spuddeh/cp2077-radio-xl/issues/2)) |
| Static and crackle, at devices only | `mod_sfx_radio`'s mono send, which world devices hear, is trimmed -2.0 dB, 3 to 5 dB above every vanilla station; a device sums the two channels, and a source clamped at 0 dBFS wraps in the next 16-bit stage | `[M]` fixed by the framework's own type ([#3](https://github.com/spuddeh/cp2077-radio-xl/issues/3), [#17](https://github.com/spuddeh/cp2077-radio-xl/issues/17)) |
| Hundreds of MB of RAM | decode at registration, before AudioXL 0.3.0 streamed long tracks | `[M]` ([#4](https://github.com/spuddeh/cp2077-radio-xl/issues/4)) |

## The engine never hands a start offset on this path

`[M]` A probe build of AudioXL (`tools/audioxl-feed-probe.patch`) logs the engine's per-slot position
at `AudioFeed::Start`, before the first render overwrites it. Seven voice starts, a mid-song tune-in
among them: 0 every time. The engine writes 0 into the slot when it posts, so no renderer can resume
by reading that field. **Resume is the framework's plugin** (`plugin/src/Clock.hpp`). Four times a
second, from its game-state update, it reads the engine's own station clock (`+0x14c` on the station
object, the seconds since the station's current slot began, at the same offset on 2.5 and 2.31) and
arms the station's current row with `PlayFrom`. A URL row is left out, because it refuses `PlayFrom`.
The only other route is the vanilla shape above, with its three unmeasured steps.

## The engine posts the next track when the voice ends, and it posts the slot its clock names

`[M]` Same probe: the next voice starts about 30 ms after the previous one retires at its last frame,
never on a clock boundary. The track it posts is whatever slot the station clock is in at that
instant. Declare a longer duration and the voice ends inside its own slot, the slot is still current,
and the engine posts the same track again from 0:00.

`[M]` **So the declared duration must sit BELOW the decoded length, and an exact one does not.** A
duration at or above the real length loses that race about half the time. The event row holds a
32-bit float whose step is 15 microseconds at three minutes, and the rounding decides the sign. Two
Tool FM tracks four microseconds either side of their own length, from the file lengths and one
boundary-to-boundary observation:

| track | decoded | declared | difference | heard |
| --- | --- | --- | --- | --- |
| Lost Keys | 226.324917 | 226.324921 | +4 us | plays twice, slot held 453.19 s |
| Afterlife | 169.721333 | 169.721329 | -4 us | plays once |

The repeat is a full second play-through, not a fragment, so a slot reads as exactly twice its
track. It does not show as a slot boundary, because a re-posted slot reports the same track.

`[M]` **Vanilla does not run that race.** `mus_radio_12_afterlife` declares
`minDuration = maxDuration = 166` for 169.72 s of audio, and every vanilla radio row carries seconds
of margin. On a station that under-declares, the slot ends first and the engine waits for the voice.

So subtracting the LAME gapless tag is necessary but not enough. The tag is delay 576 and padding
717 to 1681 frames, which dr_mp3 trims, and which leaves a raw frame count 27 to 47 ms long.
Accuracy is the wrong target. The row is written at `duration - 0.5 s` (`RadioXLScheduleMargin`) to
stay clear of the float step, and of the free-running clock passing a slot over.

## Events, and why the row alone is not enough

`[M]` `GameInstance.GetAudioSystem().Play(name)` resolves a `CName` through `eventsmetadata.json`. An
event with no row there cannot be posted by name, and it fails without a word. The framework hands
AudioXL one row per track from `OnLoad`, and AudioXL adds it to the engine's table when the engine
reads that file: `redId` the event name, `wwiseId` from AudioXL (FNV-1 32-bit of the lowercased
name), `minDuration` and `maxDuration` the track's length less the 0.5 s margin. The length is the
plugin's, read from the file's headers, because the engine reads the table at boot, before AudioXL
can decode anything. A registry row
alone plays from a receiver, but the station schedules against the event row, so both exist.

`[M]` **The custom-sound TYPE needs a row of its own, on the same rule.** AudioXL stores a row's type
as the CName hash of the type string, and the engine resolves that name through this table to reach
the Wwise event. A type missing from it plays nothing and reports nothing. The bank loads, every track
registers, every station is built, every log line reads as success, and there is silence. AudioXL
registers its own six `axl_*` types here too.

`[M]` **A bank load returning 1 does not mean the bank is live.** AudioXL returns 1 both for a load
and for a bank queued because the engine's audio system is not up yet, which is the usual case at
boot. Only a later failure is reported, so 1 at registration time is a promise, not a fact.
