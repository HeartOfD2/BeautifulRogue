-- ---------------------------------------------------------------------------
-- Miscellaneous module: small helpers for every class, as tabs of one page.
-- On by default, but every function has its own switch that is OFF until the player
-- turns it on: an active module alone hooks nothing and replaces nothing.
-- Other files add their tab with Misc.AddTab(key, label, Build, order); the page needs
-- no change for a new tab. Function options are account-wide (BeautifulRogueDB.misc).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

local Misc = ns.NewModule("misc", {
    title = L["Miscellaneous"],
    desc = L["Small helpers: camera zoom and more."],
})
ns.Misc = Misc

-- the account-wide table of one function (created on first write)
function Misc.Store(name)
    local a = ns.Acct()
    if type(a.misc) ~= "table" then a.misc = {} end
    if type(a.misc[name]) ~= "table" then a.misc[name] = {} end
    return a.misc[name]
end

-- the module runs for this character (also usable while the saved variables load)
function Misc:Wanted()
    return self:IsClassAllowed() and self:IsEnabledSetting()
end

-- ---------------------------------------------------------------- tab registry
local tabs = {}   -- { key, label, Build, order }

-- Build(frame, width) fills the body of the tab; it runs once, when the tab is first shown
function Misc.AddTab(key, label, Build, order)
    for _, t in ipairs(tabs) do
        if t.key == key then return end
    end
    tabs[#tabs + 1] = { key = key, label = label, Build = Build, order = order or (#tabs + 1) * 10 }
    table.sort(tabs, function(a, b) return a.order < b.order end)
end

function Misc.Tabs() return tabs end

-- functions with something to put in force register here (run on login, reset, module switch)
local appliers = {}
function Misc.OnApply(fn) appliers[#appliers + 1] = fn end

function Misc:Apply()
    for _, fn in ipairs(appliers) do fn() end
end

ns.On("DB_READY", function() Misc:Apply() end)
ns.On("LOGIN", function() Misc:Apply() end)
ns.On("SETTINGS_RESET", function() Misc:Apply() end)
function Misc:OnActiveChanged() self:Apply() end
