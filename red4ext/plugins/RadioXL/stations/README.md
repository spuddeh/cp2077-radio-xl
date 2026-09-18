# Station manifests

A station is one folder in here, named after the mod that ships it:

```text
red4ext/plugins/RadioXL/stations/<YourMod>/station.json
```

Nothing in this folder is shared, so any number of station mods install side by side.

**A station mod is a manifest, its audio files, and at most an icon archive.** No yaml, no
soundbank, no redscript. Everything else is built from the manifest at load.

## station.json

```json
{
  "name": "radio_station_20_yourstation",
  "frequency": 104.9,
  "displayName": "Your Station",
  "news": true,
  "tracks": [
    { "file": "audio/first.mp3",  "title": "Artist - First Song" },
    { "file": "audio/second.flac", "title": "Artist - Second Song" }
  ]
}
```

| Field | What it is |
| --- | --- |
| `name` | The station's own CName: letters, digits and underscores only. It must be unique across every installed station mod. |
| `frequency` | The station's place on the dial, as a number from 10 to 999: `104.9`. Required. See [The frequency and the name](#the-frequency-and-the-name). |
| `displayName` | The station's name, without the frequency. Required. The game shows it after the frequency: `104.9 Your Station`. |
| `news` | Optional. `true` lets the news reach the station: Stanley's bulletins and greetings, and N54 News. Defaults to `false`. See [News](#news). |
| `gain` | Optional. A level trim on every track, `0` to `4`. Defaults to `1`, the audio as recorded. See [Level](#level). |
| `icon` | Optional. An inkatlas part name, or an existing icon record such as `UIIcon.RadioHipHop`, which needs no archive. Defaults to the RadioXL glyph, which is also used when the named record does not exist. |
| `atlas` | Optional. The inkatlas holding that part, as a depot path (`mymod\gui\icons.inkatlas`, no `base\`). Required when `icon` is a part name; ignored when it is a record. |
| `tracks[].file` | An audio file, relative to this manifest's folder. |
| `tracks[].url` | In place of `file`: an `http://` or `https://` MP3 stream. A station with a `url` track has that one track only. See [A stream station](#a-stream-station). |
| `tracks[].title` | Optional. The song title, shown as written in the Radioport's radio popup. An untitled song plays everywhere a titled one does, and its title reads blank. |
| `tracks[].ident` | Optional. `true` marks a station ident, jingle or ad: it plays between songs and never shows a title. See [Idents](#idents). |

## News

A station with `"news": true` gets the game's news the same way its own stations do, and follows the
same rules:

- **A greeting** (Stanley's time-of-day lines) goes to the nearest news station, so the station you
  are listening to gets it. It starts straight away, stopping the current song.
- **A news bulletin** goes to one news station at a time: the last one, in the game's internal order,
  that has any radio nearby, switched on or not. It plays at that station's next song change. In the
  city a nearby station of the game's often takes it, so news on any station is hit and miss there,
  and dependable only away from other radios. The internal order comes from each station's `name`,
  not its frequency.

Leave `news` out and the station gets no DJ lines of any kind. Other DJs are not offered: Maximum
Mike's lines name Morro Rock and Ash's name Growl FM.

## Level

`gain` is the station's level trim, a multiplier on the samples: `0.5` is -6 dB, `2` is +6 dB, `4`
is +12 dB. RadioXL routes a station through the same level stages as the game's own stations, so
audio mastered like commercial music plays among them at `1`: the game's own radio files measure
-5 to -19 LUFS, most of them near -11, and a loud web stream at `1` read within the vanilla band on
the Radioport. A file that measures about -11 LUFS lands on the middle of the dial at `1`; a modern
master near -9 sits about 2 dB above it, and `0.8` brings it to the middle. Lower it for material
that plays louder than the vanilla stations; raise it for a quiet recording. A world radio sums a
track's two channels into one, so a wide mix plays a little quieter there than a narrow one.

**A gain above `1` must leave the loudest sample under full scale.** The samples are scaled as
16-bit integers and a value past the top wraps rather than clips, which is heard as crackle on the
loud beats. A file mastered to 0 dBFS, which is most modern music, cannot be raised at all; a file
peaking at -6 dBFS can take up to `2`. The station builder measures each file and keeps the value
inside that limit.

## The frequency and the name

**`frequency` decides where the station sits on the dial**: in the vehicle list, and in the order
every receiver steps through when you press next. A `93.7` lands between Night FM at 92.9 and
Samizdat at 95.2. Two stations on one frequency sit next to each other, the game's own first.

**The label is built from the two**, `104.9 Your Station`, the same way for every station, so the
name is the name alone. A manifest is refused, and the log says which line, when:

- `frequency` or `displayName` is missing, or `frequency` is outside 10 to 999;
- the name starts or ends with a number that reads as a frequency (`104.9 Your Station`,
  `Your Station 104.9`), or contains the frequency anywhere (`Your 104.9 Station`);
- the name is empty, has a space at either end or two in a row, or holds a control character.

A band's own number is fine: `30H!3 Radio` and `3 Doors Down FM` read. A manifest written for a
0.3.0 beta, with the number at the front of the name, is refused: move the number into
`frequency`. Opening the station on the builder page does that.

## When the manifest is wrong

**The file must be JSON.** No comments, no trailing commas, double quotes only, and a backslash in a
path written twice (`"mymod\\gui\\icons.inkatlas"`), or once as a forward slash.

**Every fault is logged with the file and the line, and the station is skipped whole.** A missing
`name`, a `tracks` that is not an array, `news` that is not `true` or `false`, a `gain` written as a
string, an `icon` part name with no `atlas` - each names its line in the RED4ext log:

```text
[RadioXL] YourMod/station.json:7: "gain" must be a number, not a string
[RadioXL] YourMod/station.json: skipped
```

A key the framework does not know is logged the same way and ignored, so a misspelt key shows up in
the log rather than quietly doing nothing; a misspelt required key also refuses the manifest as
missing.

## What the manifest does NOT carry

**No durations.** The framework reads each file's length from its headers at load, and the station
schedules the next track against that. A hand-written duration is a second place for it to be wrong.
A file whose length cannot be read is dropped, and the log names it.

**No event names.** They are derived as `<name>_01`, `<name>_02` and so on, so a filename with a
space or an accent in it never reaches an event name.

**No Wwise ids, no `index`, no TweakDB records.** A station's record index is its position on the
dial, which depends on which other station mods are installed and their frequencies - so no mod can
know its own in advance. The framework creates the records.

## The icon

A station with no `icon` shows the RadioXL glyph. To use one of the game's own station logos, set
`icon` to its record (`UIIcon.RadioHipHop` for The Dirge) and ship nothing.

For a logo of your own, the [station builder](https://spuddeh.github.io/cp2077-radio-xl/) does steps 2
to 6 below from an image: set Icon to From an image, choose the image, and Build .zip writes the texture,
atlas and archive and names them in the manifest. By hand in WolvenKit:

1. **Draw it white on a transparent background.** The Radioport tints the icon with the UI's colour,
   so a white logo comes out matching the game's own station logos, and a coloured one loses its
   colours: pink turns blue-violet and white lettering turns cyan. A coloured logo still reads well
   tinted, and PHONKWAVE Radio's is one. The game's logos are 240 to 400 px wide and 130 to 330 px
   tall, and 500 x 500 px is as large as one is worth making.
2. **Store black under every transparent pixel** (premultiplied alpha). Most editors export white
   there, and that shows in game as a white box.
3. **Import the PNG as an `.xbm`** in WolvenKit with `TEXG_Generic_UI`, `TRF_TrueColor`,
   `TCM_QualityColor`, no mip chain, not streamable, **premultiplied alpha** and **flipped
   vertically**. An import that is not flipped shows upside down.
4. **Make an `.inkatlas`** that points at the `.xbm` and has one part covering the logo. The part's
   rect selects the used area, so the texture can be padded to a multiple of 4.
5. **Pack both into your station's archive** under a folder of your own, with no `base\` prefix
   (`mystation\gui\icon.inkatlas`). WolvenKit warns about the missing prefix; the warning does not
   apply to a UI texture named by path.
6. **Name both in the manifest:** `"icon"` is the part name and `"atlas"` the `.inkatlas` path.

The [Custom in-game icons](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/custom-icons-and-ui/custom-in-game-icons)
guide on the modding wiki walks through the WolvenKit side of steps 3 and 4 with screenshots.

## The audio

Put the files beside the manifest. **AudioXL is what loads them**, so it is a hard requirement for
any station with files: WAV, MP3, OGG or FLAC. This framework does not decode, stream or mix
anything.

A track whose file AudioXL will not take is dropped, and the log names it. A station with no
playable tracks is skipped rather than registered empty.

## The order songs play in

The game picks a station's next song at random from the songs it has not played yet, and starts
over once every song has played. The order of `tracks` does not decide it, the same as for the
game's own stations.

## Idents

A track with `"ident": true` is a station ident, a jingle or an ad rather than a song:

```json
{ "file": "audio/station-id.mp3", "ident": true }
```

- **One plays after every third song**, between two songs, and adds its own length to the gap. It
  does not take a song's place in the rotation. With several idents, the game cycles through them in
  an order it picks at random when the station starts.
- **It shows no title**, the way the game's own station idents show none, so `title` is not needed.
- A station needs at least one song; a manifest where every track is an ident is refused. A stream
  track cannot be an ident.

## A stream station

A station can play a live MP3 stream instead of files:

```json
{
  "name": "radio_station_22_groovesalad",
  "frequency": 99.5,
  "displayName": "SomaFM Groove Salad",
  "tracks": [
    { "url": "https://ice1.somafm.com/groovesalad-128-mp3", "title": "SomaFM Groove Salad" }
  ]
}
```

- **One track.** The station plays that stream and nothing else; a manifest that mixes a `url` with
  other tracks is refused.
- **MP3 only**, over `http://` or `https://`. Shoutcast v1 servers are refused by AudioXL.
- **Live, not resumed.** Tuning back joins the stream wherever it is now. Sound starts a second or
  two after tuning in, while the stream buffers. If the server stops sending, the station reconnects
  on its own.
- **The title does not change** with the song the stream is playing; it shows `title`.

**Nothing plays until the player allows it.** AudioXL fetches nothing from the network unless
`red4ext\plugins\AudioXL\AudioXL.ini` allows both http and the stream's host:

```ini
[Network]
allowHttpConnections = true
allowedHost = ice1.somafm.com
```

A mod's files cannot change that setting, so a stream station's description must tell the player
which host to add. A server that redirects to another host needs that host listed too; AudioXL's log
names the host it refused, and RadioXL's log says when a stream was skipped because http is off.

**AudioXL creates `AudioXL.ini` on its first start**, with everything off, and an update leaves it
alone. Under Mod Organizer 2 the file is in Overwrite.

## Song titles and the station name

Both are plain text here, and both are registered as real localization entries at load. **Every
label the game shows is a key, not text** - the engine's station name table holds one, and so does
every radio track row - so the framework mints a key and registers the text against it. That is why
a custom station's name and titles resolve everywhere a vanilla one's do.

## Two things that will bite

**A station name that another installed mod already uses is skipped**, and the log says which mod
won. Prefix yours.

**A track whose file is missing plays nothing** and the station is shorter than the manifest says.
The log names every file AudioXL refused.
