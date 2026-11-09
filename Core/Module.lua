-- ---------------------------------------------------------------------------
-- Modules: optional feature packs, most of them for one class (see
-- Modules/<Name>/ and docs/MODULE-BAUEN.md). A module is active when its class
-- fits and the player has not switched it off (Modules page).
--
--   local M = ns.NewModule("mage", { title, desc, classes = { MAGE = true },
--                                    classHint, defaultEnabled, OnEnable,
--                                    OnActiveChanged, BuildOptions, accountWide })
-- accountWide = true: the on/off switch holds for every character of the account.
--
-- A module hooks into the other parts of the addon through the methods below.
-- Each one ties what it registers to the module: while the module is off (or
-- the class does not fit), its events stay quiet, its buttons, pages, templates
-- and cooldown entries are hidden. The module code needs no IsActive checks.
--
--   M:Event / M:UnitEvent / M:On      game events and internal messages
--   M:Command / M:Status              /ef commands and /ef status lines
--   M:Reset                           a category on the Reset page
--   M:Templates                       default macro templates
--   M:MacroAction                     a button in the macro manager header
--   M:GearMacros / M:Updater          macros that follow the gear, /ef update
--   M:Special                         a cooldown bar entry
--   M:Element                         a HUD part
--   M:Page                            a page in the app window
--   M:Block                           a block on a page of the core (General ...)
--   M:MinimapClick                    Shift- / middle-click of the minimap button
--   M:Featured                        spells and items the icon picker lists first
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

ns.modules, ns.moduleOrder = {}, {}

local Module = {}
Module.__index = Module

function Module:IsClassAllowed()
    if not self.classes then return true end
    return self.classes[ns.playerClass or ""] and true or false
end

-- per-character module settings live in the character DB
function Module:Settings()
    local all = ns.Char().modules
    all[self.key] = all[self.key] or {}
    return all[self.key]
end

-- switches of modules with accountWide = true (their settings are account-wide
-- as well, so a switch per character would leave other characters changing them)
local function AccountSwitches()
    local a = ns.Acct()
    if type(a.moduleSwitches) ~= "table" then a.moduleSwitches = {} end
    return a.moduleSwitches
end

function Module:IsEnabledSetting()
    if not ns.Char then return self.defaultEnabled ~= false end
    local s = ns.Char().modules[self.key]
    if self.accountWide then
        local sw = AccountSwitches()
        -- a switch saved on this character before moves to the account once;
        -- with one there already it is dropped, so a reset can't bring it back
        if s and s.enabled ~= nil and ns.dbReady then
            if sw[self.key] == nil then sw[self.key] = s.enabled end
            s.enabled = nil
        end
        if sw[self.key] ~= nil then return sw[self.key] end
        return self.defaultEnabled ~= false
    end
    if s and s.enabled ~= nil then return s.enabled end
    return self.defaultEnabled ~= false
end

function Module:IsActive()
    return ns.ready and self:IsClassAllowed() and self:IsEnabledSetting() or false
end

function Module:SetEnabled(on)
    if self.accountWide then
        AccountSwitches()[self.key] = on and true or false
    else
        self:Settings().enabled = on and true or false
    end
    ns.RefreshModules()
end

-- why the module is not running (shown where its parts would be)
function Module:OffReason()
    if not self:IsClassAllowed() then return self.classHint or L["not for your class"] end
    return L["%s module is off"]:format(self.title or self.key)
end

