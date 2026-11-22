# Station reference

A station is one folder in here, named after your mod:

```text
red4ext/plugins/RadioXL/stations/<YourMod>/station.json
```

Each station has its own folder, so any number of station mods install side by side. A station mod is a
`station.json`, its audio files, and at most an archive for its icon. No yaml, no sound bank, no scripts.

The [station builder](https://spuddeh.github.io/cp2077-radio-xl/) writes all of this for you. This page is for
writing or checking a station by hand.

## station.json

```json
{
  "name": "radio_station_yourstation",
  "frequency": 104.9,
  "displayName": "Your Station",
  "news": true,
  "tracks": [
    { "file": "audio/first.mp3",  "title": "Artist - First Song" },
    { "file": "audio/second.flac", "title": "Artist - Second Song", "gain": 0.8 },
    { "file": "audio/station-id.mp3", "ident": true }
  ]
}
```

| Field | Needed | What it does |
| --- | --- | --- |
| `name` | Required | The station's ID: letters, digits and underscores. It has to be different from every other installed station, so give it your own prefix. |
| `frequency` | Required | Where the station sits on the dial, from 10 to 999: `104.9`. See [The frequency and the name](#the-frequency-and-the-name). |
| `displayName` | Required | The station's name, without the frequency. The game shows them together: `104.9 Your Station`. |
| `tracks` | Required | The songs, idents or stream, as a list. It can't be empty. |
| `tracks[].file` | | An audio file, relative to this folder. |
| `tracks[].url` | | Instead of `file`: an `http://` or `https://` MP3 stream, as the station's only track. See [A stream station](#a-stream-station). |
| `tracks[].title` | Optional | The song name in the radio popup. A song with no title still plays, and its name shows blank. |
| `tracks[].ident` | Optional | `true` marks a station ident, jingle or ad. See [Idents](#idents). |
| `tracks[].gain` | Optional | This track's level, `0` to `4`, `1` by default. See [Level](#level). |
| `gain` | Optional | One level for the whole station, `0` to `4`, `1` by default, on top of each track's own. |
| `icon` | Optional | An inkatlas part name, or one of the game's own icon records, such as `UIIcon.RadioHipHop`. Leave it out for the RadioXL glyph, which also shows if the record doesn't exist. See [The icon](#the-icon). |
| `atlas` | Optional | The inkatlas holding that part, as a path with no `base\`: `mymod\gui\icons.inkatlas`. Needed when `icon` is a part name. |
| `news` | Optional | `true` lets Stanley's bulletins and greetings and N54 News reach the station. Off by default. See [News](#news). |
| `showFrequency` | Optional | `false` shows the name alone as the station's label. The frequency still places it on the dial. |
| `addUnlistedFiles` | Optional | `true` adds audio files you drop in the folder at each launch, and drops listed ones that are gone. See [Adding songs by dropping them in](#adding-songs-by-dropping-them-in). |
| `description` | Optional | A few sentences about the station, up to 1000 characters, for other mods to read. RadioXL doesn't show it. One text, or one per language: `{ "en-us": "...", "de-de": "..." }`. A missing language gets the plain text, or else `en-us`. |
| `extensions` | Optional | Data for another mod, under that mod's name: `{ "SomeMod": { ... } }`. RadioXL passes it on as written and reads none of it. |

## When something is wrong

**It has to be valid JSON.** No comments, no trailing commas, double quotes only, and backslashes in a path
written twice (`"mymod\\gui\\icons.inkatlas"`) or as forward slashes.

**A station with a mistake is skipped, and RadioXL's log names the file and the line:**

```text
[RadioXL] YourMod/station.json:7: "gain" must be a number, not a string
[RadioXL] YourMod/station.json: skipped
```

The log is `red4ext\logs\radioxl-<date>.log`. A key RadioXL doesn't know is logged and ignored, so a typo in an
optional key shows up there. A typo in a required key skips the station as missing that key.

**A station name another installed mod already uses is skipped**, and the log says which mod has it.

**A track whose file is missing is left out**, so the station is shorter than its `tracks`. The log names each one.

## The frequency and the name

The frequency places the station on the dial, in every radio's station list and in the order next and previous
step through. `93.7` lands between Night FM at 92.9 and Samizdat at 95.2. Two stations on the same frequency sit
next to each other, the game's own first.

The game's stations use 88.9, 89.3, 89.7, 91.9, 92.9, 95.2, 96.1, 98.7, 99.9, 101.9, 102.0, 103.5, 106.9, 107.3
and 107.5.

The label is always built from the two, `104.9 Your Station`, so put only the name in `displayName`. RadioXL skips
the station when:

- `frequency` or `displayName` is missing, or `frequency` is outside 10 to 999;
- the name starts or ends with a number that reads as a frequency (`104.9 Your Station`, `Your Station 104.9`),
  or has the frequency anywhere in it (`Your 104.9 Station`);
- the name is empty, has a space at either end or two spaces in a row, or has a control character in it.

A band's own number is fine: `30H!3 Radio` and `3 Doors Down FM` both work.

## Level

A track plays at its file's own loudness, times the track's `gain`, times the station's `gain`. Each runs from
`0` to `4`: `0.5` is -6 dB, `2` is +6 dB, `4` is +12 dB, and `1` changes nothing.

A file around -11 LUFS lands in the middle of the game's own stations at `1`. The game's radio files measure -5 to
-19 LUFS, most of them near -11. A modern master near -9 LUFS sits about 2 dB louder, and `0.8` brings it down.
A world radio plays both channels as one, so a wide mix is a little quieter there.

**The station builder can measure each file and set its `gain` for you** (Auto level). A stream can't be measured
ahead of time, so set its level by hand.

**A gain above `1` has to leave the loudest part under full scale, or it crackles.** The samples wrap rather than
clip, so you hear it on the loud beats. A file mastered to 0 dBFS, which is most modern music, can't be raised at
all. A file peaking at -6 dBFS can go up to `2`. This applies to the two gains multiplied together. The builder
keeps its own levels inside that limit. A value you type yourself isn't checked.

## News

With `"news": true` a station gets the game's news under the same rules as the game's own stations:

- **Stanley's greetings** go to the nearest news station, so the one you're listening to gets them. A greeting
  starts straight away and stops the current song.
- **A news bulletin** goes to one news station at a time, picked by the game from every news station with a radio
  nearby, switched on or not. It plays at that station's next song change. In the city a nearby game station often
  gets it, so news is only dependable away from other radios.

Without `news`, the station gets no DJ lines at all. Maximum Mike and Ash aren't offered, since their lines name
their own stations.

## The audio

Put the files in the station's folder. AudioXL plays them, so it's required for any station with files. Songs can be
**MP3, OGG, FLAC, or WAV as 16-bit PCM**.

Any other WAV is left out at load, and RadioXL's log names it and says why. That covers 24-bit (it plays silence),
32-bit float, a WAV with format tag 65534 (ffmpeg writes those above 48 kHz), one with a chunk before `fmt` or an
odd-sized chunk before `data`, and one over 500 MB. The station builder converts a WAV to 16-bit for you.

RadioXL reads each song's length from the file itself. A file whose length can't be read is left out, and the log
names it. A station with nothing left to play is skipped.

Each track's ID comes from its file name, so adding, removing or reordering songs keeps every other song and the
player's settings for it as they were. Renaming a file makes it a new song. The same file listed twice is left out
the second time.

## The order songs play in

The game picks the next song at random from the ones it hasn't played yet, and starts over once every song has
played, the same as for its own stations. The order of `tracks` doesn't matter.

## Idents

A track with `"ident": true` is a station ident, jingle or ad:

```json
{ "file": "audio/station-id.mp3", "ident": true }
```

- **One plays after every third song**, between two songs. It doesn't take a song's place. With several idents, the
  game cycles through them in a random order it picks when the station starts.
- **It shows no title**, like the game's own idents, so it doesn't need one.
- A station needs at least one song, so a station where every track is an ident is skipped. A stream can't be an
  ident.

## Adding songs by dropping them in

With `"addUnlistedFiles": true`, a WAV, MP3, OGG or FLAC file you put anywhere in the station's folder is added to
`tracks` the next time the game starts. Its title comes from the file name (folder and extension dropped, `_` read
as a space), at gain `1`. A listed file that's gone is taken off. The log names every file added or removed, and
`station.json` is rewritten with the change, everything else kept as it was.

RadioXL can't measure loudness, so open the station in the builder to level songs added this way. Idents are never
guessed: mark one with `"ident": true` yourself. A stream station is left alone.

Leave it off for a station you publish, so a stray file on a player's machine never turns into a song.

Every song's length is remembered in `red4ext/plugins/RadioXL/cache.json`, and read again only when the file's size
or date changes. If a song plays with the wrong length after you replaced its file, delete `cache.json` and launch
again.

## The icon

With no `icon`, the station shows the RadioXL glyph. To use one of the game's own station logos, set `icon` to its
record (`UIIcon.RadioHipHop` for The Dirge) and ship nothing else.

For your own logo, the [station builder](https://spuddeh.github.io/cp2077-radio-xl/) does steps 2 to 6 from a picture:
set Icon to From an image, choose the image, and Build .zip makes the texture, the atlas and the archive. By hand in
WolvenKit:

1. **Draw it white on a transparent background.** The Radioport tints the icon with the UI colour, so a white logo
   matches the game's own, and a coloured one changes colour: pink turns blue-violet and white lettering turns cyan.
   The game's logos are 240 to 400 px wide and 130 to 330 px tall. Keep it to 500 x 500 px or smaller.
2. **Store black under every transparent pixel** (premultiplied alpha). Most editors save white there, and that shows
   up in game as a white box.
3. **Import the PNG as an `.xbm`** with `TEXG_Generic_UI`, `TRF_TrueColor`, `TCM_QualityColor`, no mip chain, not
   streamable, **premultiplied alpha** and **flipped vertically**. If it isn't flipped, it shows upside down.
4. **Make an `.inkatlas`** pointing at the `.xbm`, with one part covering the logo. The part only covers what it
   selects, so you can pad the texture to a multiple of 4.
5. **Pack both into your archive** under a folder of your own, with no `base\` at the front
   (`mystation\gui\icon.inkatlas`). WolvenKit warns about the missing `base\`; you can ignore that for a UI
   texture.
6. **Put both in `station.json`:** `"icon"` is the part name and `"atlas"` is the `.inkatlas` path.

The [Custom in-game icons](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/custom-icons-and-ui/custom-in-game-icons)
guide on the modding wiki shows steps 3 and 4 with screenshots.

## A stream station

A station can play a live MP3 stream instead of files:

```json
{
  "name": "radio_station_groovesalad",
  "frequency": 99.5,
  "displayName": "SomaFM Groove Salad",
  "tracks": [
    { "url": "https://ice1.somafm.com/groovesalad-128-mp3", "title": "SomaFM Groove Salad" }
  ]
}
```

- **One track only.** A station that mixes a `url` with other tracks is skipped.
- **MP3 only**, over `http://` or `https://`. AudioXL doesn't play Shoutcast v1 servers.
- **Live.** Tuning back joins the stream wherever it is now, after a second or two of buffering. If the server stops
  sending, the station reconnects by itself.
- **The title stays the same.** It shows `title`, not the song the stream is playing.

**Nothing plays until the player allows it.** AudioXL doesn't go online unless
`red4ext\plugins\AudioXL\AudioXL.ini` allows http and the stream's host:

```ini
[Network]
allowHttpConnections = true
allowedHost = ice1.somafm.com
```

Your mod can't change that file, so tell players in your mod's description which host to add. A server that
redirects to another host needs that host too. AudioXL's log names any host it refused, and RadioXL's log says when
a stream was skipped because http is off.

AudioXL creates `AudioXL.ini` the first time it starts, with everything off, and updates leave it alone. Under Mod
Organizer 2 the file is in Overwrite.

## Song titles and the station name

Write both as plain text. RadioXL registers them with the game at load, so they show everywhere the game's own
station names and song titles do.
