-- ---------------------------------------------------------------------------
-- Weapon macros. Rogues swap two weapons between the hands: Backstab and
-- Ambush need a dagger in front. The two weapons are the roles W1 and W2 from
-- the placeholders page; the dagger abilities put whichever is a dagger in
-- front (two daggers: the one with "prefer main hand", else W1), everything
-- else the weapon with "prefer main hand" (none ticked: W1).
-- Macros can't hold variables, so the names are written into the macros --
-- this file keeps them up to date.
--   Create missing   makes the macros that don't exist yet, as general or
--                    character macros, in the group "Rogue" of the macro manager
--   Refresh          rewrites every macro of the list by its name
--   Own texts        each macro has a default text in placeholder form; the
--                    player's edit (account-wide, by macro key) replaces it and
--                    is filled in the same way; "Reset macros" drops all edits
-- Without Dual Wield (before level 10) the swap macros only change the main
-- hand. Spell and weapon names come from the client, so the macro names
-- follow the game language. Macro writes are blocked in combat and wait for
-- its end.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local UI, App, Macros, Rogue = ns.UI, ns.App, ns.Macros, ns.Rogue
local Placeholders = ns.Placeholders

local DAGGER = 15   -- Enum.ItemWeaponSubclass.Dagger
local TARGETS = "[@mouseover,harm,nodead][@focus,harm,nodead][] "
local QUESTION = Macros.QUESTION_ICON
local SUFFIX = " EF!"
local SPELLS = { backstab = 53, ambush = 8676, sinister = 1752, kick = 1766, blind = 2094, gouge = 1776, riposte = 14251 }

-- "<spell> EF!" from the client's spell name; too long for a macro name
-- (16 letters): the first words that fit ("Sinister EF!")
local function SpellMacroName(id)
    local s = ns.SpellName(id)
    if type(s) ~= "string" or s == "" or ns.IsSecret(s) then return ("%d"):format(id) .. SUFFIX end
    local room = Macros.NAME_MAX - #SUFFIX
    if ns.Utf8Len(s) <= room then return s .. SUFFIX end
    local out = ""
    for w in s:gmatch("%S+") do
        local try = out == "" and w or (out .. " " .. w)
        if ns.Utf8Len(try) > room then break end
        out = try
    end
    if out == "" then out = ns.Utf8Sub(s, room) end
    return out .. SUFFIX
end

