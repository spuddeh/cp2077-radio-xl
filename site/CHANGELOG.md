# Station builder changelog

One entry per builder version. The version is in `package.json` and printed at the foot of the page.
`scripts/nexus-builder-file.py` turns the newest entry into the Nexus misc file's description.

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
- The footer links to RadioXL's current Nexus page.

## 0.1.0

- New station, Edit a RadioXL station, From RadioExt, Build .zip, and the Radioport and world
  radio previews drawn from the game's own ink files.
- Build .zip writes an icon's texture, atlas and archive from an image.
- The station Volume runs 0 to 400 %.
