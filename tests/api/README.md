# RadioXL API test

An in-game test of the script API (`r6/scripts/RadioXL/API.reds`) and its events. It is a separate
mod, `RadioXLApiTest`, deployed to the Testing instance only and never shipped: the release takes
`archive`, `r6` and `red4ext` from the repo root, and this folder is not one of them.

```powershell
pwsh -File .\.claude\scripts\redscript-check.ps1 -Mod 'RadioXL\tests\api'
pwsh -File .\.claude\scripts\deploy-mod.ps1 -Mod 'RadioXL\tests\api' -Instance Testing -Target 'RadioXL API Test [DEV]' -CreateTarget
```

Enable `RadioXL API Test [DEV]` in MO2, below RadioXL.

## Running it

With a save loaded. Seated in a vehicle it uses the car radio, and also checks that the Radioport
is never reported while seated; on foot it uses the Radioport. Run it both ways. It changes station
and song, flips every setting it can reach and puts each one back.

- **Through the wolvenkit MCP's live bridge:** `live_exec` the contents of `bridge/start.lua`, wait
  about 40 seconds, then `live_exec` `bridge/report.lua` (nil means still running). The report also
  checks that every event reached a CET `Observe` as often as it reached the redscript listener.
- **From the CET console:** `RadioXLApiTest_RadioXLApiTest.Start()`, then
  `print(RadioXLApiTest_RadioXLApiTest.Report())`. This checks the redscript route only.

## Stations it reads when installed

The Testing instance's PHONKWAVE RADIO carries 19 idents and, added for this test, a `description`
in `en-us` and `de-de` and an `extensions` entry for `RadioXLApiTest` (its original manifest is kept
beside it as `station.json.orig`). Yumi Co. Radio is a stream. Without them those checks are
skipped with a note.

## What it does not reach

- `CatalogRefreshed` needs a quest to add songs to a station, and `Silenced` a phone call or a scene.
- A song state surviving a save load: switch one off with the API, load a save, and read
  `SongState` again.
