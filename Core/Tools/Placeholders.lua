-- ---------------------------------------------------------------------------
-- Placeholders: words in macro text (templates) that the addon fills in when
-- it writes the macro, so the macro keeps up with the game:
--   {s:1752}    spell name in the client language (highest rank)
--   {s:1752:r}  spell name with its rank, e.g. "Sinister Strike(Rank 3)"
--   {w:W1}      weapon roles W1 / W2: each a weapon type and the weapon of
--   {w:W2}      that type you picked (equipped or in the bags); W1 and W2
--               are never the same weapon
--   {g:t1}      the trinkets (gear) in slot 13 / 14
--   {g:t2}
--   {c:name}    your own: a name with a value (account-wide)
-- (Split: Placeholders.lua = roles, weapons, filling; PlaceholderGear.lua =
-- changed gear, dialog, writing after combat; PlaceholderPage.lua = the page.)
-- Modules add their own through the Fill of their template group (the
-- rogue's {p:MH} / {p:OH}).
-- Changed gear: a dialog suggests W1 / W2 for the new weapons (after combat);
-- confirmed, the macros that use the gear are written anew
-- (sources: Placeholders.RegisterGearMacros).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L
local UI, Macros = ns.UI, ns.Macros

local Placeholders = { gearSources = {}, updaters = {} }
ns.Placeholders = Placeholders

local DAGGER = 15   -- Enum.ItemWeaponSubclass.Dagger
local ANY = -1
local WEAPON_CLASS = 2   -- Enum.ItemClass.Weapon
local DUAL_WIELD = 674
local NOT_HELD = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
                   INVTYPE_RELIC = true, INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true }

-- ---------------------------------------------------------------------------
-- Storage: roles per character, own placeholders account-wide
-- ---------------------------------------------------------------------------
local ROLE_DEFAULTS = { W1 = { type = DAGGER }, W2 = { type = ANY } }
Placeholders.ROLES = { "W1", "W2" }
Placeholders.GEAR_SLOTS = { 13, 14, 16, 17 }   -- trinkets and weapon hands

function Placeholders.CharStore()
    local c = ns.Char()
    c.placeholders = c.placeholders or {}
    local s = c.placeholders
    s.roles = s.roles or {}
    for role, def in pairs(ROLE_DEFAULTS) do
        s.roles[role] = s.roles[role] or {}
        if s.roles[role].type == nil then s.roles[role].type = def.type end
    end
    return s
end
function Placeholders.Roles() return Placeholders.CharStore().roles end

-- ---------------------------------------------------------------------------
-- Switches (per character, Modules page): gear placeholders {w:} {g:} with the
-- weapon roles and the gear check, own placeholders {c:}. Off: they are no
-- longer filled in; with both off the Placeholders page is gone.
-- ---------------------------------------------------------------------------
-- kept apart from the roles: "Weapon roles" on the Reset page leaves them alone
local function CharSwitches(create)
    local c = ns.Char and ns.Char()
    if c and create then c.placeholderSwitches = c.placeholderSwitches or {} end
    return c and c.placeholderSwitches
end
function Placeholders.GearEnabled()
    local s = CharSwitches()
    return not (s and s.offGear)
end
function Placeholders.CustomEnabled()
    local s = CharSwitches()
    return not (s and s.offCustom)
end
function Placeholders.AnyEnabled() return Placeholders.GearEnabled() or Placeholders.CustomEnabled() end
function Placeholders.SetGearEnabled(on)
    CharSwitches(true).offGear = (not on) or nil
    ns.Fire("MODULES_CHANGED")
end
function Placeholders.SetCustomEnabled(on)
    CharSwitches(true).offCustom = (not on) or nil
    ns.Fire("MODULES_CHANGED")
end

-- the weapon that goes into the main hand when nothing needs a dagger there:
-- "W1", "W2" or nil (none ticked: W1). Used by macros that swap weapons.
function Placeholders.PreferredRole()
    local r = Placeholders.CharStore().preferMH
    return (r == "W1" or r == "W2") and r or nil
