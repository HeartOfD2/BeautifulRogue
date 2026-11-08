-- ---------------------------------------------------------------------------
-- Placeholders: macros that follow your gear. Writing after combat, the list of
-- macros to update, and the dialog for new weapons or trinkets.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX, UI, Macros = ns.L, ns.T, ns.HEX, ns.UI, ns.Macros
local Placeholders = ns.Placeholders

-- ---------------------------------------------------------------------------
-- Writing after combat (macro writes are blocked in combat), one job per key
-- ---------------------------------------------------------------------------
local afterCombat, afterOrder = {}, {}
function Placeholders.AfterCombat(key, fn)
    if not afterCombat[key] then afterOrder[#afterOrder + 1] = key end
    afterCombat[key] = fn
end
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    C_Timer.After(0.1, function()
        local order = afterOrder
        afterOrder = {}
        for _, key in ipairs(order) do
            local fn = afterCombat[key]
            afterCombat[key] = nil
            if fn then fn() end
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- Changed gear: { Outdated() -> { names }, Update() -> { updated names } }
-- ---------------------------------------------------------------------------
function Placeholders.RegisterGearMacros(src) table.insert(Placeholders.gearSources, src) end
-- extra jobs for /ef update (the rogue's built-in macros)
function Placeholders.RegisterUpdater(fn) table.insert(Placeholders.updaters, fn) end

local function GearOutdated()
    local out = {}
    for _, src in ipairs(Placeholders.gearSources) do
        if not src.IsActive or src.IsActive() then
            for _, n in ipairs(src.Outdated()) do out[#out + 1] = n end
        end
    end
    return out
end

-- rewrites every macro that uses the gear; one line in the chat
function Placeholders.UpdateGearMacros()
    if ns.InCombat() then
        Placeholders.AfterCombat("gear", Placeholders.UpdateGearMacros)
        return
    end
    local updated = {}
    for _, src in ipairs(Placeholders.gearSources) do
        if not src.IsActive or src.IsActive() then
            for _, n in ipairs(src.Update() or {}) do updated[#updated + 1] = n end
        end
    end
    if #updated > 0 then ns.Print(L["Gear changed, macros updated: %s"]:format(table.concat(updated, ", "))) end
    Macros.Reload()
    if Placeholders.RefreshPage then Placeholders.RefreshPage() end
end

-- everything: templates, the modules' own macros (Placeholders page, /ef update)
function Placeholders.UpdateAll()
    if ns.Templates then ns.Templates.UpdateMacros() end
    for _, fn in ipairs(Placeholders.updaters) do fn() end
end

-- ---------------------------------------------------------------------------
-- What happens when the gear changes (account-wide). Turning the gear check
-- off entirely is the gear placeholders switch on the Modules page.
--   ask    the "New gear" dialog asks for W1 / W2 (default)
--   auto   the suggestion is taken without a question, the macros follow
--   manual nothing happens; the player sets W1 / W2 and presses Refresh
-- ---------------------------------------------------------------------------
local MODES = { auto = true, manual = true }
function Placeholders.GearMode()
    local a = ns.Acct().placeholders
    local m = a and a.gearMode
    return MODES[m or ""] and m or "ask"
end
function Placeholders.SetGearMode(mode)
    local a = ns.Acct()
    a.placeholders = a.placeholders or {}
    a.placeholders.gearMode = MODES[mode or ""] and mode or nil
end

-- label and dropdown in one row, the dropdown right after the label
function Placeholders.GearModeRow(parent, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width or 300, 22)
    row.label = ns.Text(row, 12)
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetText(L["On new gear"])
    local items = { { "ask", L["Ask"] }, { "auto", L["Automatically"] }, { "manual", L["Manually"] } }
    -- "Manually" leaves macros behind on new gear: only after a warning
    local function Set(v)
        if v ~= "manual" or Placeholders.GearMode() == "manual" then
            Placeholders.SetGearMode(v)
            return
        end
        UI.MessageBox(L["Manually"], L["On new gear nothing happens then. Macros with {w:...} or {g:...} and the rogue macros keep the old names and may stop working until you press Refresh. The chat names them when your gear changes."],
            { { L["Cancel"] }, { L["Use manually"], function()
                Placeholders.SetGearMode("manual")
                row:Refresh()
            end, true } })
    end
    row.dd = UI.Dropdown(row, items, Placeholders.GearMode, Set, 140)
    row.dd:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
    UI.Tooltip(row.dd, { L["On new gear"],
        L["Ask: the \"New gear\" window asks which weapon is W1 and which is W2."],
        L["Automatically: W1 and W2 are picked for you, macros with gear placeholders follow."],
        L["Manually: nothing happens on new gear; pick W1 and W2 here and press Refresh."],
        L["For all characters. Macros without placeholders are never changed."] })
    function row:Refresh() self.dd:Refresh() end
    return row
end

-- takes a W1 / W2 choice, marks this gear as handled, rewrites the macros
local function ApplyRoles(choice)
    local roles = Placeholders.Roles()
    for _, role in ipairs(Placeholders.ROLES) do
        roles[role].type, roles[role].item = choice[role].type, choice[role].item
    end
    Placeholders.CharStore().seen = Placeholders.GearKey()
    Placeholders.UpdateGearMacros()
end

-- ---------------------------------------------------------------------------
-- Dialog: new weapons or trinkets. Shows W1 / W2 with the suggestion; the
-- player confirms or changes it, then the macros follow.
-- ---------------------------------------------------------------------------
local dlg, draft
local function BuildDialog()
    dlg = UI.Window("BeautifulRogueGearDialog", 470, 236, L["New gear"], { strata = "FULLSCREEN_DIALOG" })
    dlg.text = UI.Hint(dlg, "", 442)
    dlg.text:SetPoint("TOPLEFT", 14, -36)
    ns.Color(dlg.text, T.text)
    dlg.rows = {}
    for i, role in ipairs(Placeholders.ROLES) do
        local r = Placeholders.RoleRow(dlg, role, function() return draft end, function()
            for _, x in ipairs(dlg.rows) do x:Refresh() end
        end)
        r:SetPoint("TOPLEFT", 14, -96 - (i - 1) * 30)
        dlg.rows[i] = r
    end
    dlg.note = UI.Hint(dlg, L["Macros with weapons or trinkets are written anew with this choice."], 442)
    dlg.note:SetPoint("TOPLEFT", 14, -160)
    local ok = UI.Button(dlg, 120, L["Apply"], function()
        dlg:Hide()
        ApplyRoles(draft)
    end, 24)
    ok:SetPoint("BOTTOMRIGHT", -14, 14)
    ok:SetAccent(true)
    local later = UI.Button(dlg, 100, L["Later"], function()
        Placeholders.CharStore().seen = Placeholders.GearKey()   -- not again for this gear
        dlg:Hide()
    end, 24)
    later:SetPoint("RIGHT", ok, "LEFT", -6, 0)
    -- no more questions: from now on the suggestion is taken
    dlg.quiet = UI.CheckRow(dlg, L["Don't ask again"], function() return Placeholders.GearMode() == "auto" end,
        function(v) Placeholders.SetGearMode(v and "auto" or "ask") end, 200)
    dlg.quiet:SetPoint("BOTTOMLEFT", 14, 16)
    UI.Tooltip(dlg.quiet, { L["Don't ask again"], L["From now on W1 and W2 are picked for you when your gear changes, and your macros follow. Change it under Macros › Placeholders; switch gear placeholders off entirely under Addon › Modules."] })
end

-- the suggestion after a weapon change: a role whose weapon is still in a
-- hand keeps it; a new weapon takes the place of a role whose weapon left
-- the hands (one of its own type first) and brings its type along
function Placeholders.DraftForNewGear()
    local roles = Placeholders.Roles()
    local d = {}
    for _, role in ipairs(Placeholders.ROLES) do d[role] = { type = roles[role].type, item = roles[role].item } end
    local equipped, new = {}, {}
    for _, slot in ipairs({ 16, 17 }) do
        local id = GetInventoryItemID("player", slot)
        local sub = Placeholders.HeldWeaponType(id)
        if sub then
            equipped[id] = true
            if id ~= roles.W1.item and id ~= roles.W2.item then new[#new + 1] = { id = id, sub = sub } end
        end
    end
    local free = {}
    for _, role in ipairs(Placeholders.ROLES) do
        if not (d[role].item and equipped[d[role].item]) then free[#free + 1] = role end
    end
    for _, w in ipairs(new) do
        local pick
        for i, role in ipairs(free) do
            if d[role].type == w.sub then pick = i break end
        end
        pick = pick or (#free > 0 and 1)
        local role = pick and table.remove(free, pick) or "W2"
        d[role].item, d[role].type = w.id, w.sub
    end
    return d
end

function Placeholders.ShowGearDialog(newNames)
    draft = Placeholders.DraftForNewGear()
    if not dlg then BuildDialog() end
    dlg.text:SetText(L["New gear: %s.\nPlease check which weapon is W1 and which is W2:"]:format(
        ns.Colorize(HEX.good, table.concat(newNames, ", "))))
    for _, r in ipairs(dlg.rows) do r:Refresh() end
    dlg.quiet:Refresh()
    UI.PlaceDialog(dlg)
    dlg:Show()
    dlg:Raise()
end

local checkAfterCombat = false
local warnedKey   -- "Manually": the gear the chat line was printed for
local function CheckGear()
    if not ns.ready then return end
    if not Placeholders.GearEnabled() then return end   -- gear placeholders off (Modules page)
    local mode = Placeholders.GearMode()
    if ns.InCombat() then checkAfterCombat = true return end
    if not GetInventoryItemID("player", 16) then return end   -- mid-swap: wait for the weapon
    local s = Placeholders.CharStore()
    local roles = s.roles
    -- first time: take the suggestion without asking
    if not (roles.W1.item or roles.W2.item) then
        local sug = Placeholders.SuggestAll()
        roles.W1.item, roles.W2.item = sug.W1, sug.W2
        s.seen = Placeholders.GearKey()
    end
    -- weapons in the hands that are neither W1 nor W2 (swapping the two is fine)
    local new = {}
    for _, slot in ipairs({ 16, 17 }) do
        local id = GetInventoryItemID("player", slot)
        if Placeholders.HeldWeaponType(id) and id ~= roles.W1.item and id ~= roles.W2.item then
            new[#new + 1] = ns.EquippedName(slot) or ("item:" .. id)
        end
    end
    local outdated = GearOutdated()
    if mode == "manual" then
        -- nothing is written; one chat line per gear names the macros that no
        -- longer match it (they would equip or use what you no longer carry)
        local key = Placeholders.GearKey()
        if #outdated > 0 and warnedKey ~= key then
            warnedKey = key
            ns.Print(L["Gear changed: %s no longer match it. Macros › Placeholders, then Refresh, writes them anew."]:format(
                ns.Colorize(HEX.alert, table.concat(outdated, ", "))))
        end
        return
    end
    if #new == 0 and #outdated == 0 then return end
    if s.seen == Placeholders.GearKey() then return end   -- asked for this gear already
    if mode == "auto" then
        -- no question: take the suggestion, the macros follow
        ApplyRoles(Placeholders.DraftForNewGear())
        return
    end
    if #new == 0 then
        -- trinkets (or a weapon back in its role): name what changed
        for _, slot in ipairs({ 13, 14 }) do
            local n = ns.EquippedName(slot)
            if n then new[#new + 1] = n end
        end
    end
    Placeholders.ShowGearDialog(new)
end
Placeholders.CheckGear = CheckGear

local token = 0
ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function(_, slot)
    if not ns.IndexOf(Placeholders.GEAR_SLOTS, slot) then return end
    if Placeholders.RefreshPage then Placeholders.RefreshPage() end
    -- a swap fires several events: judge the gear once it has settled
    token = token + 1
    local mine = token
    C_Timer.After(1.5, function() if mine == token then CheckGear() end end)
end)
ns.On("LOGIN", function() C_Timer.After(3, CheckGear) end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if checkAfterCombat then
        checkAfterCombat = false
        C_Timer.After(0.2, CheckGear)
    end
end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    -- the dialog waits for the end of combat
    if dlg and dlg:IsShown() then dlg:Hide() checkAfterCombat = true end
end)
