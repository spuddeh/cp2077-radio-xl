-- Starts the RadioXL API test and counts every event on the CET route.
-- Run through the live bridge (live_exec) or paste into the CET console as one line.
-- CET cannot remove an Observe, so the hooks are placed once per game session and reset per run.
RXT = RXT or {}
RXT.cet = {}
local methods = { "OnReady", "OnSongChanged", "OnStationChanged", "OnRadioPower", "OnCatalogRefreshed",
                  "OnSongStateChanged", "OnMutesChanged", "OnSilenced", "OnMyStationChanged", "OnStationSkipChanged" }
if not RXT.hooked then
  for _, m in ipairs(methods) do
    Observe("RadioXL.RadioXLEvents", m, function() RXT.cet[m] = (RXT.cet[m] or 0) + 1 end)
  end
  RXT.hooked = true
end
RXT.base = {}
local t = RadioXLApiTest_RadioXLApiTest.Get()
for _, m in ipairs(methods) do RXT.base[m] = t:Count(m:sub(3)) end
return RadioXLApiTest_RadioXLApiTest.Start()
