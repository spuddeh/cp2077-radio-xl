RadioXL Example Station
=======================

1. Install this zip with your mod manager, or copy the red4ext folder into your
   Cyberpunk 2077 install (the folder with Cyberpunk2077.exe in it).

2. Start the game. "102.7 Example Radio" is on the dial, in a car and on the
   Radioport, playing the two short tracks in its audio folder with a station
   ident between every three songs.

3. To make it yours, open
      red4ext\plugins\RadioXL\stations\RadioXLExampleStation\station.json
   and change four things:

      "name"         the station's own id: letters, digits and underscores, and
                     unique among every installed station. radio_station_<yours>.
      "frequency"    where it sits on the dial, as a number. Pick one the game
                     does not use: 88.9, 89.3, 89.7, 91.9, 92.9, 95.2, 96.1,
                     98.7, 99.9, 101.9, 103.5, 106.9, 107.3 and 107.5 are taken.
      "displayName"  the name alone, without the frequency. The game shows the
                     two together: "102.7 Example Radio".
      "tracks"       one line per audio file in the audio folder: mp3, wav, ogg
                     or flac. "title" is what the radio popup shows for the song.
                     A track marked "ident": true plays between songs and has
                     no title, like a station's own jingle.

   Then replace the files in the audio folder with your music, and rename the
   RadioXLExampleStation folder to your mod's name.

That is the whole station. No durations, no event names, no yaml and no script:
RadioXL reads each track's length from the file and builds the rest when the
game loads.

The file must be plain JSON: double quotes, no comments, no trailing commas.
If something is wrong, the station is skipped and RedLogger's
r6\logs\mods\RadioXL.log names the file and the line.

Optional, on the same lines:

      "icon": "UIIcon.RadioHipHop"      a station icon the game already has;
                                        leave it out for the RadioXL glyph.
      "news": true                      lets Stanley's bulletins and greetings
                                        reach the station, as on the game's own.

The station builder page makes all of this from a form, with an icon of your own
from a picture: https://spuddeh.github.io/cp2077-radio-xl/
