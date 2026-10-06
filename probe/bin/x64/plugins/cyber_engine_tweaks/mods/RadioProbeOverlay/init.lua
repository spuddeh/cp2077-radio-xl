-- ======================================================================================
-- Mod Name: Radio Probe Overlay
-- Author: Spuddeh
-- Description: Draws Radio Station Probe's readings in game: a marker on every radio listener and level
--              meters for the radio and music buses. Dev tool, never released.
-- ======================================================================================
--
-- Radio Station Probe (RED4ext) writes two files into this folder every 100 ms:
--   radio_live.txt   one line per listener: kind x y z counts playing station
--   meter_live.txt   one line per bus: name rms_db peak_db peak_hold_db calls rms_left rms_right peak_left peak_right
--   params_live.txt  one line per vehicle game parameter: name global scope listener_value scope
-- Audible Traffic Radios' tuning build writes a fourth, every 250 ms:
--   atr_live.txt     one line per traffic car with a radio: entity_id level_db openness
-- This mod only reads and draws them. Both are on by default; each has a hotkey to hide it.

local showMarkers = true
local showMeters = true

local listeners = {}
local meters = {}
local params = {}
local atrCars = {}
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
            local l, rr = line:match("^%S+ %S+ %S+ %S+ %S+ (%S+) (%S+)")
            if n then
                byName[n] = { rms = tonumber(r), peak = tonumber(p), hold = tonumber(h),
                    left = tonumber(l), right = tonumber(rr) }
            end
        end
        f:close()
        meters = byName
    end
    f = io.open("params_live.txt", "r")
    if f then
        local list = {}
        for line in f:lines() do
            local n, g, gt, l, lt = line:match("^(%S+) (%S+) (%S+) (%S+) (%S+)")
            if n then list[#list + 1] = { name = n, global = tonumber(g), gt = gt, listener = tonumber(l), lt = lt } end
        end
        f:close()
        params = list
    end
    f = io.open("atr_live.txt", "r")
    if f then
        local list = {}
        for line in f:lines() do
            local id, db, open = line:match("^(%d+) (%S+) (%S+)")
            if id then list[#list + 1] = { id = tonumber(id), db = tonumber(db), open = tonumber(open) } end
        end
        f:close()
        atrCars = list
    end
end

-- Audible Traffic Radios: each traffic car's radio level and openness, above the car.
local function drawAtrCars(dl, player)
    local cam = Game.GetCameraSystem()
    if not cam then return end
    local w, h = GetDisplayResolution()
    local pos = player:GetWorldPosition()
    local cyan = ImGui.GetColorU32(0.3, 0.9, 1, 1)
    for _, c in ipairs(atrCars) do
        local car = Game.FindEntityByID(EntityID.new({ hash = c.id }))
        if car then
            local p = car:GetWorldPosition()
            local dx, dy, dz = p.x - pos.x, p.y - pos.y, p.z - pos.z
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            local s = cam:ProjectPoint(Vector4.new(p.x, p.y, p.z + 2.2, 1))
            if d < 200 and s.w > 0 and math.abs(s.x) <= 1.2 and math.abs(s.y) <= 1.2 then
                local sx, sy = w / 2 + s.x * w / 2, h / 2 - s.y * h / 2
                ImGui.ImDrawListAddText(dl, sx - 40, sy, cyan,
                    string.format("ATR %+.1f dB  open %.2f  %.0f m", c.db, c.open, d))
            end
        end
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

-- A bar runs from -60 dB (empty) to 0 dB (full); the white tick is the last second's peak. Under it,
-- two thin bars are the left and right channels' RMS, when the probe writes them.
local function drawMeters(dl)
    local x0, y0, bw, bh, ch = 40, 300, 320, 18, 5
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
        local y = y0 + (i - 1) * (th + bh + 2 * ch + 20)
        local lr = m.left and string.format("   L %.1f  R %.1f", m.left, m.right) or ""
        ImGui.ImDrawListAddText(dl, x0, y, white,
            string.format("%s   rms %.1f dB   peak %.1f dB%s", def.label, m.rms, m.hold, lr))
        local by = y + th + 4
        local c = def.colour
        ImGui.ImDrawListAddRectFilled(dl, x0, by, x0 + bw, by + bh, bg)
        ImGui.ImDrawListAddRectFilled(dl, x0, by, x0 + bw * frac(m.rms), by + bh, ImGui.GetColorU32(c[1], c[2], c[3], 1))
        local hx = x0 + bw * frac(m.hold)
        ImGui.ImDrawListAddLine(dl, hx, by, hx, by + bh, white, 2)
        if m.left then
            local col = ImGui.GetColorU32(c[1], c[2], c[3], 0.8)
            for j, db in ipairs({ m.left, m.right }) do
                local cy = by + bh + 2 + (j - 1) * (ch + 1)
                ImGui.ImDrawListAddRectFilled(dl, x0, cy, x0 + bw, cy + ch, bg)
                ImGui.ImDrawListAddRectFilled(dl, x0, cy, x0 + bw * frac(db), cy + ch, col)
            end
        end
    end
    -- The vehicle game parameters, each as global value and the value on the player's listener, with the scope
    -- Wwise resolved it from (0 default, 1 global, 2 game object).
    local py = y0 + #METERS * (th + bh + 2 * ch + 20)
    for i, p in ipairs(params) do
        ImGui.ImDrawListAddText(dl, x0, py + (i - 1) * (th + 2), white,
            string.format("%s   global %.2f (%s)   listener %.2f (%s)", p.name, p.global, p.gt, p.listener, p.lt))
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
    if showMarkers then
        drawMarkers(dl, player)
        drawAtrCars(dl, player)
    end
    if showMeters then drawMeters(dl) end
end)
