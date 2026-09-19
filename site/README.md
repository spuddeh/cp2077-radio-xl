# RadioXL station builder

A web page that builds a RadioXL station mod: https://spuddeh.github.io/cp2077-radio-xl/

Fill in the station, add its audio, and Build .zip writes a mod ready to install with a mod
manager: the `station.json` and the audio files in the folder RadioXL reads stations from, and,
given an icon image, the icon's texture, atlas and archive. The preview shows the station on the
Radioport and on the four kinds of world radio, drawn from the game's own UI files.

Every field is checked against the rules RadioXL applies when it loads a station, so a station that
builds here is one RadioXL accepts. The manifest format itself is in the
[station manifest reference](../red4ext/plugins/RadioXL/stations/README.md).

## Track levels

Auto level is on by default: each file is measured as it is added (integrated loudness and true
peak, EBU R128) and its level set so it plays at the level of the game's own stations. A raise is
bounded by the file's own peak, because RadioXL scales the samples and a sample past full scale
wraps. Turn auto level off to set the sliders yourself, from where they are; the suggestion stays
on each track. The play button hears a track at its level. A stream cannot be measured ahead of
time and keeps a manual level.

The station's Volume is one trim on top of every track's level.

## Which version

The builder's version is printed at the foot of the page. [CHANGELOG.md](CHANGELOG.md) lists what
changed in each.

## Running it locally

```
npm install
npm run dev        # the page on a local port
npm run build      # dist/, what GitHub Pages serves
npm test           # the checker, the manifest writer and the loudness meter, under node
npm run test:browser   # the built page in headless Chrome or Edge; skips without one
```

Everything visual is generated from the game's ink files by `scripts/*.py`; `src/theme/tokens.css`,
`src/world/layouts.json` and `src/ink/` are outputs, not sources.
