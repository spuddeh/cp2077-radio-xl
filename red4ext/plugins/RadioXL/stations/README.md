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
  "displayName": "104.9 Your Station",
  "speaker": "Ash",
  "tracks": [
    { "file": "audio/first.mp3",  "title": "Artist - First Song" },
    { "file": "audio/second.flac", "title": "Artist - Second Song" }
  ]
}
```

| Field | What it is |
| --- | --- |
| `name` | The station's own CName: letters, digits and underscores only. It must be unique across every installed station mod. |
| `displayName` | The label the game shows. Put the frequency at the front. |
| `speaker` | Optional. The station's DJ. Defaults to `None`. |
| `gain` | Optional. A level trim on every track, `0` to `1`. Defaults to `1`, the audio as recorded. |
| `shuffle` | Optional. `true`: this station plays its tracks in a new random order each time the game starts, whatever the player's Shuffle setting. `false`: this station is never shuffled, even when the player's setting says every station. Left out: the player's setting decides. |
| `icon` | Optional. An inkatlas part name, or an existing icon record such as `UIIcon.RadioHipHop`, which needs no archive. Defaults to the RadioXL glyph, which is also used when the named record does not exist. |
| `atlas` | Optional. The inkatlas holding that part, as a depot path (`mymod\gui\icons.inkatlas`, no `base\`). Required when `icon` is a part name; ignored when it is a record. |
| `tracks[].file` | An audio file, relative to this manifest's folder. |
| `tracks[].url` | In place of `file`: an `http://` or `https://` MP3 stream. A station with a `url` track has that one track only. See [A stream station](#a-stream-station). |
| `tracks[].title` | Optional. The song title, shown as written. |
| `tracks[].ident` | Optional. `true` marks a station ident, jingle or ad: it plays between songs and never shows a title. See [Idents](#idents). |

`speaker` names one of `Stanley`, `MaximumMike`, `Ash`, `Kurtz` or `PoliceDispatch`. Every vanilla
station names one; a station without one plays.

`gain` is the station's level trim. RadioXL routes a station through the same level stages as the
game's own stations, so audio mastered like commercial music plays among them at `1`: measured on
the Radioport, the vanilla stations read -16 to -20 LUFS and a loud web stream at `1` read -18.
Lower it for material that plays louder than the vanilla stations. It cannot go above `1`, so a
quiet recording stays quiet.

**The frequency lives at the front of `displayName`**, because the game has no field for it. The
number decides where the station sits on the dial: in the vehicle list, and in the order every
receiver steps through when you press next. A station whose display name does not start with a
number goes after every station that has one.

## When the manifest is wrong

**The file must be JSON.** No comments, no trailing commas, double quotes only, and a backslash in a
path written twice (`"mymod\\gui\\icons.inkatlas"`), or once as a forward slash.

**Every fault is logged with the file and the line, and the station is skipped whole.** A missing
`name`, a `tracks` that is not an array, a `speaker` the game does not have, a `gain` written as a
string, an `icon` part name with no `atlas` - each names its line in the RED4ext log:

```text
[RadioXL] YourMod/station.json:7: "speaker" must be one of None, Stanley, MaximumMike, Ash, Kurtz, PoliceDispatch: "Stanly"
[RadioXL] YourMod/station.json: skipped
```

A key the framework does not know is logged the same way and ignored, so a typo in `displayName`
shows up rather than quietly leaving the station nameless.

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

Import the texture the way the game's own station atlas is built, or it renders wrong:
`TEXG_Generic_UI`, `TRF_TrueColor`, `TCM_QualityColor`, no mip chain, not streamable, **alpha
premultiplied** and **vertically flipped on import**. The game's UI textures store black under every
transparent pixel; a PNG with white there shows as a white box, and an unflipped import shows upside
down. In WolvenKit both are import switches. The atlas part's UV rect selects the used region, so the
sheet can be padded to a multiple of 4.

## The audio

Put the files beside the manifest. **AudioXL is what loads them**, so it is a hard requirement for
any station with files: WAV, MP3, OGG or FLAC. This framework does not decode, stream or mix
anything.

A track whose file AudioXL will not take is dropped, and the log names it. A station with no
playable tracks is skipped rather than registered empty.

## Idents

A track with `"ident": true` is a station ident, a jingle or an ad rather than a song:

```json
{ "file": "audio/station-id.mp3", "ident": true }
```

- **One plays after every third song**, between two songs, and adds its own length to the gap. It
  does not take a song's place in the rotation. With several idents, the game cycles through them in
  an order it picks at random when the station starts.
- **It shows no title**, the way the game's own station idents show none, so `title` is not needed.
- **Shuffle never moves it**, because it is not in the song order.
- A station needs at least one song; a manifest where every track is an ident is refused. A stream
  track cannot be an ident.

## A stream station

A station can play a live MP3 stream instead of files:

```json
{
  "name": "radio_station_22_groovesalad",
  "displayName": "99.5 SomaFM Groove Salad",
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

**Updating AudioXL replaces `AudioXL.ini`**, which turns streaming off again until the lines are
added back.

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
