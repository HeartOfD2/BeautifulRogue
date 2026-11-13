-- ---------------------------------------------------------------------------
-- Rogue module: poison tracker, Slice and Dice timer, weapon swap macros and
-- rogue macro templates. Active on rogues only (and only while switched on).
-- This file defines the module and the poison model; the parts hook in from
-- their own files (Options, Templates, Poisons, SliceAndDice, WeaponMacros).
-- Poisons are identified by item ID and their names are read off the items,
-- so everything works in any client language.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

local Rogue = ns.NewModule("rogue", {
    title = L["Rogue"],
    desc = L["Poison tracker with one-click apply, Slice and Dice timer, an alert after a parry, weapon swap macros and macro templates."],
    classes = { ROGUE = true },
    classHint = L["only for rogues"],
})
ns.Rogue = Rogue

-- poison types and their item IDs, lowest rank first. New ranks of a type go
-- to the end of its list, new types to the end of the table (menu order).
Rogue.POISONS = {
    { key = "instant",   ids = { 6947, 6949, 6950, 8926, 8927, 8928 } },        -- Instant Poison I-VI
    { key = "deadly",    ids = { 2892, 2893, 8984, 8985, 20844 } },   -- Deadly Poison I-V
    { key = "wound",     ids = { 10918, 10920, 10921, 10922 } },        -- Wound Poison I-IV
    { key = "mindnumb",  ids = { 5237, 6951, 9186 } },                    -- Mind-numbing Poison I-III
    { key = "crippling", ids = { 3775, 3776 } },                          -- Crippling Poison I-II
    { key = "sebacious", ids = { 217345 } },                              -- level 60
    { key = "numbing",   ids = { 217346 } },                              -- level 60
    { key = "atrophic",  ids = { 217347 } },                              -- level 60
    { key = "occult",    ids = { 226374, 234444 } },                      -- I (level 54), II (level 60)
}
Rogue.POISON_ICON = "Interface\\Icons\\Trade_BrewPoison"
Rogue.HANDS = { MH = 16, OH = 17 }

local KEY_OF_ITEM, RANK_OF_ITEM = {}, {}
for _, p in ipairs(Rogue.POISONS) do
    for rank, id in ipairs(p.ids) do
        KEY_OF_ITEM[id], RANK_OF_ITEM[id] = p.key, rank
    end
end

function Rogue:PoisonKeyOfItem(id) return KEY_OF_ITEM[id] end

function Rogue:Settings()
    local s = ns.Char().modules.rogue
    if not s then
        s = {}
        ns.Char().modules.rogue = s
    end
    s.poison = s.poison or {}
    return s
end

-- ---------------------------------------------------------------------------
-- Features the player can switch off (sharpening stones, Riposte icon).
-- A feature is on while the module runs and its setting is not false. Its
-- events sit on frames of its own that are registered only while it is on, so
-- a switched-off feature costs the game no event at all and the module needs
-- no check at the places that use it: they ask Rogue:StonesOn() / RiposteOn().
--
--   local F = Rogue:NewFeature(key, setting)
--   F:Event(event, fn) / F:UnitEvent(event, unit, fn) / F:On(message, fn)
--   F:OnChange(fn(on))     runs after it was switched on or off
--   Rogue:SetFeature(key, on)    writes the setting and switches
-- ---------------------------------------------------------------------------
local Feature = {}
Feature.__index = Feature
Rogue.features = {}

local function Dispatch(list, event, ...)
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then
            local handler = geterrorhandler and geterrorhandler()
            if handler then handler(err) else print(err) end
        end
    end
end

function Rogue:NewFeature(key, setting)
    local F = setmetatable({ key = key, setting = setting, on = false,
        events = {}, unitEvents = {}, units = {}, registered = {}, changed = {} }, Feature)
    self.features[key] = F
    return F
end

local function FeatureFrame(F, field, handlers)
    local f = F[field]
    if not f then
        f = CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event, ...)
            local list = handlers[event]
            if list then Dispatch(list, event, ...) end
        end)
        F[field] = f
    end
    return f
end

