-- ---------------------------------------------------------------------------
-- Health and resource bars. Both texts take placeholders ({cur}, {max},
-- {pct}, {deficit}). The resource bar follows the current power type, so a
-- druid's bar turns from mana to energy or rage when the form changes.
-- Health and power may be secret in combat: they only ever go to the bar and
-- the game's own formatter, never into our own arithmetic.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T = ns.L, ns.T
local HUD = ns.HUD

local function MakeBar(parent, color, textSize, key)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(ns.WHITE)
    bar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
    bar:SetStatusBarColor(color[1], color[2], color[3])
    ns.Skin(bar, T.hudTrack, T.hudLine)
    ns.HUD:AddEdge(bar, key)
    local shade = bar:CreateTexture(nil, "ARTWORK", nil, 5)   -- over fill and track alike
    shade:SetAllPoints()
    ns.Gradient(shade, 0, 0, 0, 0.38, 0, 0, 0, 0)
    local sheen = bar:CreateTexture(nil, "ARTWORK", nil, 6)
    sheen:SetPoint("TOPLEFT")
    sheen:SetPoint("TOPRIGHT")
    sheen:SetHeight(1)
    sheen:SetColorTexture(unpack(T.sheen))
    bar.text = ns.HudText(bar, textSize)
    bar.text:SetPoint("CENTER", 0, 0)
    return bar
end
ns.MakeHudBar = MakeBar   -- (also used by the threat bar)

-- which formatting path the last update took (shown in the layout editor and /ef status)
ns.textModes = {}

-- the bar color a style asks for: "default" (the part's own), "class", "custom"
local function StyleColor(key, default)
    local mode = HUD:Get(key, "colorMode")
    if mode == "class" then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[ns.playerClass or ""]
        if c then return { c.r, c.g, c.b } end
    elseif mode == "custom" then
        local c = HUD:Get(key, "color")
        if type(c) == "table" then return c end
    end
    return default
end
ns.StyleColor = StyleColor

-- the text color a style asks for (field textColor; nil = the light default of the combat frame)
function ns.StyleTextColor(key)
    local c = HUD:Get(key, "textColor")
    if type(c) == "table" then return c end
    return T.hudText
end

-- text size, alignment, color and visibility of a bar's text
local function StyleText(key, fs)
    ns.ApplyFont(fs, HUD:Get(key, "textSize") or 12, "")
    local tc = ns.StyleTextColor(key)
    fs:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
    local align = HUD:Get(key, "textAlign") or "CENTER"
    fs:ClearAllPoints()
    if align == "LEFT" then
        fs:SetPoint("LEFT", 6, 0)
    elseif align == "RIGHT" then
        fs:SetPoint("RIGHT", -6, 0)
    else
        fs:SetPoint("CENTER", 0, 0)
    end
    fs:SetJustifyH(align)
    fs:SetShown(HUD:Get(key, "showText") ~= false)
end
ns.StyleBarText = StyleText

-- ---------------------------------------------------------------------------
-- Health
-- ---------------------------------------------------------------------------
local health = HUD:Register({
    key = "health", order = 10, height = 20,
    label = L["Health bar"],
    style = { height = 20, colorMode = "default", textSize = 12, textAlign = "CENTER", showText = true,
              warn = true, warnPct = 30 },
    Build = function(self, parent)
        local bar = MakeBar(parent, T.health, 12, "health")
        -- warning zone: the left 30% of the empty track glows red. It sits under
        -- the fill, so it only shows once health drops below it -- the game
        -- draws that comparison, we never touch the (secret) value
        local zone = CreateFrame("Frame", nil, bar)
        zone:SetPoint("TOPLEFT")
        zone:SetPoint("BOTTOMLEFT")
        zone:SetWidth(HUD.WIDTH * 0.3)
        bar.zoneFrame = zone
        zone:SetFrameLevel(bar:GetFrameLevel())
        local glow = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
        glow:SetAllPoints(zone)
        ns.Gradient(glow, T.danger[1], T.danger[2], T.danger[3], 0.55, T.danger[1], T.danger[2], T.danger[3], 1)
        bar.zone, bar.zoneGlow = zone, glow
        local breathe = glow:CreateAnimationGroup()
        breathe:SetLooping("BOUNCE")
        local a = breathe:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.35)
        a:SetDuration(0.7)
        a:SetSmoothing("IN_OUT")
        bar.breathe = breathe
        -- the zone's width comes from the frame width (ApplyStyle), never from
        -- the bar: a bar holding a secret value reports secret sizes
        self.region = bar
        self.elapsed = 0
    end,
})

