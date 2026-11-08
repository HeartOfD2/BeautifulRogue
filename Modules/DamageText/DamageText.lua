-- ---------------------------------------------------------------------------
-- Damage numbers module: font and behavior of the floating combat numbers.
-- For every class, on by default, but every effect is OFF until the player switches it on:
-- an active module alone changes nothing in the game.
--   world numbers  the numbers above the heads: DAMAGE_TEXT_FONT (read by the client at
--                  login, so a new font needs a log-out/log-in) and the CVars for size,
--                  gravity and duration (live)
--   scrolling text SetFont on the client's own font objects
-- The module reads no combat values and no combat log; it only sets fonts and CVars.
-- Settings are account-wide (BeautifulRogueDB.damageText) because the CVars are. The names
-- of the global, the CVars and the font objects can differ between clients:
-- every one is checked for existence and called under pcall.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

-- the switch is account-wide like the settings: switched off on one character,
-- no other character may set the fonts and CVars again
local DT = ns.NewModule("damagetext", {
    title = L["Damage numbers"],
    desc = L["Font and behavior of the floating combat numbers."],
    accountWide = true,
})
ns.DamageText = DT

DT.OUTLINES = { "none", "thin", "thick" }
DT.RANGES = {   -- { min, max, slider step }
    worldScale    = { 0.5, 5, 0.1 },
    worldGravity  = { -10, 10, 0.5 },
    worldDuration = { 0.1, 3, 0.01 },
    sctShadow     = { 0, 10, 1 },
}

DT.DEFAULTS = {
    worldOn = true, worldFont = ns.FONT_CHOICE_DEFAULT, worldScale = 1, worldGravity = 0.5, worldDuration = 1,
    sctOn = true, sctFont = ns.FONT_CHOICE_DEFAULT, sctOutline = "none", sctMono = false, sctShadow = 0,
}

-- CVar of each world setting; the client may know the name with or without _v2
local CVARS = {
    worldScale = "WorldTextScale", worldGravity = "WorldTextGravity", worldDuration = "WorldTextRampDuration",
}
-- the game's own font objects of the scrolling combat text
local SCT_OBJECTS = { "CombatTextFont", "DamageNumberFont", "WorldFont" }

-- the account-wide table (created on first write)
local function Store()
    local a = ns.Acct()
    if type(a.damageText) ~= "table" then a.damageText = {} end
    return a.damageText
end

-- a stored value, or the default when nothing (valid) is stored
function DT:Get(key)
    local v = Store()[key]
    local d = self.DEFAULTS[key]
    if key == "worldFont" or key == "sctFont" then
        return (type(v) == "string" and ns.FontEntry(v)) and v or d
    elseif key == "sctOutline" then
        for _, o in ipairs(self.OUTLINES) do if o == v then return v end end
        return d
    elseif type(d) == "number" then
        if type(v) ~= "number" or v ~= v then return d end
        local r = self.RANGES[key]
        return math.max(r[1], math.min(r[2], v))
    end
    if type(v) == "boolean" then return v end   -- (false must stay false when the default is true)
    return d
end

function DT:Set(key, value)
    Store()[key] = value
    self:Apply()
end

-- the alphabet the client language needs besides Latin; none of our fonts has these
local NEEDS = { ruRU = "cyrillic", koKR = "korean", zhCN = "chinese", zhTW = "chinese" }

-- does the font have the letters of the client language?
function DT.FontSuits(key)
    local need = NEEDS[ns.LOCALE]
    if not need then return true end
    local f = ns.FontEntry(key)
    return f ~= nil and f.scripts ~= nil and f.scripts[need] == true
end

-- the file to use for a catalog font: loads, and suits the language; else nil
function DT.FontFile(key)
    if not DT.FontSuits(key) then return nil end
    local path = ns.FontPath(key)
    if not path or not ns.FontUsable(path) then return nil end
    return path
end

-- the module runs for this character (checked without ns.ready: the font has to be set
-- while the saved variables load, before the player is in the world)
function DT:Wanted()
    return self:IsClassAllowed() and self:IsEnabledSetting()
end

