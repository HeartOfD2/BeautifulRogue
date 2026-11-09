-- ---------------------------------------------------------------------------
-- Sharpening stones: the second temporary enchant of a weapon. On this client a
-- weapon carries an imbue (poisons) and a temporary enchant (stones, oils) at
-- once, and C_Item.GetWeaponEnchantInfo lists both. This file holds the stone
-- list, the ranking (per character), which stone a hand gets and the reading of
-- the enchant list. The button sits in the poison tiles (Poisons.lua), the
-- settings have their own page (StonesPage.lua).
-- ---------------------------------------------------------------------------
local _, ns = ...
local Rogue = ns.Rogue

-- kind: the weapons a stone works on ("sharp" = bladed, "blunt", "any");
-- the order is the default ranking: per tier the sharpening stone first
Rogue.STONES = {
    { id = 18262, kind = "any" },     -- Elemental Sharpening Stone
    { id = 12404, kind = "sharp" },   -- Dense Sharpening Stone
    { id = 12643, kind = "blunt" },   -- Dense Weightstone
    { id = 7964,  kind = "sharp" },   -- Solid Sharpening Stone
    { id = 7965,  kind = "blunt" },   -- Solid Weightstone
    { id = 2871,  kind = "sharp" },   -- Heavy Sharpening Stone
    { id = 3241,  kind = "blunt" },   -- Heavy Weightstone
    { id = 2863,  kind = "sharp" },   -- Coarse Sharpening Stone
    { id = 3240,  kind = "blunt" },   -- Coarse Weightstone
    { id = 2862,  kind = "sharp" },   -- Rough Sharpening Stone
    { id = 3239,  kind = "blunt" },   -- Rough Weightstone
}
Rogue.STONE_ICON = "Interface\\Icons\\INV_Stone_SharpeningStone_01"
Rogue.MAX_CUSTOM_STONES = 8
Rogue.STONE_KINDS = { "sharp", "blunt", "any" }

local BUILTIN_KIND = {}
for _, s in ipairs(Rogue.STONES) do BUILTIN_KIND[s.id] = s.kind end

-- weapon subclasses (Enum.ItemWeaponSubclass): axes, polearm, swords, dagger
-- take sharpening stones; maces, staff and fist weapons weightstones
local SHARP = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [15] = true }
local BLUNT = { [4] = true, [5] = true, [10] = true, [13] = true }
local WEAPON_CLASS = 2

-- ---------------------------------------------------------------------------
-- Settings (per character): { order = {itemID...}, custom = {[itemID] = kind},
-- pick = { MH = itemID, OH = itemID }, button = bool, warn = bool }
-- ---------------------------------------------------------------------------
function Rogue:StoneSettings()
    local s = self:Settings()
    local st = s.stones
    if type(st) ~= "table" then
        st = {}
        s.stones = st
    end
    st.order = st.order or {}
    st.custom = st.custom or {}
    st.pick = st.pick or {}
    return st
end

function Rogue:StoneButtonOn() return self:StoneSettings().button ~= false end
function Rogue:StoneWarnOn() return self:StoneSettings().warn ~= false end
function Rogue:IsCustomStone(id) return BUILTIN_KIND[id] == nil end

function Rogue:StoneKind(id)
    return BUILTIN_KIND[id] or self:StoneSettings().custom[id] or "any"
end

