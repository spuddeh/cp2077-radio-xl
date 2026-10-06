### [Unreleased]

- Fix: changing the traffic setting no longer undoes another mod's changes to which stations traffic cars play.
- New: the "Mute the radio when..." switches are now situations: a call, a scene, a driving scene, a club, a weapons-free area such as your apartment, and a quest blocking the radio. Turning one off keeps the Radioport playing through that situation. Your previous switch settings are carried over to the matching situation.
- New: switches for combat music, police chase music, someone speaking (the radio is turned down under conversations, calls and the police scanner), Megabuilding H10's music, and an open menu (the inventory, map and hub; the Escape menu still pauses the radio). They act on the car radio and the Radioport.
- All of these are on by default, which is the game's own behaviour.

- Fix: a custom station no longer picks up other sounds. Custom stations used channels the game also uses for world music, TVs and ambience, so near those you could hear them mixed in, often in one ear. Custom stations now have channels nothing else in the game uses.
- Fix: the second and twelfth custom stations no longer share the police scanner's and Kurtz's place in the game, where the scanner could be heard in the second one.
- Up to 101 custom stations.
- After updating, a radio in the world that was on a custom station can come back on a different one, once: tune it again.

- Fix: a car you take from traffic while it plays a custom station keeps that station. It came up on a random station of the game's, or with the radio off.
- Fix: a car saved while on a custom station is still on it when the save loads.

### v0.7.0

- New: passing traffic cars can be tuned to custom stations. A setting on the Stations tab chooses which cars: Most cars (the default), Every car, or Off. A passing car's radio is tuned but not heard in the game, and that is unchanged: this puts custom stations on those radios.
- New: radios and jukeboxes around the city that start on a random station can start on a custom one. On by default, with its own switch.
- New: a switch to let traffic and those radios pick stations that stream as well. Off by default.
- New: a station can add the songs you drop into its folder by itself. With "addUnlistedFiles" in its station.json, new audio files are added at the next launch and removed files are taken off.
- New: song lengths are remembered between launches, so a song file that has not changed is not read again at each start.
- Fix: removing, adding or reordering a station's songs no longer moves your per-song settings onto other songs. Settings you already have are carried over on the first launch.
- Fix: a WAV that AudioXL cannot play (32-bit float, or anything but 16 or 24-bit PCM) is left out of the station, with a line in RadioXL's log naming it, rather than listed and played as silence.
- Mod authors: a custom song's event name now comes from its file name rather than its place in the list.

### v0.6.0

- New: a script API for other mods. A mod can read every station and song, the player's song settings, what is playing and where, and each station's description; change song or station through RadioXL's own controls; and hear when the song, the station, the radio's power or a setting changes. Mod authors: the API is documented at https://github.com/spuddeh/cp2077-radio-xl/blob/main/docs/script-api.md
- New: a station can carry a `description` of up to 1000 characters, in one language or several, for other mods to read. RadioXL itself does not show it. The station builder has a field for it.
- New: a station can carry data for other mods under `extensions`. RadioXL passes it on and does nothing else with it.
- New: when a stream station cannot play, a warning in game says what to change in AudioXL.ini: switching streams on, or the host to allow.
- Fix: a song switched off with the never-again key is now remembered after loading a save or restarting the game.
- Fix: the previous-song key now steps back through songs the station chose itself, not only the ones you skipped to, when no song is switched off.

### v0.5.1

- Fix: My station now plays when you get into a car whose radio is off, such as the first car after loading a save. The radio is switched on to your station about a second after you sit down.

### v0.5.0

- Fix: My station and the two mutes stopped being remembered once Redscript Configuration Framework was updated to 3.0.0. That release dropped RedFileSystem and RedData, which is where RadioXL kept those three values, and it went quiet rather than reporting anything.
- Changed: RadioXL now keeps them through RedFunctions 0.13.0 or later, which replaces those two and is what the settings panel itself uses. What you have already set is read from the same file and carries over; nothing needs setting again.

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
