-- ---------------------------------------------------------------------------
-- Threat on the current target (one bar, no grid, no nameplates, no combat
-- log). The sources, in this order, each only passed through:
--   1. value  UnitDetailedThreatSituation: the scaled percentage goes straight
--             to the bar and to the game's formatter, plain or secret alike
--   2. state  UnitThreatSituation 0-3, when the game withholds the value
--   3. lead   UnitThreatLeadSituation 0-3, when even the state is missing
-- Secret values are never compared, calculated or used as table keys: the
-- color comes from our table only for plain states, else from a color curve
-- (C_CurveUtil) the game evaluates for us. C_Secrets is only asked for the
-- /ef status line. Without a hostile target or data the bar stays empty.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T = ns.L, ns.T
local HUD = ns.HUD

local STATE_LABELS = { [0] = L["Low threat"], [1] = L["High threat"], [2] = L["Tanking, insecure"], [3] = L["Tanking"] }
local STATE_COLORS = { [0] = T.threatLow, [1] = T.threatHigh, [2] = T.threatInsecure, [3] = T.threatTanking }

local threat = HUD:Register({
    key = "threat", order = 45, height = 14,
    label = L["Threat bar"],
    style = { height = 14, colorMode = "default", textSize = 11, textAlign = "CENTER", showText = true,
              soundOn = true, sound = "RAID_WARNING", soundAt = 80, soundVolume = 100, showWhen = "always",
              soundWhen = "group" },
    Build = function(self, parent)
        self.region = ns.MakeHudBar(parent, T.threatLow, 11, "threat")
        self.elapsed = 0
        self.mode = L["no target"]
    end,
})

-- "Show: always / only in a group or raid" (style field showWhen). Hidden bars
-- leave the layout; a group change re-lays it out.
function threat:IsAvailable()
    if HUD:Get("threat", "showWhen") == "group" and not IsInGroup() then
        return false, L["group only"]
    end
    return true
end

-- where the sound may play (style field soundWhen): always / group (party or raid) / party / raid / instance
function threat:SoundWanted()
    local when = HUD:Get("threat", "soundWhen") or "group"
    if when == "group" then return IsInGroup() end
    if when == "party" then return IsInGroup() and not (IsInRaid and IsInRaid()) end
    if when == "raid" then return IsInRaid and IsInRaid() or false end
    if when == "instance" then
        if not IsInInstance then return false end
        local inside, kind = IsInInstance()
        return inside and (kind == "party" or kind == "raid") or false
    end
    return true
end

-- a sound when the threat percentage rises to the limit. Only with a plain
-- percentage: a secret value is never compared, so the alert stays silent then.
local ALERT_PAUSE = 3   -- seconds between two alerts
function threat:Alert(pct)
    if not HUD:Get("threat", "soundOn") or not self:SoundWanted() then self.armed = nil return end
    local limit = HUD:Get("threat", "soundAt") or 80
    if pct < limit then self.armed = true return end
    if self.armed == false then return end   -- still above: it rang already
    self.armed = false
    local now = GetTime()
    if self.lastAlert and now - self.lastAlert < ALERT_PAUSE then return end
    self.lastAlert = now
    ns.Sound.Play(HUD:Get("threat", "sound"), HUD:Get("threat", "soundVolume"))
end

-- a stored value or a secret one: both count as "the game told us"
local function Known(v) return ns.IsSecret(v) or v ~= nil end

-- ---------------------------------------------------------------------------
-- Color
-- ---------------------------------------------------------------------------
-- curves for secret values: percent (0-100) and steps (0-3)
local curves = {}
local function Curve(kind)
    if curves[kind] ~= nil then return curves[kind] or nil end
    curves[kind] = false
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c then return nil end
    local xs = kind == "pct" and { 0, 70, 90, 100 } or { 0, 1, 2, 3 }
    local good = pcall(function()
        for i, x in ipairs(xs) do
            local col = STATE_COLORS[i - 1]
            c:AddPoint(x, CreateColor(col[1], col[2], col[3], 1))
        end
    end)
    if good then curves[kind] = c end
    return curves[kind] or nil
end

