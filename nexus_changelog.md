### [Unreleased]

### v0.4.1

- Fix: My station now tunes the car radio when you get in. The car brings its own station up a fraction of a second after you take the seat, later than the check ran, so the station you set was passed over.

### v0.4.0

- New: every track can have its own level, so a loud song comes down and a quiet one comes up without touching the files. The station builder measures each song and sets the level for you; the whole station still has one Volume on top.
- New: a station's `gain` runs up to 4, so a quiet recording can be brought up to the level of the game's own stations. A raised level must leave the loudest sample under full scale or it crackles; the builder keeps its suggestion inside that limit.
- New: `"showFrequency": false` shows a station's name alone as its label. The frequency still places it on the dial.
- Station builder 0.2.0: Auto level, on by default, measures every song as you add it and sets its level to match the game's stations; turn it off to set the sliders yourself. A play button on each track hears it at that level. Own atlas takes your .archive and checks the atlas path is in it. A stream can have a title. A failed build stays on the page with a log to copy into a report. Choosing an image after opening or converting a station uses the station's own atlas path. A name with no Latin letters still gets a station ID. The builder's version is printed at the foot of the page, and its own changelog is the "RadioXL Station Builder" file under Miscellaneous.

### v0.3.0

- RadioXL is now a real engine station: custom stations play on the Radioport, in every vehicle and on the radios placed around Night City, with their own name, icon and song titles.
- A station is one station.json and a folder of audio. No yaml, no script. The frequency is its own field in it, and the name is the name alone; the game shows the two together.
- A station can use an icon the game already has, such as the Hip Hop station's, by naming its record. No icon archive needed.
- Tuning away from a station and back picks the song up where the station has got to, the way a vanilla station does.
- A vehicle radio switched off and on stays on the station it was on.
- "Mute radio when..." settings: twelve switches, all on by default, each keeping or lifting one of the game's radio silences. They apply to every station on the Radioport, the game's own included, and a switch stands for a whole situation: turning off the holo call switch also lifts the locks a call brings with it.
- Stations built for 0.1.0 need converting to a station.json; their songs and icon are reused as they are.
- A station can carry Stanley's news bulletins and greetings with "news": true.
- Song titles are optional: an untitled song plays everywhere, with no name shown.
- A station can mark tracks as idents, jingles or ads: they play between songs like the game's own station idents and show no song title.
- A station can play a live internet radio stream. The player allows the stream's host in AudioXL's settings file.
- Next and previous song on any radio, and next and previous station along the dial, on keys of your own. F3 and F2 out of the box; a key can carry a modifier, and the Radioport can have its own set. A song you skip to leaves the station's own rotation and counts toward its next ident, the same as one the station picked itself.
- Switch any song off, on any station, or off only while Streamer Mode is on. A key can switch off the song playing now.
- My station: the radio comes on to the station you choose, when you get into a car, when the car radio switches on, or when the Radioport switches on. A key jumps there any time.
- Stations the station keys step over, so cycling only visits the ones you listen to.
- The vehicle radio's song popup for the Radioport too, and an on-screen line, each optional.
- Mute station idents, and mute the DJs' talk between songs.
- Requires AudioXL 0.4.3 or later.
