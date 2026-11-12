-- ---------------------------------------------------------------------------
-- Riposte alert (rogue module): a free-standing icon that shows, and blinks,
-- while Riposte can be used (after a parry), with an optional sound.
--
-- Reads only C_Spell.IsSpellUsable (plain booleans, also in combat) and, where
-- the client sends them, the spell activation overlay events. A secret answer
-- keeps the last state. The icon is no button: it casts nothing and lets
-- clicks through; only while the Riposte window is open can it be dragged.
-- IsSpellUsable ignores the cooldown, so a cast of Riposte hides the icon
-- until the game reports it unusable and usable again (the next parry).
-- Nor does IsSpellUsable know the cooldown: a parry within the cooldown of the
-- last cast would show an icon for a spell that cannot be used yet. So the cast
-- time is noted (own clock, no cooldown value is read: those are secret in
-- combat) and the icon waits until at most READY_EARLY seconds of the
-- cooldown are left.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T = ns.L, ns.T
local Rogue = ns.Rogue
local Sound = ns.Sound

local RIPOSTE = { 14251 }
local IS_RIPOSTE = { [14251] = true }
local SOUND_GAP = 1   -- seconds between two sounds at most once
local READY_EARLY = 0.5   -- the icon shows when this many seconds of the cooldown are left
local COOLDOWN_FALLBACK = 6   -- seconds, when the client gives no base cooldown

local DEFAULTS = {
    on = true, blink = true, size = 56, x = 0, y = 140,
    soundOn = false, sound = Sound.DEFAULT, soundVolume = 100,
}
Rogue.RIPOSTE_SIZE_MIN, Rogue.RIPOSTE_SIZE_MAX = 24, 128

function Rogue:RiposteSettings()
    local s = self:Settings()
    s.riposte = s.riposte or {}
    return s.riposte
end

function Rogue:RiposteGet(field)
    local v = self:RiposteSettings()[field]
    if v == nil then return DEFAULTS[field] end
    return v
end

-- the learned rank (nil = not learned)
local function SpellID()
    for _, id in ipairs(RIPOSTE) do
        if ns.IsKnown(id) then return id end
    end
end
function Rogue:RiposteKnown() return SpellID() ~= nil end
-- the spell's name from the client (never written into the code)
function Rogue:RiposteName() return ns.SpellName(SpellID() or RIPOSTE[1]) or "?" end

-- ---------------------------------------------------------------------------
-- The icon
-- ---------------------------------------------------------------------------
local f = CreateFrame("Frame", "BeautifulRogueRiposte", UIParent)
f:SetFrameStrata("HIGH")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(false)
f:RegisterForDrag("LeftButton")
f:Hide()
ns.Skin(f, T.hudPanel, T.comboMax)
f.icon = f:CreateTexture(nil, "ARTWORK")
f.icon:SetPoint("TOPLEFT", 1, -1)
f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
f.hint = ns.Text(f, 11)
f.hint:SetPoint("TOP", f, "BOTTOM", 0, -4)
ns.Color(f.hint, T.hudText)
f.hint:Hide()
Rogue.riposteFrame = f

local blink = f:CreateAnimationGroup()
blink:SetLooping("BOUNCE")
local fade = blink:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0.2)
fade:SetDuration(0.35)
fade:SetSmoothing("IN_OUT")
f.blink = blink

-- state: usable (game), overlay (glow events), consumed (cast since then),
-- fighting (own flag: InCombatLockdown is still false during
-- PLAYER_REGEN_DISABLED), preview (window open), shown (last evaluation);
-- counters for /brogue status
local usable, overlay, consumed, fighting, preview, shown = false, false, false, false, false, false
local seen, lastShown, lastSound = 0, nil, 0
local readyAt, waitTimer = 0, false   -- GetTime() from which the icon may show; wake-up pending

-- the cooldown of the spell in seconds (static base value from the client)
local function CooldownSeconds()
    local id = SpellID()
    if id and GetSpellBaseCooldown then
        local ok, ms = pcall(GetSpellBaseCooldown, id)
        if ok and type(ms) == "number" and not ns.IsSecret(ms) and ms > 0 then return ms / 1000 end
    end
    return COOLDOWN_FALLBACK
end

local function Place()
    local size = Rogue:RiposteGet("size")
    f:SetSize(size, size)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", Rogue:RiposteGet("x"), Rogue:RiposteGet("y"))
end

local function Wanted()
    return Rogue:IsActive() and Rogue:RiposteGet("on") and SpellID() ~= nil
end

function Rogue:RiposteReady()
    return (usable or overlay) and not consumed and fighting and GetTime() >= readyAt
end

local function Apply()
    local show = preview or (Wanted() and Rogue:RiposteReady())
    if not show then
        blink:Stop()
        f:SetAlpha(1)
        f:EnableMouse(false)
        f:Hide()
        return
    end
    Place()
    f.icon:SetTexture(ns.SpellIcon(SpellID() or RIPOSTE[1]) or "Interface\\Icons\\INV_Misc_QuestionMark")
    f.icon:SetDesaturated(preview and not Rogue:RiposteKnown())
    f.hint:SetShown(preview)
    f:EnableMouse(preview)
    f:Show()
    if Rogue:RiposteGet("blink") then
        if not blink:IsPlaying() then blink:Play() end
    else
        blink:Stop()
        f:SetAlpha(1)
    end