-- the ranking: the saved order first, then built-ins it doesn't have yet, then
-- own items (sorted by ID); entries that no longer exist drop out
function Rogue:StoneOrder()
    local st = self:StoneSettings()
    local seen, out = {}, {}
    local function add(id)
        if type(id) == "number" and not seen[id] and (BUILTIN_KIND[id] or st.custom[id]) then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    for _, id in ipairs(st.order) do add(id) end
    for _, s in ipairs(self.STONES) do add(s.id) end
    local own = {}
    for id in pairs(st.custom) do own[#own + 1] = id end
    table.sort(own)
    for _, id in ipairs(own) do add(id) end
    st.order = out
    return out
end

function Rogue:MoveStone(id, dir)
    local order = self:StoneOrder()
    local i = ns.IndexOf(order, id)
    local j = i and i + dir
    if not j or j < 1 or j > #order then return end
    order[i], order[j] = order[j], order[i]
    ns.Fire("ROGUE_STONE_CHOICE")
end

function Rogue:DefaultStoneOrder()
    self:StoneSettings().order = {}
    ns.Fire("ROGUE_STONE_CHOICE")
end

-- adds an own item; returns true or an error text key
function Rogue:AddCustomStone(id, kind)
    local st = self:StoneSettings()
    if BUILTIN_KIND[id] or st.custom[id] then return "already" end
    local n = 0
    for _ in pairs(st.custom) do n = n + 1 end
    if n >= self.MAX_CUSTOM_STONES then return "full" end
    st.custom[id] = kind or "any"
    self:StoneOrder()
    ns.ItemName(id)   -- asks the client to load the item
    ns.Fire("ROGUE_STONE_CHOICE")
    return true
end

function Rogue:RemoveCustomStone(id)
    local st = self:StoneSettings()
    st.custom[id] = nil
    for hand, pick in pairs(st.pick) do
        if pick == id then st.pick[hand] = nil end
    end
    self:StoneOrder()
    ns.Fire("ROGUE_STONE_CHOICE")
end

function Rogue:StoneName(id)
    return ns.ItemName(id) or ns.L["Item %d"]:format(id)
end

-- ---------------------------------------------------------------------------
-- Which stone a hand gets
-- ---------------------------------------------------------------------------
-- "sharp", "blunt", "none" (no weapon: shield, off-hand item) or nil (unknown)
function Rogue:WeaponKind(hand)
    local id = GetInventoryItemID("player", self.HANDS[hand])
    if not id then return "none" end
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
    if classID == nil then return nil end
    if classID ~= WEAPON_CLASS then return "none" end
    if SHARP[subID] then return "sharp" end
    if BLUNT[subID] then return "blunt" end
    return nil
end

function Rogue:StoneFits(id, hand)
    local w = self:WeaponKind(hand)
    if w == "none" then return false end
    local k = self:StoneKind(id)
    return k == "any" or w == nil or k == w
end

function Rogue:StonePick(hand) return self:StoneSettings().pick[hand] end
function Rogue:SetStonePick(hand, id)
    self:StoneSettings().pick[hand] = id
    ns.Fire("ROGUE_STONE_CHOICE", hand)
end

-- the stone the button applies: itemID or nil, plus the pick when it is missing.
-- A pick that doesn't fit the weapon (now) or the level gives way to the ranking.
function Rogue:StoneFor(hand)
    local pick = self:StonePick(hand)
    if pick and self:StoneFits(pick, hand) and self:LevelOK(pick) then
        if ns.ItemCount(pick) > 0 then return pick end
        return nil, pick
    end
    for _, id in ipairs(self:StoneOrder()) do
        if ns.ItemCount(id) > 0 and self:StoneFits(id, hand) and self:LevelOK(id) then return id end
    end
end

-- ---------------------------------------------------------------------------
-- Reading: both temporary enchants of a weapon from the list API
-- ---------------------------------------------------------------------------
local WEAPON_SLOT = { MH = "MainHand", OH = "OffHand" }

-- ok, imbue, temp; each enchant is { ms = time left, charges, id } or nil.
-- ok = false when the API is missing or a value is secret: the caller falls back
function Rogue:ReadEnchantList(hand)
    local fn = C_Item and C_Item.GetWeaponEnchantInfo
    local WS, ET = Enum and Enum.WeaponSlot, Enum and Enum.ItemEnchantType
    local slot = WS and WS[WEAPON_SLOT[hand]]
    if not (fn and slot and ET and ET.Imbue and ET.Temporary) then return false end
    local ok, list = pcall(fn, slot)
    if not ok or ns.IsSecret(list) then return false end
    local imbue, temp
    if type(list) == "table" then
        for _, e in ipairs(list) do
            local has, kind, left = e.hasEnchant, e.enchantType, e.timeLeft
            if ns.IsSecret(has) or ns.IsSecret(kind) or ns.IsSecret(left)
                    or ns.IsSecret(e.charges) or ns.IsSecret(e.enchantID) then
                return false
            end
            if has and type(left) == "number" and left > 0 then
                local v = { ms = left, charges = e.charges, id = e.enchantID }
                if kind == ET.Imbue then imbue = v elseif kind == ET.Temporary then temp = v end
            end
        end
    end
    return true, imbue, temp
end

-- the stone on each weapon: { expires = GetTime() } / false (none) / nil
-- (never read). Kept while the list can't be read (secret in combat).
Rogue.stoneState = {}

function Rogue:SetStoneRead(hand, temp)
    self.stoneState[hand] = temp and { expires = GetTime() + temp.ms / 1000 } or false
end

-- seconds left (nil = no stone or unknown), and whether it is known
function Rogue:StoneLeft(hand)
    local st = self.stoneState[hand]
    if not st then return nil, st == false end
    local left = st.expires - GetTime()
    if left <= 0 then
        self.stoneState[hand] = false
        return nil, true
    end
    return left, true
end
