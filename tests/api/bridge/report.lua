-- The RadioXL API test's report, with the CET route checked against the redscript route: every
-- event that reached a redscript listener during the run must have reached an Observe as often.
-- Nil while the run is still going.
if RadioXLApiTest_RadioXLApiTest.Running() then return nil end
local out = { RadioXLApiTest_RadioXLApiTest.Report(), "CET route (Observe on RadioXLEvents):" }
local t = RadioXLApiTest_RadioXLApiTest.Get()
local ok = true
for m, base in pairs(RXT.base or {}) do
  local reds = t:Count(m:sub(3)) - base
  local cet = RXT.cet[m] or 0
  if reds > 0 or cet > 0 then
    local same = reds == cet
    ok = ok and same
    table.insert(out, string.format("%s  %s  redscript %d, CET %d", same and "PASS" or "FAIL", m, reds, cet))
  end
end
if not RXT.hooked then table.insert(out, "FAIL  start.lua was not run, so nothing was observed") end
return table.concat(out, "\n")