end
Rogue.ApplyRiposte = Apply

local function PlayAlert()
    if not Rogue:RiposteGet("soundOn") then return end
    local now = GetTime()
    if now - lastSound < SOUND_GAP then return end
    lastSound = now
    Sound.Play(Rogue:RiposteGet("sound"), Rogue:RiposteGet("soundVolume"))
end

local Update

-- after every change of the state: a fresh window plays the sound
local function Evaluate()
    if not (usable or overlay) then consumed = false end
    local now = Wanted() and Rogue:RiposteReady()
    -- parried within the cooldown: look again when it is nearly over
    local wait = readyAt - GetTime()
    if wait > 0 and (usable or overlay) and not consumed and fighting and not waitTimer then
        waitTimer = true
        C_Timer.After(wait + 0.02, function()
            waitTimer = false
            Update()
        end)
    end
    if now and not shown then
        seen, lastShown = seen + 1, GetTime()
        PlayAlert()
    end
    shown = now and true or false
    Apply()
end

-- reads the game, then shows / hides
function Update()
    local id = SpellID()
    if not id then
        usable, overlay, consumed = false, false, false
    elseif C_Spell and C_Spell.IsSpellUsable then
        local ok, u = pcall(C_Spell.IsSpellUsable, id)
        if ok and u ~= nil and not ns.IsSecret(u) then
            usable = u and true or false
        end
    end
    Evaluate()
end

-- ---------------------------------------------------------------------------
-- Moving: only in the preview (the Riposte window is open)
-- ---------------------------------------------------------------------------
f:SetScript("OnDragStart", function(self)
    if preview then self:StartMoving() end
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local cx, cy = self:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if cx and ux then
        local s = Rogue:RiposteSettings()
        s.x, s.y = math.floor(cx - ux + 0.5), math.floor(cy - uy + 0.5)
    end
    Place()
end)

function Rogue:SetRiposte(field, value)
    self:RiposteSettings()[field] = value
    Apply()
end

function Rogue:ResetRipostePosition()
    local s = self:RiposteSettings()
    s.x, s.y = nil, nil
    Apply()
end

function Rogue:SetRipostePreview(on)
    preview = on and true or false
    f.hint:SetText(L["%s: drag to move"]:format(Rogue:RiposteName()))
    Apply()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
for _, ev in ipairs({ "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE", "SPELLS_CHANGED" }) do
    Rogue:Event(ev, Update)
end
-- the fight itself is followed even while the module is off (ns.RegisterEvent,
-- not Rogue:Event): switched on again after a fight, nothing old may show
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    fighting = true
    if ns.ready and Rogue:IsActive() then Update() end
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    usable, overlay, consumed, fighting = false, false, false, false
    if ns.ready then Evaluate() end
end)
-- energy comes often: one pass per moment
local pending
Rogue:UnitEvent("UNIT_POWER_UPDATE", "player", function()
    if pending or not fighting or not Wanted() then return end
    pending = true
    C_Timer.After(0.05, function()
        pending = false
        Update()
    end)
end)

-- the glow events, where the client has them; a secret ID is skipped
Rogue:Event("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, spellID)
    if ns.IsSecret(spellID) or not IS_RIPOSTE[spellID] then return end
    overlay = true
    Update()
end)
Rogue:Event("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, spellID)
    if ns.IsSecret(spellID) or not IS_RIPOSTE[spellID] then return end
    overlay = false
    Update()
end)

Rogue:On("PLAYER_CAST", function(spellID)
    if not IS_RIPOSTE[spellID] then return end
    consumed = true
    readyAt = GetTime() + CooldownSeconds() - READY_EARLY
    Evaluate()
end)

ns.On("LOGIN", function()
    fighting = ns.InCombat()
    Update()
end)
-- module switched off (or on): its events were quiet, so read afresh
ns.On("MODULES_CHANGED", function()
    if not ns.ready then return end
    if Rogue:IsActive() then Update() else Evaluate() end
end)
ns.On("SETTINGS_RESET", function() if ns.ready then Evaluate() end end)

Rogue:Status(function()
    if not SpellID() then return L["%s: not learned"]:format(Rogue:RiposteName()) end
    local line = L["%s: usable %s, shown %d times"]:format(Rogue:RiposteName(), usable and L["yes"] or L["no"], seen)
    if lastShown then line = line .. "  ·  " .. L["last %d s ago"]:format(math.floor(GetTime() - lastShown)) end
    -- internal state, for a report when the icon stays away (not translated)
    line = line .. ("  ·  [usable=%s glow=%s used=%s fight=%s wait=%.1fs]"):format(
        tostring(usable), tostring(overlay), tostring(consumed), tostring(fighting), math.max(0, readyAt - GetTime()))
    return line
end)