end
function Placeholders.SetPreferredRole(role)
    Placeholders.CharStore().preferMH = (role == "W1" or role == "W2") and role or nil
end
-- the "Prefer main hand" boxes show only while something uses them (a module
-- registers a check, e.g. its IsActive)
Placeholders.preferUsers = {}
function Placeholders.UsePreferredRole(isActive) table.insert(Placeholders.preferUsers, isActive) end
function Placeholders.PreferredRoleUsed()
    for _, fn in ipairs(Placeholders.preferUsers) do if fn() then return true end end
    return false
end

local function Custom()
    local a = ns.Acct()
    a.placeholders = a.placeholders or {}
    a.placeholders.custom = a.placeholders.custom or {}
    return a.placeholders.custom
end
Placeholders.Custom = Custom

function Placeholders.FindCustom(name)
    for i, c in ipairs(Custom()) do
        if c.name == name then return c, i end
    end
end

-- ---------------------------------------------------------------------------
-- Weapons you own and the roles W1 / W2
-- ---------------------------------------------------------------------------
-- weapon subclasses (Enum.ItemWeaponSubclass); own names first, because the
-- client calls one- and two-handed swords alike ("Schwert")
Placeholders.WEAPON_TYPES = { ANY, 15, 7, 4, 0, 13, 8, 5, 1, 6, 10 }
local TYPE_NAMES = {
    [15] = L["Dagger"], [7] = L["One-handed sword"], [4] = L["One-handed mace"], [0] = L["One-handed axe"],
    [13] = L["Fist weapon"], [8] = L["Two-handed sword"], [5] = L["Two-handed mace"], [1] = L["Two-handed axe"],
    [6] = L["Polearm"], [10] = L["Staff"],
}
function Placeholders.WeaponTypeName(t)
    if t == ANY then return L["Any weapon"] end
    if TYPE_NAMES[t] then return TYPE_NAMES[t] end
    local get = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    local name = get and get(2, t)
    return (type(name) == "string" and name ~= "") and name or tostring(t)
end

local function ItemInfo(id)
    if not (id and C_Item and C_Item.GetItemInfoInstant) then return end
    local _, _, _, equipLoc, _, classID, subID = C_Item.GetItemInfoInstant(id)
    return classID, subID, equipLoc
end

-- the weapon subclass of an item that can sit in a hand slot (nil: not a held weapon)
function Placeholders.HeldWeaponType(id)
    if not id then return end
    local classID, sub, loc = ItemInfo(id)
    if classID == WEAPON_CLASS and not NOT_HELD[loc or ""] then return sub end
end

