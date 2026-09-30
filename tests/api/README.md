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

With a save loaded and V on foot. It uses the Radioport, changes station and song, flips every
setting it can reach and puts each one back.

- **Through the wolvenkit MCP's live bridge:** `live_exec` the contents of `bridge/start.lua`, wait
  about 40 seconds, then `live_exec` `bridge/report.lua` (nil means still running). The report also
  checks that every event reached a CET `Observe` as often as it reached the redscript listener.
- **From the CET console:** `RadioXLApiTest_RadioXLApiTest.Start()`, then
  `print(RadioXLApiTest_RadioXLApiTest.Report())`. This checks the redscript route only.

## What it does not reach

- `CatalogRefreshed` needs a quest to add songs to a station, and `Silenced` a phone call or a scene.
- The vehicle receiver: run it on foot. In a car the run stops after the reads.
- A song state surviving a save load: switch one off with the API, load a save, and read
  `SongState` again.
