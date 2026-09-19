# Station builder changelog

One entry per builder version. The version is in `package.json` and printed at the foot of the page.
`scripts/nexus-builder-file.py` turns the newest entry into the Nexus misc file's description.

## 0.2.1

- Build .zip waits until every file has been measured, and the footer says how many are still
  measuring. A build started before that wrote the unmeasured tracks at 100 %.
- A RadioExt station comes across with its Volume at 100 %. RadioExt's own volume was set against
  RadioExt's player, and with Auto level putting each track on the game's level it moved the whole
  station off target. The note says what the value was.

## 0.2.0

- Each track has its own level, 0 to 400 % with the dB shown, written to the manifest as the track's
  `gain` and multiplied with the station's Volume. A track at 100 % writes nothing.
- Auto level, on by default: every file is measured as it is added (integrated loudness and true
  peak, EBU R128) and its level set so it plays at the level of the game's own stations, as far as
  the file's peak allows. Off, the sliders are yours, starting from where they are; the page still
  shows each track's suggestion, with "use it" per track and "Use suggested levels" for all.
  Opening a station that already carries a track level opens with auto level off.
- A play button on each track hears it at the level set, live as the slider moves.
- A stream is not measured and keeps a manual level. A file the browser cannot decode says so and
  gets no suggestion.
- Opening a station reads each track's `gain` back.
- The builder's version is printed at the foot of the page.
- Show frequency, on by default: off, the label is the name alone and the frequency only places
  the station on the dial (RadioXL 0.4.0 reads the field). A RadioExt station whose name carried
  no number comes across with it off.
- A stream track has a title field; the URL sits under it.
- Choosing an image after opening or converting a station takes the station's own atlas path
  instead of the one the station carried.
- Own atlas takes the .archive: Build .zip puts it in the package, and the page checks that the
  archive's index lists the atlas path typed. An archive that stores its icon raw shows it in the
  previews.
- A build that fails stays on the page: which step and which file, with a log to copy into a
  report. Every file is checked as readable before the zip starts, so a file moved or deleted
  after it was picked is named rather than breaking the zip halfway.
- A station name with no Latin letter or digit in it (CJK, Cyrillic, symbols) gets a station ID
  and a mod folder from a hash of the name, instead of none.
- A large station in a browser with no save dialog gets a notice that the zip is built in memory,
  and that Chrome and Edge write it straight to disk.
- The footer links to RadioXL's current Nexus page.

## 0.1.0

- New station, Edit a RadioXL station, From RadioExt, Build .zip, and the Radioport and world
  radio previews drawn from the game's own ink files.
- Build .zip writes an icon's texture, atlas and archive from an image.
- The station Volume runs 0 to 400 %.
