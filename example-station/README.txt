RadioXL Example Station
=======================

1. Install this zip with your mod manager, or copy the red4ext folder into your
   Cyberpunk 2077 folder (the one with Cyberpunk2077.exe in it).

2. Start the game. "102.7 Example Radio" is on the dial, in a car and on the
   Radioport, playing the two short tracks in its audio folder with a station
   ident after every third song.

3. To make it yours, open
      red4ext\plugins\RadioXL\stations\RadioXLExampleStation\station.json
   and change four things:

      "name"         the station's ID: letters, digits and underscores,
                     different from every other installed station. Use your
                     own prefix: radio_station_<yours>.
      "frequency"    where it sits on the dial. Pick one the game doesn't use:
                     88.9, 89.3, 89.7, 91.9, 92.9, 95.2, 96.1, 98.7, 99.9,
                     101.9, 102.0, 103.5, 106.9, 107.3 and 107.5 are taken.
      "displayName"  the name only, without the frequency. The game shows them
                     together: "102.7 Example Radio".
      "tracks"       one line per audio file in the audio folder. Songs can be
                     MP3, OGG, FLAC, or WAV as 16-bit PCM. "title" is what the
                     radio popup shows. A track marked "ident": true plays
                     between songs with no title, like a station's own jingle.

   Then swap the files in the audio folder for your music, and rename the
   RadioXLExampleStation folder to your mod's name.

That's the whole station. RadioXL reads each song's length from the file and
builds everything else when the game loads.

station.json has to be plain JSON: double quotes, no comments, no trailing
commas. If something is wrong, the station is skipped and
red4ext\logs\radioxl-<date>.log names the file and the line.

Optional extras, on their own lines:

      "icon": "UIIcon.RadioHipHop"      one of the game's own station icons.
                                        Leave it out for the RadioXL glyph.
      "news": true                      lets Stanley's bulletins and greetings
                                        reach the station.
      "addUnlistedFiles": true          adds songs you drop in the folder at
                                        the next launch, and takes off ones
                                        you removed.

Every field is in red4ext\plugins\RadioXL\stations\README.md, which comes with
RadioXL.

The station builder makes all of this for you, icon included:
https://spuddeh.github.io/cp2077-radio-xl/
