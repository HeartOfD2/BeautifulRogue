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
-- Names: from the items in the bags, else from the client's item cache
-- ---------------------------------------------------------------------------
local baseName = {}   -- key -> localized name without the rank numeral

local function StripRank(name) return (name:gsub("%s+[IVXLCDM]+$", "")) end

function Rogue:RefreshPoisonNames()
    wipe(baseName)
    ns.ForEachBagItem(function(id, name)
        local key = KEY_OF_ITEM[id]
        if key and name then baseName[key] = StripRank(name) end
    end)
    for _, p in ipairs(self.POISONS) do
        if not baseName[p.key] then
            local n = ns.ItemName(p.ids[1])
            if n then baseName[p.key] = StripRank(n) end
        end
    end
end

-- every type has its name (the tooltip readers need all of them)
function Rogue:PoisonNamesReady()
    for _, p in ipairs(self.POISONS) do
        if not baseName[p.key] then return false end
    end
    return true
end

function Rogue:PoisonName(key)
    if not key then return L["Best available"] end
    return baseName[key] or key
end

function Rogue:PoisonIcon(key)
    for _, p in ipairs(self.POISONS) do
        if p.key == key then return ns.ItemIcon(p.ids[1]) or self.POISON_ICON end
    end
    return self.POISON_ICON
end

-- the minimum level from the item data (nil while not loaded)
function Rogue:ItemMinLevel(id)
    if not (C_Item and C_Item.GetItemInfo) then return nil end
    local minLevel = select(5, C_Item.GetItemInfo(id))
    return type(minLevel) == "number" and minLevel or nil
end

-- can the character use the item? Unknown item data counts as yes
function Rogue:LevelOK(id)
    local need = self:ItemMinLevel(id)
    return not need or need <= (UnitLevel("player") or 0)
end

-- highest rank in the bags of one type (nil = of any type) that the character
-- can use (anyLevel: also the ones above its level): name, itemID
function Rogue:FindPoison(key, anyLevel)
    local bestName, bestID, bestRank
    ns.ForEachBagItem(function(id, name)
        local k = KEY_OF_ITEM[id]
        if k and (not key or k == key) and (anyLevel or self:LevelOK(id)) then
            local rank = RANK_OF_ITEM[id]
            if not bestRank or rank > bestRank or (rank == bestRank and id > bestID) then
                bestName, bestID, bestRank = name or ns.ItemName(id), id, rank
            end
        end
    end)
    return bestName, bestID
end

-- lowest minimum level among the bag items of one type (nil = none in the bags
-- or level unknown): the choice shows it when only higher ranks are there
function Rogue:PoisonLevelNeeded(key)
    local low
    ns.ForEachBagItem(function(id)
        if KEY_OF_ITEM[id] == key then
            local need = self:ItemMinLevel(id)
            if need and (not low or need < low) then low = need end
        end
    end)
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

Rogue:Event("BAG_UPDATE", function() Rogue:RefreshPoisonNames() end)
Rogue:Event("GET_ITEM_INFO_RECEIVED", function() Rogue:RefreshPoisonNames() end)
