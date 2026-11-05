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
        local roles = Placeholders.Roles()
        for _, role in ipairs(Placeholders.ROLES) do
            roles[role].type, roles[role].item = draft[role].type, draft[role].item
        end
        Placeholders.CharStore().seen = Placeholders.GearKey()
        dlg:Hide()
        Placeholders.UpdateGearMacros()
    end, 24)
    ok:SetPoint("BOTTOMRIGHT", -14, 14)
    ok:SetAccent(true)
    local later = UI.Button(dlg, 100, L["Later"], function()
        Placeholders.CharStore().seen = Placeholders.GearKey()   -- not again for this gear
        dlg:Hide()
    end, 24)
    later:SetPoint("RIGHT", ok, "LEFT", -6, 0)
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
    UI.PlaceDialog(dlg)
    dlg:Show()
    dlg:Raise()
end

local checkAfterCombat = false
local function CheckGear()
    if not ns.ready then return end
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
    if #new == 0 and #outdated == 0 then return end
    if s.seen == Placeholders.GearKey() then return end   -- asked for this gear already
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