function Feature:Event(event, fn)
    local list = self.events[event]
    if not list then
        list = {}
        self.events[event] = list
    end
    list[#list + 1] = fn
    if self.on then self:Register() end
end

function Feature:UnitEvent(event, unit, fn)
    local list = self.unitEvents[event]
    if not list then
        list = {}
        self.unitEvents[event] = list
    end
    list[#list + 1] = fn
    self.units[event] = unit
    if self.on then self:Register() end
end

-- an internal message, answered only while the feature is on
function Feature:On(message, fn)
    ns.On(message, function(...) if self.on then fn(...) end end)
end

function Feature:OnChange(fn) self.changed[#self.changed + 1] = fn end

-- events on or off (unknown events of other client generations are skipped quietly)
function Feature:Register()
    local f = FeatureFrame(self, "frame", self.events)
    local uf = FeatureFrame(self, "uframe", self.unitEvents)
    for event in pairs(self.events) do
        if self.on and not self.registered[event] then
            self.registered[event] = pcall(f.RegisterEvent, f, event) or nil
        elseif not self.on and self.registered[event] then
            f:UnregisterEvent(event)
            self.registered[event] = nil
        end
    end
    for event in pairs(self.unitEvents) do
        local key = "unit:" .. event
        if self.on and not self.registered[key] then
            self.registered[key] = pcall(uf.RegisterUnitEvent, uf, event, self.units[event]) or nil
        elseif not self.on and self.registered[key] then
            uf:UnregisterEvent(event)
            self.registered[key] = nil
        end
    end
end

function Feature:IsWanted()
    return Rogue:IsActive() and Rogue:Settings()[self.setting] ~= false
end

-- brings the events and the feature's own state in line with module and setting
function Feature:Sync()
    local want = self:IsWanted() and true or false
    if want == self.on then return end
    self.on = want
    self:Register()
    for _, fn in ipairs(self.changed) do ns.SafeCall(fn, want) end
end

Rogue.featureStones = Rogue:NewFeature("stones", "stonesEnabled")
Rogue.featureRiposte = Rogue:NewFeature("riposte", "riposteEnabled")
function Rogue:StonesOn() return self.featureStones.on end
function Rogue:RiposteOn() return self.featureRiposte.on end

function Rogue:SetFeature(key, on)
    local F = self.features[key]
    if not F then return end
    self:Settings()[F.setting] = on and true or false
    F:Sync()
end

local function SyncFeatures()
    for _, F in pairs(Rogue.features) do F:Sync() end
end
ns.On("LOGIN", SyncFeatures)
ns.On("MODULES_CHANGED", SyncFeatures)
ns.On("SETTINGS_RESET", function() if ns.ready then SyncFeatures() end end)

-- ---------------------------------------------------------------------------
-- Names and the poisons in the bags, read once per change of the bags (never
-- per second): the poisons by item ID, the localized names without the rank
-- numeral, from the items in the bags, else from the client's item cache
-- ---------------------------------------------------------------------------
local baseName = {}   -- key -> localized name without the rank numeral
local poisonBag = {}  -- itemID -> name (true while the name is not known) of the poisons in the bags
local bagsDirty, nameRev = true, 0

local function StripRank(name) return (name:gsub("%s+[IVXLCDM]+$", "")) end

local function ScanBag(id, name)
    if KEY_OF_ITEM[id] then poisonBag[id] = name or true end
end

local function Bags()
    if not bagsDirty then return end
    bagsDirty = false
    nameRev = nameRev + 1
    wipe(poisonBag)
    wipe(baseName)
    ns.ForEachBagItem(ScanBag)
    for id, name in pairs(poisonBag) do
        if name ~= true then baseName[KEY_OF_ITEM[id]] = StripRank(name) end
    end
    for _, p in ipairs(Rogue.POISONS) do
        if not baseName[p.key] then
            local n = ns.ItemName(p.ids[1])
            if n then baseName[p.key] = StripRank(n) end
        end
    end
end

-- the bags or the item data changed: read them again with the next question
function Rogue:ItemsChanged() bagsDirty = true end

function Rogue:RefreshPoisonNames()
    bagsDirty = true
    Bags()
end

-- counts up whenever the names were read afresh (a failed reading of a tooltip is tried again then)
function Rogue:NameRev()
    Bags()
    return nameRev
end

-- every type has its name (the tooltip readers need all of them)
function Rogue:PoisonNamesReady()
    Bags()
    for _, p in ipairs(self.POISONS) do
        if not baseName[p.key] then return false end
    end
    return true
end

function Rogue:PoisonName(key)
    if not key then return L["Best available"] end
    Bags()
    return baseName[key] or key
end

function Rogue:PoisonIcon(key)
    for _, p in ipairs(self.POISONS) do
        if p.key == key then return ns.ItemIcon(p.ids[1]) or self.POISON_ICON end
    end
    return self.POISON_ICON
end

-- the minimum level from the item data (nil while not loaded); it never
-- changes, so a number read once is kept
local minLevelOf = {}
function Rogue:ItemMinLevel(id)
    local known = minLevelOf[id]
    if known then return known end
    if not (C_Item and C_Item.GetItemInfo) then return nil end
    local minLevel = select(5, C_Item.GetItemInfo(id))
    if type(minLevel) ~= "number" then return nil end
    minLevelOf[id] = minLevel
    return minLevel
end

-- can the character use the item? Unknown item data counts as yes
function Rogue:LevelOK(id)
    local need = self:ItemMinLevel(id)
    return not need or need <= (UnitLevel("player") or 0)
end

-- highest rank in the bags of one type (nil = of any type) that the character
-- can use (anyLevel: also the ones above its level): name, itemID
function Rogue:FindPoison(key, anyLevel)
    Bags()
    local bestName, bestID, bestRank
    for id, name in pairs(poisonBag) do
        local k = KEY_OF_ITEM[id]
        if (not key or k == key) and (anyLevel or self:LevelOK(id)) then
            local rank = RANK_OF_ITEM[id]
            if not bestRank or rank > bestRank or (rank == bestRank and id > bestID) then
                bestName, bestID, bestRank = (name ~= true and name) or ns.ItemName(id), id, rank
            end
        end
    end
    return bestName, bestID
end

-- lowest minimum level among the bag items of one type (nil = none in the bags
-- or level unknown): the choice shows it when only higher ranks are there
function Rogue:PoisonLevelNeeded(key)
    Bags()
    local low
    for id in pairs(poisonBag) do
        if KEY_OF_ITEM[id] == key then
            local need = self:ItemMinLevel(id)
            if need and (not low or need < low) then low = need end
        end
    end
    return low
end

-- the player's pick per hand (nil = whatever fits best)
function Rogue:Choice(hand) return self:Settings().poison[hand] end
function Rogue:SetChoice(hand, key)
    self:Settings().poison[hand] = key
    ns.Fire("ROGUE_POISON_CHOICE", hand)
end

-- what a hand gets: the pick, else what was last seen on that weapon
Rogue.lastSeen = {}
function Rogue:EffectiveKey(hand) return self:Choice(hand) or self.lastSeen[hand] end

-- what the weapon macros use: the pick, else Instant (main) / Crippling (off hand)
local MACRO_DEFAULT = { MH = "instant", OH = "crippling" }
function Rogue:MacroPoison(hand)
    local key = self:Choice(hand) or MACRO_DEFAULT[hand]
    local name, id = self:FindPoison(key)
    return name, id, key
end

-- icon picker: rogue abilities and poisons first
do
    -- fixed IDs on purpose: the icons must show for spells the character has not learned yet
    local spells = {
        1752, 53, 2098, 5171, 1784,     -- Sinister Strike, Backstab, Eviscerate, Slice and Dice, Stealth
        1776, 1766, 2983, 5277, 1856,   -- Gouge, Kick, Sprint, Evasion, Vanish
        2094, 6770, 1833, 408, 8676,    -- Blind, Sap, Cheap Shot, Kidney Shot, Ambush
        703, 1943, 8647, 1966, 1725,    -- Garrote, Rupture, Expose Armor, Feint, Distract
        921, 1804, 2836, 1842, 14251,   -- Pick Pocket, Pick Lock, Detect Traps, Disarm Trap, Riposte
        13877, 13750, 14177, 14278, 16511, -- Blade Flurry, Adrenaline Rush, Cold Blood, Ghostly Strike, Hemorrhage
        14183, 14185, 2764,             -- Premeditation, Preparation, Throw
    }
    ns.Rogue.FEATURED_SPELLS = spells
    function Rogue:OnEnable()
        local items = {}
        for _, p in ipairs(Rogue.POISONS) do items[#items + 1] = p.ids[1] end
        Rogue:Featured(spells, items)
        Rogue:RefreshPoisonNames()
    end
end

-- the item events only mark the snapshot as old; it is read at the next question.
-- Item data arrives for any item of any addon: only ours count.
Rogue:Event("BAG_UPDATE", function() Rogue:ItemsChanged() end)
Rogue:Event("GET_ITEM_INFO_RECEIVED", function(_, id)
    if type(id) == "number" and (KEY_OF_ITEM[id] or (Rogue.IsStoneItem and Rogue:IsStoneItem(id))) then Rogue:ItemsChanged() end
end)
Rogue:Event("PLAYER_LEVEL_UP", function() Rogue:ItemsChanged() end)
-- events were quiet while the module was off: read the bags afresh
ns.On("MODULES_CHANGED", function() Rogue:ItemsChanged() end)