function ns.NewModule(key, def)
    local m = setmetatable(def or {}, Module)
    m.key = key
    ns.modules[key] = m
    ns.moduleOrder[#ns.moduleOrder + 1] = key
    return m
end

-- (re)evaluate which modules run; called at login and after toggles/resets
function ns.RefreshModules()
    for _, key in ipairs(ns.moduleOrder) do
        local m = ns.modules[key]
        local active = m:IsActive()
        if active and not m.started then
            m.started = true
            if m.OnEnable then ns.SafeCall(m.OnEnable, m) end
        end
        if active ~= m.wasActive then
            m.wasActive = active
            if m.OnActiveChanged then ns.SafeCall(m.OnActiveChanged, m, active) end
        end
    end
    ns.Fire("MODULES_CHANGED")
end
-- "Modules" on the Reset page puts every switch back to its default
ns.On("SETTINGS_RESET", function(keys) if keys.modules and ns.ready then ns.RefreshModules() end end)

-- ---------------------------------------------------------------------------
-- Hooks into the rest of the addon, tied to the module
-- ---------------------------------------------------------------------------
function Module:Event(event, fn)
    return ns.RegisterEvent(event, function(...) if self:IsActive() then fn(...) end end)
end

function Module:UnitEvent(event, unit, fn)
    return ns.RegisterUnitEvent(event, unit, function(...) if self:IsActive() then fn(...) end end)
end

function Module:On(message, fn)
    ns.On(message, function(...) if self:IsActive() then fn(...) end end)
end

function Module:Command(names, fn, help)
    ns.AddCommand(names, function(...)
        if self:IsActive() then return fn(...) end
        ns.Print(self:OffReason())
    end, help)
end

function Module:Status(fn)
    ns.AddStatus(function() if self:IsActive() then return fn() end end)
end

-- def: { key, label, desc, order, accountWide, danger, reset }
function Module:Reset(def)
    local visible = def.IsVisible
    def.IsVisible = function() return self:IsClassAllowed() and (not visible or visible()) end
    ns.RegisterReset(def)
end

-- def: { key, title, groupName, Fill(body), list = { { name, desc, body } } }
function Module:Templates(def)
    local active = def.IsActive
    def.IsActive = function() return self:IsActive() and (not active or active()) end
    ns.Macros.RegisterTemplates(def)
end

-- def: { label, width, accent, IsActive(), OnClick(button, mouseButton), Tooltip(button) }
function Module:MacroAction(def)
    local active = def.IsActive
    def.IsActive = function() return self:IsActive() and (not active or active()) end
    ns.Macros.RegisterAction(def)
end

-- src: { Outdated() -> names, Update() -> updated names }
function Module:GearMacros(src)
    local active = src.IsActive
    src.IsActive = function() return self:IsActive() and (not active or active()) end
    ns.Placeholders.RegisterGearMacros(src)
end

function Module:Updater(fn)
    ns.Placeholders.RegisterUpdater(function() if self:IsActive() then fn() end end)
end

-- def: { key, ids, noCasts, IsAvailable() }; returns the entry
function Module:Special(def)
    local available = def.IsAvailable
    def.IsAvailable = function(...) return self:IsActive() and (not available or available(...)) end
    def.IsRelevant = def.IsRelevant or function() return self:IsClassAllowed() end
    return ns.Cooldowns:RegisterSpecial(def)
end

-- def: the HUD:Register definition; returns the element
function Module:Element(def)
    local relevant, available = def.IsRelevant, def.IsAvailable
    def.IsRelevant = relevant or function() return self:IsClassAllowed() end
    def.IsAvailable = function(el, ...)
        if not self:IsActive() then return false, self:OffReason() end
        if available then return available(el, ...) end
        return true
    end
    return ns.HUD:Register(def)
end

-- def: the App:AddPage definition; the page shows while the module runs
function Module:Page(def)
    local visible = def.IsVisible
    def.IsVisible = function() return self:IsActive() and (not visible or visible()) end
    return ns.App:AddPage(def)
end

-- def: the App:AddBlock definition; the block shows while the module runs
function Module:Block(pageKey, def)
    local visible = def.IsVisible
    def.IsVisible = function() return self:IsActive() and (not visible or visible()) end
    return ns.App:AddBlock(pageKey, def)
end

-- def: { OnClick(), tooltip, hint }; Shift- and middle-click of the minimap
-- button (and the addon list entry) while the module runs
function Module:MinimapClick(def)
    local active = def.IsActive
    def.IsActive = function() return self:IsActive() and (not active or active()) end
    ns.AddMinimapShiftClick(def)
end

-- spells and items the icon picker lists first (call from OnEnable)
function Module:Featured(spells, items)
    for _, id in ipairs(spells or {}) do table.insert(ns.Macros.featuredSpells, id) end
    for _, id in ipairs(items or {}) do table.insert(ns.Macros.featuredItems, id) end
end