-- ---------------------------------------------------------------- world numbers
local function CVarNames(base)
    local names = {}
    for _, n in ipairs({ base, base .. "_v2" }) do
        local ok, cur = pcall(GetCVar, n)
        if ok and cur ~= nil then names[#names + 1] = n end
    end
    return names
end

local pendingCVars = false   -- set in combat: done after the fight

local function SetCVars(want)
    local keep = Store()
    keep.orig = type(keep.orig) == "table" and keep.orig or {}
    for key, base in pairs(CVARS) do
        for _, name in ipairs(CVarNames(base)) do
            if want then
                local target = tostring(DT:Get(key))
                if keep.orig[name] == nil then keep.orig[name] = GetCVar(name) end
                if tonumber(GetCVar(name)) ~= tonumber(target) then pcall(SetCVar, name, target) end
            elseif keep.orig[name] ~= nil then   -- switched off: give the game its own value back
                pcall(SetCVar, name, keep.orig[name])
                keep.orig[name] = nil
            end
        end
    end
    if next(keep.orig) == nil then keep.orig = nil end
end

-- the world font this session set (and the game's one before it): switched
-- off, the global goes back and the chat says that it takes a new login
local worldFontSet, gameWorldFont

local function ApplyWorld(on)
    if on then
        local path = DT.FontFile(DT:Get("worldFont"))
        if path then
            if not worldFontSet then gameWorldFont = rawget(_G, "DAMAGE_TEXT_FONT") end
            _G.DAMAGE_TEXT_FONT = path
            worldFontSet = path
        end
    elseif worldFontSet then
        if gameWorldFont then _G.DAMAGE_TEXT_FONT = gameWorldFont end
        worldFontSet = nil
        if ns.ready then
            ns.Print(L["Damage numbers: the game's font for the numbers above the heads comes back after logging out and in again (/reload is not enough)."])
        end
    end
    local touched = Store().orig ~= nil
    if not on and not touched then return end   -- nothing was ever changed: leave the game alone
    if InCombatLockdown() then
        pendingCVars = true
        return
    end
    pendingCVars = false
    SetCVars(on)
end

-- ---------------------------------------------------------------- scrolling text
local originals = {}   -- font object name -> { path, size, flags, shadowX, shadowY } as the game had it

local function Flags()
    local f = ({ none = "", thin = "OUTLINE", thick = "THICKOUTLINE" })[DT:Get("sctOutline")]
    if DT:Get("sctMono") then f = (f ~= "" and f .. ", " or "") .. "MONOCHROME" end
    return f
end

local function ApplySct(on)
    local path = on and DT.FontFile(DT:Get("sctFont")) or nil
    for _, name in ipairs(SCT_OBJECTS) do
        local obj = rawget(_G, name)
        if type(obj) == "table" and obj.GetFont and obj.SetFont then
            if path then
                if not originals[name] then
                    local p, s, f = obj:GetFont()
                    local sx, sy
                    if obj.GetShadowOffset then sx, sy = obj:GetShadowOffset() end
                    originals[name] = { p, s, f, sx, sy }
                end
                local o = originals[name]
                pcall(obj.SetFont, obj, path, o[2] or 24, Flags())
                local shadow = DT:Get("sctShadow")
                if shadow > 0 and obj.SetShadowOffset then pcall(obj.SetShadowOffset, obj, shadow, -shadow) end
                if shadow == 0 and obj.SetShadowOffset and o[4] then pcall(obj.SetShadowOffset, obj, o[4], o[5]) end
            elseif originals[name] then   -- off: back to the game's font
                local o = originals[name]
                if o[1] then pcall(obj.SetFont, obj, o[1], o[2] or 24, o[3] or "") end
                if o[4] and obj.SetShadowOffset then pcall(obj.SetShadowOffset, obj, o[4], o[5]) end
                originals[name] = nil
            end
        end
    end
end

-- put every setting in force (or back, when the module or a block is off)
function DT:Apply()
    local on = self:Wanted()
    ApplyWorld(on and self:Get("worldOn"))
    ApplySct(on and self:Get("sctOn"))
end

ns.On("DB_READY", function() DT:Apply() end)
ns.On("LOGIN", function() DT:Apply() end)   -- the CVars may only exist by now
ns.On("SETTINGS_RESET", function() DT:Apply() end)
function DT:OnActiveChanged() self:Apply() end

DT:Event("PLAYER_REGEN_ENABLED", function()
    if pendingCVars then DT:Apply() end
end)

DT:Reset({ key = "damagetext", group = "extras", order = 95, accountWide = true,
    label = L["Damage numbers"],
    desc = L["Both blocks go back to their defaults and the game's own values; a changed world font needs a new login."],
    reset = function()
        local keep = Store()
        local orig = keep.orig
        for k in pairs(keep) do keep[k] = nil end
        keep.orig = orig   -- Apply gives the CVars back and then drops it
    end })

DT:Status(function()
    if not DT:Get("worldOn") and not DT:Get("sctOn") then return L["Damage numbers: all off"] end
    return L["Damage numbers: world %s, scrolling text %s"]:format(
        DT:Get("worldOn") and L["active"] or L["off"], DT:Get("sctOn") and L["active"] or L["off"])
end)