function health:Update()
    local bar = self.region
    local cur, max = UnitHealth("player"), UnitHealthMax("player")
    bar:SetMinMaxValues(0, max)
    bar:SetValue(cur)
    ns.textModes.health = ns.SetValueText(bar.text, ns.Char().text.health or "{cur}", cur, max, function()
        return UnitHealthPercent("player", false, CurveConstants and CurveConstants.ScaleTo100)
    end)
end

-- events bring every change; the slow tick is only a safety net and keeps
-- the warning zone in step with the frame's fading
function health:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.2 then return end
    self.elapsed = 0
    self:Update()
    -- the zone rests while dead or while the frame fades
    local bar = self.region
    local on = self.warn ~= false and not UnitIsDeadOrGhost("player") and HUD.frame:GetAlpha() >= 0.99
    bar.zoneGlow:SetShown(on)
    if on and not bar.breathe:IsPlaying() then bar.breathe:Play() end
    if not on and bar.breathe:IsPlaying() then bar.breathe:Stop() end
end

function health:ApplyStyle()
    local bar = self.region
    local c = StyleColor("health", T.health)
    bar:SetStatusBarColor(c[1], c[2], c[3])
    StyleText("health", bar.text)
    bar.zoneFrame:SetWidth(HUD.WIDTH * (HUD:Get("health", "warnPct") or 30) / 100)
    self.warn = HUD:Get("health", "warn") ~= false
    if not self.warn then
        bar.zoneGlow:Hide()
        bar.breathe:Stop()
    end
end

health.Refresh = health.Update

-- ---------------------------------------------------------------------------
-- Resource (mana, rage, energy ...)
-- ---------------------------------------------------------------------------
local power = HUD:Register({
    key = "power", order = 20, height = 20,
    label = L["Resource bar"],
    style = { height = 20, colorMode = "default", textSize = 13, textAlign = "CENTER", showText = true,
              fiveSec = true, fiveSecHeight = 3 },
    Build = function(self, parent)
        local bar = MakeBar(parent, ns.PowerColor("ENERGY"), 13, "power")
        -- crisp leading edge riding the end of the fill (anchored: no value math)
        bar.spark = bar:CreateTexture(nil, "ARTWORK", nil, 7)
        bar.spark:SetColorTexture(1, 1, 1, 0.5)
        bar.spark:SetWidth(1)
        bar.spark:SetPoint("TOPRIGHT", bar:GetStatusBarTexture(), "TOPRIGHT")
        bar.spark:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
        self.region = bar
        self.elapsed = 0
        -- five-second rule: thin bar right below the resource bar (its height is added to the part), own frame so that its
        -- OnUpdate only runs inside the 5 s window
        local fsr = CreateFrame("StatusBar", nil, bar)
        fsr:SetStatusBarTexture(ns.WHITE)
        fsr:SetMinMaxValues(0, 5)
        fsr:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
        fsr:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        fsr:SetFrameLevel(bar:GetFrameLevel() + 3)
        fsr.spark = fsr:CreateTexture(nil, "OVERLAY")
        fsr.spark:SetWidth(2)
        fsr.spark:SetPoint("TOPRIGHT", fsr:GetStatusBarTexture(), "TOPRIGHT")
        fsr.spark:SetPoint("BOTTOMRIGHT", fsr:GetStatusBarTexture(), "BOTTOMRIGHT")
        fsr:Hide()
        bar.fsr = fsr
    end,
})

-- Five-second rule. Pure time arithmetic on GetTime(): never on mana values.
local FSR_SECONDS = 5

-- does this spell cost mana? Without the API every spell counts (better too many than none).
function ns.CostsMana(spellID)
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return true end
    local costs = C_Spell.GetSpellPowerCost(spellID)
    if type(costs) ~= "table" then return false end
    local mana = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    for _, c in ipairs(costs) do
        if c.type == mana then
            if ns.IsSecret(c.cost) or ns.IsSecret(c.minCost) then return true end
            if (c.cost or 0) > 0 or (c.minCost or 0) > 0 then return true end
        end
    end
    return false
end

local function FsrStop(bar)
    local fsr = bar.fsr
    fsr.untilTime = nil
    fsr:SetScript("OnUpdate", nil)
    fsr:Hide()
end

local function FsrTick(fsr)
    local left = (fsr.untilTime or 0) - GetTime()
    if left <= 0 then
        fsr.untilTime = nil
        fsr:SetScript("OnUpdate", nil)
        fsr:Hide()
    else
        fsr:SetValue(left)
    end
end

local function FsrStart(bar)
    local fsr = bar.fsr
    fsr.untilTime = GetTime() + FSR_SECONDS
    fsr:SetValue(FSR_SECONDS)
    fsr:Show()
    fsr:SetScript("OnUpdate", FsrTick)
end

