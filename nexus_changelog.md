### [Unreleased - v0.3.0]

- RadioXL is now a real engine station: custom stations play on the Radioport, in every vehicle and on the radios placed around Night City, with their own name, icon and song titles.
- A station is one station.json and a folder of audio. No yaml, no script.
- A station can use an icon the game already has, such as the Hip Hop station's, by naming its record. No icon archive needed.
- Tuning away from a station and back picks the song up where the station has got to, the way a vanilla station does.
- A vehicle radio switched off and on stays on the station it was on.
- "Mute radio when..." settings: twelve switches, all on by default, each keeping or lifting one of the game's radio silences. They apply to every station on the Radioport, the game's own included, and a switch stands for a whole situation: turning off the holo call switch also lifts the locks a call brings with it.
- Stations built for 0.1.0 need converting to a station.json; their songs and icon are reused as they are.
- A station can mark tracks as idents, jingles or ads: they play between songs like the game's own station idents and show no song title.
- A station can play a live internet radio stream. The player allows the stream's host in AudioXL's settings file.
- Requires AudioXL 0.4.0 or later.
