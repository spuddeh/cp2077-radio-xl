# RadioXL station builder

A web page that makes a RadioXL station mod for you: https://spuddeh.github.io/cp2077-radio-xl/

Fill in the station, add your songs, and Build .zip gives you a mod ready for your mod manager: the `station.json`
and the audio files in the folder RadioXL reads stations from, plus the icon's texture, atlas and archive if you
gave it a picture. The preview shows the station on the Radioport and on the four kinds of world radio, drawn from
the game's own UI files.

Every field is checked against the rules RadioXL uses when it loads a station, so a station that builds here is one
RadioXL will accept. A WAV that won't play in game is flagged as you add it, and the page converts it to 16-bit. The
format itself is in the [station reference](../red4ext/plugins/RadioXL/stations/README.md).

## Track levels

Auto level is off by default, and Build .zip and Copy station.json offer to measure your songs first. With it on,
each file is measured as you add it (loudness and true peak, EBU R128) and its level set to match the game's own
stations. A file can only be raised as far as its own peak allows, or it would crackle in game. Turn auto level off
to set the sliders yourself; each track keeps its suggestion. The play button lets you hear a track at its level. A
stream can't be measured ahead of time, so you set its level by hand.

The station's Volume is one level on top of every track's own.

## Which version

The builder's version is at the bottom of the page. [CHANGELOG.md](CHANGELOG.md) lists what changed in each.

## Running it locally

```
npm install
npm run dev            # the page on a local port
npm run build          # dist/, what GitHub Pages serves
npm test               # the checker, the station.json writer and the loudness meter, under node
npm run test:browser   # the built page in headless Chrome or Edge; skips without one
```

Everything visual is generated from the game's UI files by `scripts/*.py`. `src/theme/tokens.css`,
`src/world/layouts.json` and `src/ink/` are generated, so don't edit them by hand.