-- every weapon in the hands and the bags: { id, name, sub, slot (16/17/nil) }
function Placeholders.Weapons()
    local out, seen = {}, {}
    local function add(id, name, slot)
        if not id or seen[id] then return end
        local classID, sub, loc = ItemInfo(id)
        if classID ~= WEAPON_CLASS or NOT_HELD[loc or ""] then return end
        seen[id] = true
        out[#out + 1] = { id = id, name = name or ns.ItemName(id) or ("item:" .. id), sub = sub, slot = slot }
    end
    for _, slot in ipairs({ 16, 17 }) do add(GetInventoryItemID("player", slot), ns.EquippedName(slot), slot) end
    ns.ForEachBagItem(function(id, name) add(id, name) end)
    return out
end

local function Fits(w, roleType) return roleType == ANY or w.sub == roleType end

-- the best guess for a role: equipped before bags; W1 prefers the main hand,
-- W2 takes what W1 left. avoid = the item ID the other role holds
function Placeholders.Suggest(role, roleType, avoid, weapons)
    weapons = weapons or Placeholders.Weapons()
    local order = role == "W1" and { 16, 17, false } or { 17, 16, false }
    for _, want in ipairs(order) do
        for _, w in ipairs(weapons) do
            if w.id ~= avoid and Fits(w, roleType) and ((want and w.slot == want) or (not want and not w.slot)) then
                return w
            end
        end
    end
end

-- suggestions for both roles from what you carry now: { W1 = id, W2 = id }
function Placeholders.SuggestAll(types)
    local weapons = Placeholders.Weapons()
    local roles = Placeholders.Roles()
    local t1 = types and types.W1 or roles.W1.type
    local t2 = types and types.W2 or roles.W2.type
    local w1 = Placeholders.Suggest("W1", t1, nil, weapons)
    local w2 = Placeholders.Suggest("W2", t2, w1 and w1.id, weapons)
    return { W1 = w1 and w1.id, W2 = w2 and w2.id }
end

-- { W1 = { id, name, slot }, W2 = ... }, { W1 = reason, ... }
function Placeholders.ResolveWeapons(roles)
    roles = roles or Placeholders.Roles()
    local weapons = Placeholders.Weapons()
    local byId = {}
    for _, w in ipairs(weapons) do byId[w.id] = w end
    local out, why, taken = {}, {}, nil
    for _, role in ipairs(Placeholders.ROLES) do
        local r = roles[role]
        local pick = r.item and byId[r.item]
        if pick and (pick.id == taken or not Fits(pick, r.type)) then pick = nil end
        pick = pick or Placeholders.Suggest(role, r.type, taken, weapons)
        if pick then
            out[role], taken = pick, pick.id
        else
            why[role] = L["%s: no %s"]:format(role, Placeholders.WeaponTypeName(r.type))
        end
    end
    return out, why
end

-- picks a role's type or weapon; the other role never holds the same weapon
function Placeholders.SetRole(role, field, value, roles)
    roles = roles or Placeholders.Roles()
    local r = roles[role]
    r[field] = value
    if field == "type" then
        -- the best weapon of the new type, rather not the other role's; if it
        -- is the only one, the other role makes room
        local other = roles[role == "W1" and "W2" or "W1"]
        local w = Placeholders.Suggest(role, value, other.item) or Placeholders.Suggest(role, value)
        r.item = w and w.id or nil
    end
    local otherRole = role == "W1" and "W2" or "W1"
    if r.item and roles[otherRole].item == r.item then
        local w = Placeholders.Suggest(otherRole, roles[otherRole].type, r.item)
        roles[otherRole].item = w and w.id or nil
    end
end

-- the weapon list of a role (for the drop-down): { { id, label } }
function Placeholders.WeaponItems(role, roles)
    roles = roles or Placeholders.Roles()
    local r = roles[role]
    local items = {}
    for _, w in ipairs(Placeholders.Weapons()) do
        if Fits(w, r.type) then
            local where = w.slot == 16 and L["main hand"] or w.slot == 17 and L["off hand"] or L["bags"]
            items[#items + 1] = { w.id, w.name .. "  " .. ns.Muted("(" .. where .. ")") }
        end
    end
    if #items == 0 then items[1] = { false, ns.Muted(L["none in the bags or hands"]) } end
    return items
end

-- can this character carry a weapon in the off hand?
function Placeholders.CanDualWield()
    if ns.IsKnown(DUAL_WIELD) then return true end
    local classID, _, loc = ItemInfo(GetInventoryItemID("player", 17))
    return classID == WEAPON_CLASS and not NOT_HELD[loc or ""]
end

-- the trinket in slot 13 (n = 1) or 14 (n = 2)
function Placeholders.Trinket(n)
    local slot = 12 + n
    if not GetInventoryItemID("player", slot) then return nil end
    return ns.EquippedName(slot)
end

-- one row: {w:W1}  [type v]  [weapon v]; source = roles table (the saved
-- one or the dialog's draft), onChange() after a pick
function Placeholders.RoleRow(parent, role, getRoles, onChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(430, 24)
    row.code = ns.Text(row, 13)
    row.code:SetPoint("LEFT", 0, 0)
    row.code:SetText(ns.Code("{w:" .. role .. "}"))
    local types = {}
    for _, t in ipairs(Placeholders.WEAPON_TYPES) do types[#types + 1] = { t, Placeholders.WeaponTypeName(t) } end
    row.type = UI.Dropdown(row, types, function() return getRoles()[role].type end, function(v)
        Placeholders.SetRole(role, "type", v, getRoles())
        onChange()
    end, 140)
    row.type:SetPoint("LEFT", 50, 0)
    row.weapon = UI.Dropdown(row, function() return Placeholders.WeaponItems(role, getRoles()) end,
        function()
            local found = Placeholders.ResolveWeapons(getRoles())
            return found[role] and found[role].id or false
        end, function(v)
            if not v then return end
            Placeholders.SetRole(role, "item", v, getRoles())
            onChange()
        end, 234)
    row.weapon:SetPoint("LEFT", row.type, "RIGHT", 6, 0)
    UI.Tooltip(row.weapon, { L["Weapon"], L["Your weapons of this type, in your hands or bags. W1 and W2 are never the same weapon."] })
    function row:Refresh()
        self.type:Refresh()
        self.weapon:Refresh()
    end
    return row
end

-- the weapons and trinkets worn right now, as one key
function Placeholders.GearKey()
    local ids = {}
    for _, slot in ipairs(Placeholders.GEAR_SLOTS) do ids[#ids + 1] = tostring(GetInventoryItemID("player", slot) or 0) end
    return table.concat(ids, ":")
end

-- ---------------------------------------------------------------------------
-- Filling in
-- ---------------------------------------------------------------------------
function Placeholders.SpellRank(id)
    local get = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
    local ok, rank = pcall(get or function() end, id)
    if ok and type(rank) == "string" and not ns.IsSecret(rank) and rank ~= "" then return rank end
end

local function SpellText(id, withRank)
    id = tonumber(id)
    local name = ns.SpellName(id)
    if not name then return nil end
    local rank = withRank and Placeholders.SpellRank(id)
    return rank and (name .. "(" .. rank .. ")") or name
end

-- macro text with every placeholder filled in that has a value right now;
-- the rest stays as it is (Placeholders.Unfilled lists it)
function Placeholders.Fill(body)
    local text = (body or ""):gsub("{s:(%d+):[rR]}", function(id) return SpellText(id, true) or ("spell " .. id) end)
    text = text:gsub("{s:(%d+)}", function(id) return SpellText(id) or ("spell " .. id) end)
    -- switched off on the Modules page: those placeholders stay as they are
    if Placeholders.GearEnabled() then
        if text:find("{w:", 1, true) then
            local found = Placeholders.ResolveWeapons()
            text = text:gsub("{w:[wW]([12])}", function(n) return found["W" .. n] and found["W" .. n].name or nil end)
        end
        text = text:gsub("{g:[tT]([12])}", function(n) return Placeholders.Trinket(tonumber(n)) end)
    end
    if Placeholders.CustomEnabled() and text:find("{c:", 1, true) then
        text = text:gsub("{c:([^}]+)}", function(name)
            local c = Placeholders.FindCustom(name)
            return c and c.value or nil
        end)
    end
    for _, group in ipairs(Macros.templates) do
        if group.Fill and (not group.IsActive or group.IsActive()) then text = group.Fill(text) end
    end
    return ns.Utf8Sub(text, Macros.BODY_MAX)
end

-- placeholders left in a filled text: { "{w:W1}", ... }
function Placeholders.Unfilled(text)
    local out = {}
    for p in (text or ""):gmatch("{%a:[^}\n]*}") do
        if not ns.IndexOf(out, p) then out[#out + 1] = p end
    end
    return out
end

-- does this template text depend on the gear? (weapons, trinkets)
function Placeholders.UsesGear(body)
    return body and (body:find("{w:", 1, true) or body:find("{g:", 1, true)) and true or false
end

