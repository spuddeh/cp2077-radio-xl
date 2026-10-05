-- ======================================================================================
-- Mod Name: Radio Probe Overlay
-- Author: Spuddeh
-- Description: Draws Radio Station Probe's readings in game: a marker on every radio listener and level
--              meters for the radio and music buses. Dev tool, never released.
-- ======================================================================================
--
-- Radio Station Probe (RED4ext) writes two files into this folder every 100 ms:
--   radio_live.txt   one line per listener: kind x y z counts playing station
--   meter_live.txt   one line per bus: name rms_db peak_db peak_hold_db calls
-- This mod only reads and draws them. Both are on by default; each has a hotkey to hide it.

local showMarkers = true
local showMeters = true

local listeners = {}
local meters = {}
local readAt = 0

local KINDS = { [1] = "World", [2] = "Car", [3] = "Hit car (k3)", [4] = "Player (k4)", [5] = "Ambient" }
local STATIONS = {
    radio_station_01_att_rock = "Morro Rock", radio_station_02_aggro_ind = "Vexelstrom",
    radio_station_03_elec_ind = "Night FM", radio_station_04_hiphop = "The Dirge",
    radio_station_05_pop = "Body Heat", radio_station_06_minim_techno = "Samizdat",
    radio_station_07_aggro_techno = "PEBKAC", radio_station_08_jazz = "Royal Blue",
    radio_station_09_downtempo = "Pacific Dreams", radio_station_10_latino = "30 Principales",
    radio_station_11_metal = "Ritual FM", radio_station_12_growl_fm = "Growl FM",
    radio_station_13_dark_star = "Dark Star", radio_station_14_impulse_fm = "Impulse",
}
local METERS = {
    { name = "diegetic", label = "Traffic + world radios", colour = { 0.3, 1, 0.3 } },
    { name = "systemic", label = "Combat / police / open-world music", colour = { 1, 0.75, 0.2 } },
    { name = "player", label = "Your radio (car, pocket, metro)", colour = { 0.35, 0.7, 1 } },
}

local function readFiles()
    local f = io.open("radio_live.txt", "r")
    if f then
        local list = {}
        for line in f:lines() do
            local k, x, y, z, c, pl, st = line:match("^(%d+) (%S+) (%S+) (%S+) (%d) (%d) (%S+)")
            if k then
                list[#list + 1] = { k = tonumber(k), x = tonumber(x), y = tonumber(y), z = tonumber(z),
                    counts = c == "1", playing = pl == "1", st = st }
            end
        end
        f:close()
        listeners = list
    end
    f = io.open("meter_live.txt", "r")
    if f then
        local byName = {}
        for line in f:lines() do
            local n, r, p, h = line:match("^(%S+) (%S+) (%S+) (%S+)")
            if n then byName[n] = { rms = tonumber(r), peak = tonumber(p), hold = tonumber(h) } end
        end
        f:close()
        meters = byName
    end
end

local function drawMarkers(dl, player)
    local cam = Game.GetCameraSystem()
    if not cam then return end
    local w, h = GetDisplayResolution()
    local pos = player:GetWorldPosition()
    local green = ImGui.GetColorU32(0.3, 1, 0.3, 1)
    local yellow = ImGui.GetColorU32(1, 0.85, 0.2, 1)
    local grey = ImGui.GetColorU32(0.6, 0.6, 0.6, 0.8)
    for _, r in ipairs(listeners) do
        local dx, dy, dz = r.x - pos.x, r.y - pos.y, r.z - pos.z
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d < 200 then
            local s = cam:ProjectPoint(Vector4.new(r.x, r.y, r.z + 1.5, 1))
            if s.w > 0 and math.abs(s.x) <= 1.2 and math.abs(s.y) <= 1.2 then
                local sx, sy = w / 2 + s.x * w / 2, h / 2 - s.y * h / 2
                local col = (r.counts and r.playing) and green or (r.counts and yellow or grey)
                local size = 9
                if r.k == 5 then
                    ImGui.ImDrawListAddCircleFilled(dl, sx, sy, size, col)
                elseif r.k == 2 then
                    ImGui.ImDrawListAddQuadFilled(dl, sx, sy - size, sx + size, sy, sx, sy + size, sx - size, sy, col)
                elseif r.k == 1 then
                    ImGui.ImDrawListAddTriangleFilled(dl, sx, sy - size, sx + size, sy + size, sx - size, sy + size, col)
                else
                    ImGui.ImDrawListAddRectFilled(dl, sx - size, sy - size, sx + size, sy + size, col)
                end
                ImGui.ImDrawListAddText(dl, sx + 12, sy - 8, col, string.format("%s %s %.0f m",
                    KINDS[r.k] or ("kind " .. r.k), STATIONS[r.st] or r.st, d))
            end
        end
    end
end

-- A bar runs from -60 dB (empty) to 0 dB (full); the white tick is the last second's peak.
local function drawMeters(dl)
    local x0, y0, bw, bh = 40, 300, 320, 18
    local th = ImGui.GetTextLineHeight()
    local white = ImGui.GetColorU32(1, 1, 1, 1)
    local bg = ImGui.GetColorU32(0, 0, 0, 0.55)
    local function frac(db) return math.max(0, math.min(1, (db + 60) / 60)) end
    if not next(meters) then
        ImGui.ImDrawListAddText(dl, x0, y0, white, "Radio meters: waiting for Radio Station Probe")
        return
    end
    for i, def in ipairs(METERS) do
        local m = meters[def.name] or { rms = -120, peak = -120, hold = -120 }
        local y = y0 + (i - 1) * (th + bh + 16)
        ImGui.ImDrawListAddText(dl, x0, y, white,
            string.format("%s   rms %.1f dB   peak %.1f dB", def.label, m.rms, m.hold))
        local by = y + th + 4
        local c = def.colour
        ImGui.ImDrawListAddRectFilled(dl, x0, by, x0 + bw, by + bh, bg)
        ImGui.ImDrawListAddRectFilled(dl, x0, by, x0 + bw * frac(m.rms), by + bh, ImGui.GetColorU32(c[1], c[2], c[3], 1))
        local hx = x0 + bw * frac(m.hold)
        ImGui.ImDrawListAddLine(dl, hx, by, hx, by + bh, white, 2)
    end
end

registerHotkey("RadioProbeOverlay_Markers", "Show / hide radio markers", function()
    showMarkers = not showMarkers
end)

registerHotkey("RadioProbeOverlay_Meters", "Show / hide radio meters", function()
    showMeters = not showMeters
end)

registerForEvent("onDraw", function()
    if not showMarkers and not showMeters then return end
    local player = Game.GetPlayer()
    if not player then return end
    local now = ImGui.GetTime()
    if now - readAt > 0.1 then
        readAt = now
        readFiles()
    end
    local dl = ImGui.GetForegroundDrawList()
    if showMarkers then drawMarkers(dl, player) end
    if showMeters then drawMeters(dl) end
end)
