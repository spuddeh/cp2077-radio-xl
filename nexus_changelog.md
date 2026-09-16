### [Unreleased - v0.3.0]

- RadioXL is now a real engine station: custom stations play on the Radioport, in every vehicle and on the radios placed around Night City, with their own name, icon and song titles.
- A station is one station.json and a folder of audio. No yaml, no script.
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