-- macro names: "EF!" at the end, the spells in the game language
local function Names()
    local n = {
        dagger = "W1 MH" .. SUFFIX, weapon = "W2 MH" .. SUFFIX,
        poisonMH = L["Poison MH"] .. SUFFIX, poisonOH = L["Poison OH"] .. SUFFIX,
    }
    for key, id in pairs(SPELLS) do n[key] = SpellMacroName(id) end
    -- Sinister Strike + Riposte: "Fin Riposte EF!" (first letters of the one, the other in full; 16 letters at most)
    local sin, rip = ns.SpellName(SPELLS.sinister), ns.SpellName(SPELLS.riposte)
    if type(sin) == "string" and type(rip) == "string" and not ns.IsSecret(sin) and not ns.IsSecret(rip) then
        n.riposte = ns.Utf8Sub(ns.Utf8Sub(sin, 3) .. " " .. rip, Macros.NAME_MAX - #SUFFIX) .. SUFFIX
    end
    return n
end

-- the weapon that goes into the main hand unless an ability needs a dagger
-- there: "W1", "W2" or nil (none ticked: W1)
-- (kept with W1 / W2 on the placeholders page; the rogue's old setting moves there once)
function Rogue:PreferredRole()
    local s = self:Settings()
    if s.preferMH ~= nil then
        if Placeholders.PreferredRole() == nil then Placeholders.SetPreferredRole(s.preferMH) end
        s.preferMH = nil
    end
    return Placeholders.PreferredRole()
end
function Rogue:SetPreferredRole(role) Placeholders.SetPreferredRole(role) end
-- the "Prefer main hand" boxes on the placeholders page show while this module runs
Placeholders.UsePreferredRole(function()
    if not Rogue:IsActive() then return false end
    Rogue:PreferredRole()   -- takes the old setting along before the page shows it
    return true
end)
local function Other(role) return role == "W1" and "W2" or "W1" end

-- front and back role for an ability: wantDagger = Backstab / Ambush
local function FrontFor(found, wantDagger)
    local lead = Rogue:PreferredRole() or "W1"
    if wantDagger then
        local d1 = found.W1 and found.W1.sub == DAGGER
        local d2 = found.W2 and found.W2.sub == DAGGER
        if not (d1 or d2) then return nil end   -- no dagger at all
        if d1 ~= d2 then lead = d1 and "W1" or "W2" end
    end
    return lead, Other(lead)
end

-- W1 / W2 right now: "W1: name · W2: name"
local function RolesText(sep)
    local found, why = Placeholders.ResolveWeapons()
    local parts = {}
    for _, role in ipairs(Placeholders.ROLES) do
        parts[#parts + 1] = ns.Colorize(HEX.good, role .. ":") .. " "
            .. (found[role] and found[role].name or ns.Colorize(HEX.alert, why[role] or "—"))
    end
    return table.concat(parts, sep or "   ·   ")
end

-- ---------------------------------------------------------------------------
-- The macros: a fixed key each (the stored edits use it, never the name) and
-- a default text in placeholder form, filled in when the macro is written.
-- Besides the placeholders of the templates ({s:ID}, {w:W1}, {c:name}, ...):
--   {r:front}  the weapon this macro puts into the main hand
--   {r:back}   the other one, for the off hand; empty without Dual Wield
--   {p:MH}     the poison picked for that hand (else Instant / Crippling),
--   {p:OH}     as "item:ID"
-- front = the role in front (swap macros); dagger = Backstab / Ambush (the
-- dagger in front); without either the weapon with "prefer main hand".
-- A line whose placeholder is empty ({r:back}) is left out; a placeholder
-- without a value skips the macro with the reason.
-- ---------------------------------------------------------------------------
local SWAP = "#showtooltip {r:front}\n/equipslot 16 {r:front}\n/equipslot 17 {r:back}"
local function Strike(id, pre)
    return "#showtooltip {s:" .. id .. "}\n/equipslot 16 {r:front}\n/equipslot 17 {r:back}"
        .. (pre and ("\n/cast {s:" .. pre .. "}") or "") .. "\n/cast {s:" .. id .. "}"
end
local MACROS = {
    { key = "dagger",   front = "W1", body = SWAP },
    { key = "weapon",   front = "W2", body = SWAP },
    { key = "backstab", dagger = true, body = Strike(SPELLS.backstab) },
    { key = "ambush",   dagger = true, body = Strike(SPELLS.ambush) },
    { key = "sinister", body = Strike(SPELLS.sinister) },
    -- Riposte first: it fires whenever it can, else Sinister Strike
    { key = "riposte",  body = Strike(SPELLS.sinister, SPELLS.riposte) },
    { key = "kick",     body = "#showtooltip\n/cast " .. TARGETS .. "{s:" .. SPELLS.kick .. "}" },
    { key = "blind",    body = "#showtooltip\n/stopattack\n/cast " .. TARGETS .. "{s:" .. SPELLS.blind .. "}" },
    { key = "gouge",    body = "#showtooltip\n/cast {s:" .. SPELLS.gouge .. "}\n/stopattack" },
    -- the item ID keeps it short; the click confirms "replace enchantment?"
    { key = "poisonMH", hand = "MH", body = "/use {p:MH}\n/use 16\n/click StaticPopup1Button1" },
    { key = "poisonOH", hand = "OH", body = "/use {p:OH}\n/use 17\n/click StaticPopup1Button1" },
}
local DEF = {}
Rogue.WEAPON_MACRO_KEYS = {}
for i, d in ipairs(MACROS) do
    DEF[d.key] = d
    Rogue.WEAPON_MACRO_KEYS[i] = d.key
end

-- the player's own texts, account-wide by macro key (placeholder form)
local NONE = {}
local function Bodies(create)
    local a = ns.Acct()
    if create and type(a.rogueMacros) ~= "table" then a.rogueMacros = {} end
    return type(a.rogueMacros) == "table" and a.rogueMacros or NONE
end

-- what the macros fill in from, read once per round
local function Context()
    local found, why = Placeholders.ResolveWeapons()
    return { found = found, why = why, dual = Placeholders.CanDualWield() }
end

-- the weapons in front and behind for a macro: front name (nil + reason when
-- missing), back name ("" without Dual Wield or without a second weapon)
local function Hands(def, ctx)
    local front, back
    if def.front then
        front, back = def.front, Other(def.front)
    else
        front, back = FrontFor(ctx.found, def.dagger)
        if not front then return nil, "", L["no dagger as W1 or W2"] end
    end
    local f, b = ctx.found[front], ctx.found[back]
    if not f then return nil, "", ctx.why[front] end
    return f.name, (ctx.dual and b) and b.name or ""
end

-- text -> filled text, reason (nil = it can be written as it is)
local function FillText(def, text, ctx)
    ctx = ctx or Context()
    local reason, hands
    local lines = {}
    for line in ((text or ""):gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
        local empty = false
        line = line:gsub("{([rRpP]):(%a+)}", function(kind, arg)
            if kind == "r" or kind == "R" then
                hands = hands or { Hands(def, ctx) }
                arg = arg:lower()
                if arg == "front" then
                    if hands[1] then return hands[1] end
                    reason = reason or hands[3]
                elseif arg == "back" then
                    if hands[2] == "" then empty = true end
                    return hands[2]
                end
                return nil
            end
            local hand = arg:upper()
            if not Rogue.HANDS[hand] then return nil end
            local _, id, key = Rogue:MacroPoison(hand)
            if id then return "item:" .. id end
            reason = reason or L["no %s in the bags"]:format(Rogue:PoisonName(key))
            return nil
        end)
        if not empty then lines[#lines + 1] = line end
    end
    local filled = Placeholders.Fill(table.concat(lines, "\n"), true)
    if not reason then
        local left = Placeholders.Unfilled(filled)
        if #left > 0 then reason = L["no value for %s"]:format(table.concat(left, ", ")) end
    end
    if not reason and not filled:find("%S") then reason = L["the text is empty"] end
    if not reason and ns.Utf8Len(filled) > Macros.BODY_MAX then reason = L["longer than 255 letters"] end
    return filled, reason
end

-- does the text follow the gear? (written anew when the weapons change)
local function FollowsGear(text)
    return (text:find("{[rR]:") or Placeholders.UsesGear(text)) and true or nil
end

-- the set: { key, name, icon, body, filled, weapon, note, custom } or { ..., skip = reason }
local function Build()
    local out, NAMES, ctx, own = {}, Names(), Context(), Bodies()
    for _, def in ipairs(MACROS) do
        local text = own[def.key] or def.body
        local filled, reason = FillText(def, text, ctx)
        local note
        if def.hand and not reason and text:find("{[pP]:") then note = (Rogue:MacroPoison(def.hand)) end
        out[#out + 1] = { key = def.key, name = Macros.ShortName(NAMES[def.key]), icon = QUESTION,
            body = (not reason) and filled or nil, skip = reason, filled = filled,
            weapon = FollowsGear(text), note = note, custom = own[def.key] ~= nil }
    end
    return out
end

-- each macro with a state: "change" | "same" | "missing" | "skip"
local function Plan()
    local list = Build()
    for _, m in ipairs(list) do
        -- a general and a character macro may share the name: both follow
        m.indices = Macros.IndicesByName(m.name)
        m.index = m.indices[1]
        m.current = m.index and (select(3, GetMacroInfo(m.index)) or "") or nil
        if not m.index then
            m.state = "missing"
        elseif m.skip then
            m.state = "skip"
        else
            m.state = "same"
            for _, idx in ipairs(m.indices) do
                if not Macros.SameText(select(3, GetMacroInfo(idx)), m.body) then m.state = "change" end
            end
        end
    end
    return list
end
Rogue.WeaponMacroPlan = Plan

local RefreshPage

local function Report(summary, isAlert, lines)
    App.Status(summary, isAlert)
    ns.Print(summary)
    for _, l in ipairs(lines) do print("   " .. l) end
end

local function AfterWrites()
    Macros.Reload()
    if RefreshPage then RefreshPage() end
end

-- in combat the writes wait; several calls meanwhile become one
-- (waitOnly: the names, true = all; waitQuiet: only quiet calls)
local waitOnly, waitQuiet

-- only = { [name] = true } limits the update to those macros; quiet: no
-- report (the gear check prints its own line). Returns the updated names.
local function Update(only, quiet)
    if ns.InCombat() then
        if not only or waitOnly == true then
            waitOnly = true
        else
            waitOnly = waitOnly or {}
            for name in pairs(only) do waitOnly[name] = true end
        end
        waitQuiet = (waitQuiet == nil or waitQuiet) and quiet and true or false
        Placeholders.AfterCombat("rogueMacros", function()
            local o, q = waitOnly, waitQuiet
            waitOnly, waitQuiet = nil, nil
            Update(o ~= true and o or nil, q)
        end)
        if not quiet then Report(L["In combat: the weapon macros update when combat ends."], false, {}) end
        return nil
    end
    local list = Plan()
    local updated, failed, missing, skipped, same = {}, {}, {}, {}, 0
    for _, m in ipairs(list) do
        if m.state == "change" then
            if not only or only[m.name] then
                local ok = true
                for _, idx in ipairs(m.indices) do
                    if not pcall(EditMacro, idx, nil, m.icon, m.body) then ok = false end
                end
                if ok then updated[#updated + 1] = m.name else failed[#failed + 1] = m.name end
            end
        elseif m.state == "same" then
            same = same + 1
        elseif m.state == "missing" then
            missing[#missing + 1] = m.name
        else
            skipped[#skipped + 1] = m.name .. " (" .. m.skip .. ")"
        end
    end
    AfterWrites()
    if quiet then return updated end
    local lines = {}
    lines[#lines + 1] = RolesText("   |   ")
    if #updated > 0 then lines[#lines + 1] = L["updated: %s"]:format(table.concat(updated, ", ")) end
    if #missing > 0 then lines[#lines + 1] = L["missing: %s (Create missing)"]:format(table.concat(missing, ", ")) end
    if #skipped > 0 then lines[#lines + 1] = L["skipped: %s"]:format(table.concat(skipped, ", ")) end
    if #failed > 0 then lines[#lines + 1] = ns.Colorize(HEX.alert, L["failed: %s"]:format(table.concat(failed, ", "))) end
    Report(L["Weapon macros: %d updated, %d up to date, %d missing, %d skipped."]:format(
        #updated, same, #missing, #skipped + #failed), #failed > 0, lines)
    return updated
end
Rogue.UpdateWeaponMacros = function() Update() end

-- ---------------------------------------------------------------------------
-- Own texts (the editor): default and own text, saving, filling in, reset
-- ---------------------------------------------------------------------------
-- default text, own text (nil = none) of a macro key, both in placeholder form
function Rogue:WeaponMacroSource(key)
    local def = DEF[key]
    if not def then return nil end
    return def.body, Bodies()[key]
end

-- the macro name of a key, in the game language
function Rogue:WeaponMacroName(key)
    local n = DEF[key] and Names()[key]
    return n and Macros.ShortName(n)
end

-- the filled text and the reason it can't be written (nil: it can)
function Rogue:FillWeaponMacro(key, text)
    local def = DEF[key]
    if not def then return nil, L["unknown macro"] end
    return FillText(def, text or Bodies()[key] or def.body)
end

-- keeps the own text (nil or the default text: back to the default) and
-- writes the macro right away (in combat when combat ends)
function Rogue:SetWeaponMacroBody(key, text)
    local def = DEF[key]
    if not def then return false end
    if type(text) == "string" then text = text:gsub("\r", "") end
    if text == nil or text == def.body then
        Bodies()[key] = nil
    else
        Bodies(true)[key] = text
    end
    local name = self:WeaponMacroName(key)
    Update(name and { [name] = true } or nil)
    return true
end

-- "Reset macros" (the page and the Reset page): every own text goes, every
-- existing macro of the list gets its default text (none is created or
-- deleted, groups and action buttons stay)
function Rogue:ResetWeaponMacros()
    ns.Acct().rogueMacros = nil
    if self:IsActive() then
        Update()
    elseif RefreshPage then
        RefreshPage()
    end
end

-- only = { [name] = true } limits it to those macros; perChar: character
-- macros instead of general ones
local function CreateMissing(only, perChar)
    if ns.InCombat() then
        Placeholders.AfterCombat("rogueCreate", function() CreateMissing(only, perChar) end)
        Report(L["In combat: the macros are created when combat ends."], false, {})
        return
    end
    local created, empty, failed, existed = {}, {}, {}, 0
    for _, m in ipairs((Plan())) do
        if m.state == "missing" and (not only or only[m.name]) then
            -- without the gear for it yet the macro starts empty; Update fills it later
            if Macros.Create(m.name, m.body or "#showtooltip", perChar) then
                Macros.SetGroup(m.name, perChar, L["Rogue"])
                created[#created + 1] = m.name
                if not m.body then empty[#empty + 1] = m.name .. " (" .. m.skip .. ")" end
            else
                failed[#failed + 1] = m.name
            end
        else
            existed = existed + 1
        end
    end
    AfterWrites()
    local lines = {}
    if #created > 0 then
        lines[#lines + 1] = L["created under %s: %s"]:format(perChar and L["Character"] or L["General"], table.concat(created, ", "))
    end
    if #empty > 0 then lines[#lines + 1] = L["still empty: %s"]:format(table.concat(empty, ", ")) end
    if #failed > 0 then lines[#lines + 1] = ns.Colorize(HEX.alert, L["failed (macro list full?): %s"]:format(table.concat(failed, ", "))) end
    Report(L["Weapon macros: %d created, %d already there."]:format(#created, existed), #failed > 0, lines)
end
Rogue.CreateWeaponMacros = CreateMissing

-- general or character: the choice comes with each creation
local function AskCreate(anchor, only)
    UI.OpenMenu(anchor, {
        { label = L["Create as macro"], isTitle = true },
        { label = L["General"], fn = function() CreateMissing(only, false) end },
        { label = L["Character"], fn = function() CreateMissing(only, true) end },
    }, { width = 180, point = "TOPLEFT", relPoint = "BOTTOMLEFT" })
end

-- macros made before the group existed join it, once per character; the ones
-- the player sorted into a group of their own stay there
local function AdoptExisting()
    local s = Rogue:Settings()
    if s.macroGroupDone or not Rogue:IsActive() then return end
    s.macroGroupDone = true
    for _, m in ipairs((Plan())) do
        for _, idx in ipairs(m.indices) do
            local perChar = idx > Macros.CharBase()
            if not Macros.GroupStore(perChar).of[m.name] then Macros.SetGroup(m.name, perChar, L["Rogue"]) end
        end
    end
end
Macros.OnShow(AdoptExisting)

-- ---------------------------------------------------------------------------
-- Page: Macros › Rogue
-- ---------------------------------------------------------------------------
local STATE = {
    change = { L["UPDATE"], "accent" }, same = { L["UP TO DATE"], "muted" },
    missing = { L["MISSING"], "alert" }, skip = { L["SKIPPED"], "alert" },
}

local function BuildPage(p)
    local W = App.CONTENT_W
    local LIST_W, ROWS, ROW = 250, 8, 28
    local TOP = -34   -- below the weapon line
    local plan, sel, scroll = {}, nil, 0
    local rows = {}

    -- W1 / W2 and "prefer main hand" are set on the placeholders page; here
    -- only what they are right now, with a way there
    local weapons = ns.Text(p, 12)
    weapons:SetPoint("TOPLEFT", 0, -4)
    weapons:SetWidth(W - 150)
    weapons:SetJustifyH("LEFT")
    weapons:SetWordWrap(false)
    local toRoles = UI.Button(p, 140, L["Placeholders"] .. "  ›", function() App:Select("placeholders") end, 22)
    toRoles:SetPoint("TOPRIGHT", 0, 0)
    UI.Tooltip(toRoles, { L["Placeholders"], L["Pick W1, W2 and \"Prefer main hand\" there."] })
    local dualHint = UI.Hint(p, "", W)

    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", 0, TOP)
    list:SetSize(LIST_W, ROWS * ROW)
    ns.Skin(list, T.panel)
    list:EnableMouseWheel(true)

    local X = LIST_W + 16
    local BOX_W = W - X
    local function Box(label, y, h)
        UI.Label(p, label, X, y)
        local f = CreateFrame("Frame", nil, p)
        f:SetPoint("TOPLEFT", X, y - 16)
        f:SetSize(BOX_W, h)
        ns.Skin(f, T.control, T.input)
        f.text = ns.Text(f, 12)
        f.text:SetPoint("TOPLEFT", 8, -6)
        f.text:SetPoint("BOTTOMRIGHT", -8, 6)
        f.text:SetJustifyH("LEFT")
        f.text:SetJustifyV("TOP")
        return f
    end
    local curBox = Box(L["CURRENT"], TOP, 92)
    local newBox = Box(L["NEW"], TOP - 116, 92)

    local applyBtn, createBtn, selBtn, editBtn, resetOneBtn, resetAllBtn
    local function Render()
        local changes, missing = 0, 0
        for _, m in ipairs(plan) do
            if m.state == "change" then changes = changes + 1 end
            if m.state == "missing" then missing = missing + 1 end
        end
        scroll = math.max(0, math.min(scroll, #plan - ROWS))
        for i = 1, ROWS do
            local r, m = rows[i], plan[scroll + i]
            r.entry = m
            if m then
                r.name:SetText(m.name)
                local st = STATE[m.state]
                r.badge:SetText(ns.Colorize(HEX[st[2]], st[1]))
                r.custom:SetText(m.custom and ns.Colorize(HEX.accent, L["EDITED"]) or "")
                r.badge:SetPoint("RIGHT", -8, m.custom and 6 or 0)
                r.sel:SetShown(m == sel)
                r.mark:SetShown(m == sel)
                r:Show()
            else
                r:Hide()
            end
        end
        if sel then
            curBox.text:SetText(sel.current and (sel.current ~= "" and sel.current or ns.Muted(L["(empty)"]))
                or ns.Colorize(HEX.alert, L["This macro doesn't exist yet."]))
            if sel.body then
                newBox.text:SetText(sel.body .. (sel.note and ("\n\n" .. ns.Muted(L["item: %s"]:format(sel.note))) or ""))
            else
                newBox.text:SetText(ns.Colorize(HEX.alert, L["Can't be built right now: %s."]:format(sel.skip)))
            end
        else
            curBox.text:SetText("")
            newBox.text:SetText("")
        end
        applyBtn.text:SetText(changes > 0 and L["Refresh all (%d)"]:format(changes) or L["Refresh all"])
        -- the selected macro: create or refresh just this one
        local st = sel and sel.state
        selBtn.text:SetText(st == "missing" and (L["Create"] .. "  ›") or L["Refresh"])
        selBtn:SetAlpha((st == "missing" or st == "change") and 1 or 0.4)
        createBtn.text:SetText(L["Create %d missing"]:format(missing) .. "  ›")
        createBtn:SetAlpha(missing > 0 and 1 or 0.4)
        editBtn.text:SetText(L["Edit \"%s\" ..."]:format(sel and sel.name or "—"))
        editBtn:SetAlpha(sel and 1 or 0.4)
        resetOneBtn:SetAlpha((sel and sel.custom) and 1 or 0.4)
        local edited = 0
        for _, m in ipairs(plan) do if m.custom then edited = edited + 1 end end
        resetAllBtn.text:SetText(edited > 0 and L["Reset all macros (%d edited)"]:format(edited) or L["Reset all macros"])
    end

    RefreshPage = function()
        if not p:IsVisible() then return end
        AdoptExisting()
        local selName = sel and sel.name
        plan = Plan()
        sel = nil
        for _, m in ipairs(plan) do if m.name == selName then sel = m end end
        if not sel then
            for _, m in ipairs(plan) do if m.state == "change" then sel = m break end end
            sel = sel or plan[1]
        end
        local lead = Rogue:PreferredRole()
        weapons:SetText(RolesText() .. (lead and ("   ·   " .. ns.Muted(L["main hand: %s"]:format(lead))) or "")
            .. (Placeholders.GearEnabled() and "" or ("   ·   " .. ns.Muted(L["gear placeholders off"]))))
        toRoles:SetShown(Placeholders.GearEnabled())
        dualHint:SetText(Placeholders.CanDualWield() and L["Backstab and Ambush put the dagger in front, everything else the weapon with \"Prefer main hand\" (none ticked: W1). The swap macros put one in each hand."]
            or L["Without Dual Wield (level 10) the swap macros change the main hand only."])
        Render()
    end

    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        r:SetSize(LIST_W, ROW)
        r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.sel:SetAllPoints()
        ns.Color(r.sel, T.accentSoft)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetPoint("TOPLEFT")
        r.mark:SetPoint("BOTTOMLEFT")
        r.mark:SetWidth(2)
        ns.Color(r.mark, T.accent)
        r.name = ns.Text(r, 12)
        r.name:SetPoint("LEFT", 12, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetPoint("RIGHT", -96, 0)
        r.name:SetWordWrap(false)
        r.badge = ns.Text(r, 10)
        r.badge:SetPoint("RIGHT", -8, 0)
        -- the player's own text is used for this macro: under the state
        r.custom = ns.Text(r, 10)
        r.custom:SetPoint("RIGHT", -8, -6)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        ns.Color(r.hl, T.hover)
        r:SetScript("OnClick", function(self) sel = self.entry Render() end)
        r:SetScript("OnDoubleClick", function(self)
            sel = self.entry
            Render()
            if sel then Rogue:EditWeaponMacro(sel.key) end
        end)
        UI.Tooltip(r, function(self)
            local m = self.entry
            if not m then return end
            local st = STATE[m.state]
            local lines = { m.name, ns.Colorize(HEX[st[2]], st[1]) .. (m.skip and ("  ·  " .. m.skip) or "") }
            if m.custom then
                lines[#lines + 1] = ns.Colorize(HEX.accent, L["EDITED"]) .. "  ·  " .. L["Your own text is used instead of the default one."]
            end
            return lines
        end)
        rows[i] = r
    end

    list:SetScript("OnMouseWheel", function(_, delta)
        scroll = scroll - delta
        Render()
    end)

    -- two groups under the list and the boxes, side by side: the selected
    -- macro on the left, every macro of the list on the right
    local HALF = (LIST_W - 6) / 2
    local ALL_W = (BOX_W - 6) / 2
    local GROUP_Y = TOP - ROWS * ROW - 10
    UI.Label(p, L["SELECTED MACRO"], 0, GROUP_Y)
    UI.Label(p, L["ALL MACROS"], X, GROUP_Y)

    editBtn = UI.Button(p, LIST_W, "", function() if sel then Rogue:EditWeaponMacro(sel.key) end end, 22)
    editBtn:SetPoint("TOPLEFT", 0, GROUP_Y - 16)
    UI.Tooltip(editBtn, { L["Edit macro"], L["Opens the text of the selected macro with its placeholders (also: double-click the row). Your version is kept for all characters and follows your weapons and poisons."] })
    selBtn = UI.Button(p, HALF, "", function(self)
        if not sel then return end
        if sel.state == "missing" then AskCreate(self, { [sel.name] = true })
        elseif sel.state == "change" then Update({ [sel.name] = true }) end
    end, 22)
    selBtn:SetPoint("TOPLEFT", editBtn, "BOTTOMLEFT", 0, -6)
    UI.Tooltip(selBtn, { L["Selected macro"], L["Creates the selected macro, or writes it anew when it is out of date."] })
    resetOneBtn = UI.Button(p, HALF, L["Reset"], function()
        if not (sel and sel.custom) then
            App.Status(L["\"%s\" already has its default text."]:format(sel and sel.name or "—"))
            return
        end
        local key, name = sel.key, sel.name
        UI.MessageBox(L["Reset macro"], L["Your own text of \"%s\" is deleted and the macro gets its default text again."]:format(name),
            { { L["Cancel"] }, { L["Reset"], function() Rogue:SetWeaponMacroBody(key, nil) end, true } })
    end, 22)
    resetOneBtn:SetPoint("LEFT", selBtn, "RIGHT", 6, 0)
    UI.Tooltip(resetOneBtn, { L["Reset macro"], L["Deletes your own text of the selected macro; it gets its default text again. Asks first."] })

    applyBtn = UI.Button(p, ALL_W, "", function() Update() end, 22)
    applyBtn:SetPoint("TOPLEFT", X, GROUP_Y - 16)
    applyBtn:SetAccent(true)
    UI.Tooltip(applyBtn, { L["Refresh all"], L["Rewrites every macro of this list (general or character) with your current weapons, spells and poisons."] })
    createBtn = UI.Button(p, ALL_W, "", function(self)
        for _, m in ipairs(plan) do
            if m.state == "missing" then AskCreate(self) return end
        end
    end, 22)
    createBtn:SetPoint("LEFT", applyBtn, "RIGHT", 6, 0)
    UI.Tooltip(createBtn, { L["Create as macro"], L["Asks whether they become general or character macros. They go into the group \"%s\" of the macro manager, which is created if needed."]:format(L["Rogue"]) })
    -- the same as "Rogue macros" on the Reset page
    resetAllBtn = UI.Button(p, BOX_W, L["Reset all macros"], function()
        local n = 0
        for _, m in ipairs(plan) do if m.custom then n = n + 1 end end
        UI.MessageBox(L["Reset all macros"], L["Your own texts (%d) are deleted and every existing rogue macro gets its default text again. No macro is created or deleted; groups and action buttons stay."]:format(n),
            { { L["Cancel"] }, { L["Reset"], function() Rogue:ResetWeaponMacros() end, true } })
    end, 22)
    resetAllBtn:SetPoint("TOPLEFT", applyBtn, "BOTTOMLEFT", 0, -6)
    UI.Tooltip(resetAllBtn, { L["Reset all macros"], L["Deletes your own texts and writes every existing macro of this list with its default text. Asks first."] })

    dualHint:SetPoint("TOPLEFT", selBtn, "BOTTOMLEFT", 0, -14)
    local note = UI.Hint(p, L["\"Refresh all\" writes every macro of this list anew that exists under its name (general or character); macros with other names are never changed. Drag new ones from the macro list onto your action bars."], W)
    note:SetPoint("BOTTOMLEFT", 0, 0)
    note:SetSpacing(2)
end

Rogue:Page({
    key = "weaponMacros", section = "macros", label = L["Rogue macros"], order = 140,
    Build = function(_, frame) BuildPage(frame) end,
    Refresh = function() if RefreshPage then RefreshPage() end end,
})

-- the same function as the button on the page
Rogue:Reset({ key = "weaponMacros", group = "macros", order = 77, label = L["Rogue macros"], accountWide = true,
    desc = L["Deletes your own texts of the rogue macros; every existing one gets its default text again."],
    reset = function() Rogue:ResetWeaponMacros() end })

local function ShowPlan() App:Open("weaponMacros") end
Rogue.ShowWeaponMacros = ShowPlan

-- buttons in the macro manager header
Rogue:MacroAction({
    label = L["Rogue macros"], width = 130, accent = true,
    OnClick = function(_, button)
        if button == "RightButton" then Update() else ShowPlan() end
    end,
    Tooltip = function()
        local list = Plan()
        local lines = { L["Weapon macros"] }
        lines[#lines + 1] = RolesText("\n")
        local changes = {}
        for _, m in ipairs(list) do if m.state == "change" then changes[#changes + 1] = m.name end end
        lines[#lines + 1] = #changes > 0 and L["Would update: %s"]:format(table.concat(changes, ", ")) or L["Everything is up to date."]
        lines[#lines + 1] = L["Left-click: show the changes  ·  Right-click: update all now"]
        return lines
    end,
})

-- ---------------------------------------------------------------------------
-- Changed weapons: the swap macros follow (Placeholders asks first for new ones)
-- ---------------------------------------------------------------------------
local function WeaponOutdated()
    local only, names = {}, {}
    for _, m in ipairs((Plan())) do
        if m.weapon and m.state == "change" then
            only[m.name] = true
            names[#names + 1] = m.name
        end
    end
    return names, only
end
Rogue:GearMacros({
    Outdated = function() return (WeaponOutdated()) end,
    Update = function()
        local _, only = WeaponOutdated()
        if not next(only) then return {} end
        return Update(only, true)
    end,
})
Rogue:Updater(function() Update() end)

ns.RegisterEvent("UPDATE_MACROS", function() if App:IsOpen("weaponMacros") and RefreshPage then RefreshPage() end end)
ns.RegisterEvent("BAG_UPDATE", function() if App:IsOpen("weaponMacros") and RefreshPage then RefreshPage() end end)
ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() if App:IsOpen("weaponMacros") and RefreshPage then RefreshPage() end end)

Rogue:Command({ "defaults" }, function(arg) CreateMissing(nil, arg == "char") end,
    L["rogue: create the missing weapon macros (\"char\": as character macros)"])