-- the five-second line sits below the bar and adds its height to the part; only for characters with mana
function power:ExtraHeight()
    if HUD:Get("power", "fiveSec") == false then return 0 end
    local mana = UnitPowerMax("player", Enum and Enum.PowerType and Enum.PowerType.Mana or 0)
    if ns.IsSecret(mana) or (mana or 0) > 0 then return HUD:Get("power", "fiveSecHeight") or 3 end
    return 0
end

function power:CurrentType()
    local pType, token = UnitPowerType("player")
    return pType, token
end

function power:Update()
    local bar = self.region
    local pType, token = self:CurrentType()
    if token ~= self.token then
        self.token = token
        local c = StyleColor("power", ns.PowerColor(token))
        bar:SetStatusBarColor(c[1], c[2], c[3])
        if token ~= "MANA" then FsrStop(bar) end   -- only mana has the rule (druid forms)
    end
    local cur, max = UnitPower("player", pType), UnitPowerMax("player", pType)
    bar:SetMinMaxValues(0, max)
    bar:SetValue(cur)
    ns.textModes.power = ns.SetValueText(bar.text, ns.Char().text.power or "{cur}", cur, max, function()
        return UnitPowerPercent("player", pType, false, CurveConstants and CurveConstants.ScaleTo100)
    end)
end

function power:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= 0.2 then
        self.elapsed = 0
        self:Update()
    end
end

function power:ApplyStyle()
    self.token = nil   -- recolor on the next update
    StyleText("power", self.region.text)
    local fsr = self.region.fsr
    local c = HUD:Get("power", "fiveSecColor")
    if type(c) ~= "table" then c = T.hudText end
    fsr:SetHeight(HUD:Get("power", "fiveSecHeight") or 3)
    fsr:SetStatusBarColor(c[1], c[2], c[3], c[4] or 0.85)
    fsr.spark:SetColorTexture(c[1], c[2], c[3], 1)
    if HUD:Get("power", "fiveSec") == false then FsrStop(self.region) end
    self:Update()
end

ns.On("PLAYER_CAST", function(spellID)
    if not power.shown or not power.region then return end
    if HUD:Get("power", "fiveSec") == false then return end
    local _, token = UnitPowerType("player")
    if token ~= "MANA" then return end
    if ns.CostsMana(spellID) then FsrStart(power.region) end
end)

-- ---------------------------------------------------------------------------
-- GCD bar: an own thin bar, the topmost part by default, lit while the global
-- cooldown runs. Only the plain on/off flag `isOnGCD` is read: never
-- compared, never computed on. A spell with a cooldown of its own (Kick, Gouge, Sprint)
-- never reports the GCD (`isOnGCD` is false from the first moment, and the
-- generic GCD spell 61304 has no record at all). The GCD is global, though: a *reference
-- spell* without a cooldown of its own shows it, whoever started it. References: the
-- class pack's `gcdRef` list (known spells only) and every spell seen reporting the GCD.
-- The OnUpdate exists only inside the GCD window.
-- ---------------------------------------------------------------------------
local learned = {}   -- spells seen reporting the GCD this session (reference spells found at runtime)
local GCD_POLL = 0.05

local gcd = HUD:Register({
    key = "gcd", order = 5, height = 4,
    label = L["Global cooldown"],
    style = { height = 4, clear = true },
    Build = function(self, parent)
        local r = CreateFrame("Frame", nil, parent)
        ns.Skin(r, T.hudTrack, T.hudLine)
        HUD:AddEdge(r, "gcd")
        local fill = CreateFrame("StatusBar", nil, r)
        fill:SetStatusBarTexture(ns.WHITE)
        fill:SetAllPoints()
        fill:SetFrameLevel(r:GetFrameLevel() + 2)
        fill:SetMinMaxValues(0, 1)
        fill:SetValue(1)
        fill:Hide()
        r.fill = fill
        self.region = r
    end,
})