-- state: a plain or secret 0-3; x: the value the curve reads (percent or the state)
function threat:Paint(state, x, kind)
    local bar = self.region
    if (HUD:Get("threat", "colorMode") or "default") ~= "default" then
        local c = ns.StyleColor("threat", T.threatLow)
        bar:SetStatusBarColor(c[1], c[2], c[3])
        return
    end
    if not ns.IsSecret(state) and type(state) == "number" and STATE_COLORS[state] then
        local c = STATE_COLORS[state]
        bar:SetStatusBarColor(c[1], c[2], c[3])
        return
    end
    local cv = Known(x) and Curve(kind)
    if cv and pcall(function()
        local col = cv:Evaluate(x)
        bar:GetStatusBarTexture():SetVertexColor(col:GetRGBA())
    end) then
        return
    end
    bar:SetStatusBarColor(T.hudMuted[1], T.hudMuted[2], T.hudMuted[3])
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------
function threat:SetText(fmt, v)
    local fs = self.region.text
    if not pcall(fs.SetFormattedText, fs, fmt, v) then fs:SetText("") end
end

function threat:Empty(reason)
    self.armed = nil   -- a new target rings again
    local bar = self.region
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar.text:SetText("")
    self.mode = reason
end

-- a 0-3 answer (state or lead) on the bar
function threat:ShowStep(v, labels, fallbackFmt)
    local bar = self.region
    bar:SetMinMaxValues(0, 3)
    bar:SetValue(v)
    if ns.IsSecret(v) then
        self:SetText(fallbackFmt, v)
    else
        local label = labels and type(v) == "number" and labels[v]
        if label then bar.text:SetText(label) else self:SetText(fallbackFmt, v) end
    end
    self:Paint(v, v, "step")
end

function threat:Update()
    local exists = UnitExists("target")
    if not ns.IsSecret(exists) and not exists then return self:Empty(L["no target"]) end
    if not ns.IsSecret(exists) then
        local can = UnitCanAttack("player", "target")
        -- a secret answer: the threat APIs below decide
        if not ns.IsSecret(can) and not can then return self:Empty(L["no hostile target"]) end
        -- a dead target keeps its last threat numbers: show nothing, play nothing
        if ns.TargetGoneOrDead() then return self:Empty(L["target is dead"]) end
    end

    -- 1. the value
    local ok, _, state, scaled = pcall(UnitDetailedThreatSituation, "player", "target")
    if ok and Known(scaled) then
        local bar = self.region
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(scaled)
        self:SetText("%.0f%%", scaled)
        self:Paint(state, scaled, "pct")
        if ns.IsSecret(scaled) then
            self.mode = L["value (secret, shown by the game)"]
        else
            self.mode = L["value"]
            if type(scaled) == "number" then self:Alert(scaled) end
        end
        return
    end
    -- 2. the state
    local ok2, st = pcall(UnitThreatSituation, "player", "target")
    if ok2 and Known(st) then
        self:ShowStep(st, STATE_LABELS, "%d / 3")
        self.mode = L["state 0-3"]
        return
    end
    -- 3. the lead
    local ok3, lead = pcall(UnitThreatLeadSituation, "player", "target")
    if ok3 and Known(lead) then
        self:ShowStep(lead, nil, L["Lead %d / 3"])
        self.mode = L["lead 0-3"]
        return
    end
    self:Empty(L["no threat data"])
end

-- what C_Secrets says about the pair (only for /ef status, never on the value)
function threat:SecretFlag()
    local fn = C_Secrets and C_Secrets.ShouldUnitThreatValuesBeSecret
    if not fn then return L["not available"] end
    local ok, r = pcall(fn, "player", "target")
    if not ok then return L["not available"] end
    if ns.IsSecret(r) then return L["secret"] end
    return r and L["yes"] or L["no"]
end

-- events bring every change; the slow tick is only a safety net
function threat:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.25 then return end
    self.elapsed = 0
    self:Update()
end

function threat:ApplyStyle()
    ns.StyleBarText("threat", self.region.text)
    self:Update()
end

threat.Refresh = threat.Update

ns.RegisterEvent("GROUP_ROSTER_UPDATE", function() HUD:ApplyLayout() end)

for _, ev in ipairs({ "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "PLAYER_TARGET_CHANGED",
                      "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    ns.RegisterEvent(ev, function() if threat.shown then threat:Update() end end)
end