-- is this spell reporting the global cooldown? true / false, nil when it cannot be told
local function OnGcd(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(info) ~= "table" then return nil end
    local on = info.isOnGCD
    if ns.IsSecret(on) then return nil end
    return on and true or false
end

-- reference spells, best first: the cast spell, those learned, the class pack's known ones
local function References(spellID)
    local list, seen = { spellID }, { [spellID] = true }
    local function Add(id)
        if id and not seen[id] then seen[id] = true list[#list + 1] = id end
    end
    local ids = {}
    for id in pairs(learned) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do Add(id) end
    local pack = ns.ClassPack and ns.ClassPack().gcdRef
    if pack then
        for _, id in ipairs(pack) do
            if ns.IsKnown(id) then Add(id) end
        end
    end
    return list
end

-- the spell whose record shows the running GCD, or nil
local function GcdSource(spellID)
    for _, id in ipairs(References(spellID)) do
        if id and OnGcd(id) then return id end
    end
end

function gcd:Stop()
    local fill = self.region and self.region.fill
    if not fill then return end
    self.spell, self.lit = nil, nil
    self.region:SetScript("OnUpdate", nil)
    fill:Hide()
end

gcd.HideAll = function(self)
    self:Stop()
    if self.region then self.region:Hide() end
end

-- The game updates the cooldown record a moment after the cast, and a spell with a
-- cooldown of its own reports `isOnGCD` only for an instant. So the flag only *starts* the
-- bar; with the duration object of the reference spell showing the GCD (the generic
-- GCD spell 61304 has none) the bar then runs and fades by
-- itself (passed on, never read: secret in combat), and the OnUpdate ends
-- after GCD_MAX. Without that object the flag decides, as before.
local GCD_WAIT = 0.5   -- how long a cast may take to show the GCD
local GCD_MAX = 2.5    -- longest GCD with the object's help (hasted ones are shorter)

local gcdCurve
local function GcdCurve()
    if gcdCurve == nil then
        gcdCurve = false
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            local ok, c = pcall(function()
                local cv = C_CurveUtil.CreateCurve()
                cv:AddPoint(0, 0)         -- nothing left: invisible
                cv:AddPoint(0.001, 1)
                cv:AddPoint(1, 1)
                return cv
            end)
            if ok and c then gcdCurve = c end
        end
    end
    return gcdCurve or nil
end

-- the duration object of a reference spell (that of the running GCD), or nil
local function GcdDuration(src)
    if not (src and C_Spell and C_Spell.GetSpellCooldownDuration) then return nil end
    local ok, d = pcall(C_Spell.GetSpellCooldownDuration, src)
    if ok and d then return d end
end

-- lets the lit fill follow the object: drains by SetTimerDuration, fades out through the curve
function gcd:Follow()
    local fill = self.region.fill
    local d = self.duration
    if not d then return end
    local curve = GcdCurve()
    if curve and type(d.EvaluateRemainingPercent) == "function" then
        local ok, a = pcall(d.EvaluateRemainingPercent, d, curve)
        if ok then fill:SetAlpha(a) end
    end
end

function gcd:Poll()
    local fill = self.region.fill
    if not self.lit then
        local src = GcdSource(self.spell)
        if not src then return end
        self.lit = true
        fill:SetMinMaxValues(0, 1)
        fill:SetValue(1)
        fill:SetAlpha(1)
        self.duration = nil
        local d = GcdDuration(src)
        if d and type(fill.SetTimerDuration) == "function" then
            local dir = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
            if pcall(fill.SetTimerDuration, fill, d, nil, dir) then self.duration = d end
        end
        fill:Show()
    elseif not self.duration and not GcdSource(self.spell) then
        self:Stop()
    end
    self:Follow()
end

local function GcdTick(region, elapsed)
    region.acc = (region.acc or 0) + elapsed
    region.waited = (region.waited or 0) + elapsed
    if region.acc < GCD_POLL then return end
    region.acc = 0
    gcd:Poll()
    if not gcd.lit then
        if region.waited > GCD_WAIT then gcd:Stop() end
    elseif gcd.duration and region.waited > GCD_MAX then
        gcd:Stop()
    end
end

function gcd:ApplyStyle()
    local r = self.region
    local c = HUD:Get("gcd", "color")
    if type(c) ~= "table" then c = T.accent end
    r.fill:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    -- optional see-through look: no track, no border, only the lit part shows
    local clear = HUD:Get("gcd", "clear") == true
    local f = clear and { 0, 0, 0, 0 } or T.hudTrack
    r.skinFill = f
    r.skinBg:SetColorTexture(f[1], f[2], f[3], f[4] or 1)
    for _, e in ipairs(r.edges) do e:SetShown(not clear) end
end

function gcd:Start(spellID)
    if OnGcd(spellID) then learned[spellID] = true end   -- a spell without a cooldown of its own: a reference
    local r = self.region
    self.spell, self.lit, self.duration, r.acc, r.waited = spellID, nil, nil, 0, 0
    r:SetScript("OnUpdate", GcdTick)   -- the region stays shown, so the script runs while the fill is dark
    self:Poll()
end

ns.On("PLAYER_CAST", function(spellID)
    if gcd.shown and gcd.region then gcd:Start(spellID) end
end)

power.Refresh = power.Update

for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT" }) do
    ns.RegisterUnitEvent(ev, "player", function() if health.shown then health:Update() end end)
end
for _, ev in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
    ns.RegisterUnitEvent(ev, "player", function() if power.shown then power:Update() end end)
end
