-- ---------------------------------------------------------------------------
-- Settings pages of the Addon section: Modules, Reset and About.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX, UI, App = ns.L, ns.T, ns.HEX, ns.UI, ns.App

local modulesPage, resetPage   -- set at the end of the file; filled in while building

-- ---------------------------------------------------------------------------
-- Modules: switch feature packs on and off, plus their own settings
-- ---------------------------------------------------------------------------
local function BuildModules(p)
    UI.Label(p, L["MODULES"], 0, 0)
    local intro = UI.Hint(p, L["Modules add features. One made for a class stays off for the other classes."], App.CONTENT_W)
    intro:SetPoint("TOPLEFT", 0, -18)
    local sections = {}
    -- texts may wrap (other fonts, longer translations): measure them
    local function Lines(fs) return math.max(14, fs:GetStringHeight() or 0) end
    -- the cards scroll: switches of the core first (blocks of this page), then the modules
    local area = UI.ScrollArea(p)
    area:SetPoint("TOPLEFT", 0, -34 - Lines(intro))
    area:SetPoint("BOTTOMRIGHT", 0, 0)
    area.child:SetWidth(App.CONTENT_W)
    local list = area.child
    local y = App:PlaceBlocks("modules", list, 0, 0, App.CONTENT_W, 10)
    local shown = 0
    for _, key in ipairs(ns.moduleOrder) do
        local m = ns.modules[key]
        if m:IsClassAllowed() then
        shown = shown + 1
        local s = CreateFrame("Frame", nil, list)
        s:SetPoint("TOPLEFT", 0, y)
        s:SetSize(App.CONTENT_W, 60)
        ns.Skin(s, T.panel)
        s.row = UI.CheckRow(s, m.title or key,
            function() return m:IsEnabledSetting() end,
            function(v)
                m:SetEnabled(v)
                modulesPage.Refresh()
            end, 240)
        s.row:SetPoint("TOPLEFT", 10, -8)
        s.row.label:SetFontObject(GameFontHighlight)
        ns.ApplyFont(s.row.label, 13, "")
        s.status = ns.Text(s, 11)
        s.status:SetPoint("TOPRIGHT", -10, -12)
        s.desc = UI.Hint(s, (m.accountWide and (L["All characters"] .. " · ") or "") .. (m.desc or ""), App.CONTENT_W - 20)
        s.desc:SetPoint("TOPLEFT", 10, -30)
        local h = 38 + Lines(s.desc)
        if m.BuildOptions then
            local box = CreateFrame("Frame", nil, s)
            box:SetPoint("TOPLEFT", 10, -h)
            box:SetSize(App.CONTENT_W - 20, 10)
            local used = m:BuildOptions(box, App.CONTENT_W - 20) or 0
            box:SetHeight(used)
            s.options = box
            h = h + used + 8
        end
        s:SetHeight(h)
        y = y - h - 10
        s.module = m
        sections[#sections + 1] = s
        end
    end
    if shown == 0 then
        local none = UI.Hint(list, L["There is no module for this class yet."], App.CONTENT_W)
        none:SetPoint("TOPLEFT", 0, y)
        y = y - 20
    end
    area:SetContentHeight(-y)
    modulesPage.Refresh = function()
        for _, def in ipairs(App.blocks.modules or {}) do
            if def.frame and def.Refresh then ns.SafeCall(def.Refresh, def) end
        end
        for _, s in ipairs(sections) do
            local m = s.module
            s.row:Refresh()
            local allowed = m:IsClassAllowed()
            s.row:SetDisabled(not allowed)
            if not allowed then
                s.status:SetText(ns.Muted(m.classHint or L["not for this class"]))
            elseif m:IsActive() then
                s.status:SetText(ns.Colorize(HEX.good, L["active"]))
            else
                s.status:SetText(ns.Muted(L["off"]))
            end
            if s.options then
                if m.RefreshOptions then m:RefreshOptions() end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Reset: tick what to reset
-- ---------------------------------------------------------------------------
local function BuildReset(p)
    UI.Label(p, L["CHOOSE WHAT TO RESET"], 0, 0)
    local selected = {}
    local rows = {}
    local ROW_H, HEAD_H = 24, 26
    -- the list scrolls: more modules mean more categories
    local area = UI.ScrollArea(p)
    area:SetPoint("TOPLEFT", 0, -20)
    area:SetPoint("BOTTOMRIGHT", 0, 40)
    area.child:SetWidth(App.CONTENT_W)
    local list = area.child
    local y = 0
    -- same headings and order as the sidebar; a category without a group counts as Addon
    for _, section in ipairs(App.sections) do
        local first = true
        for _, def in ipairs(ns.resetCategories) do
            if (def.group or "addon") == section.key and (not def.IsVisible or def.IsVisible()) then
                if first then
                    first = false
                    local head = UI.Label(list, section.label, 0, y - 8)
                    ns.Color(head, T.accent)
                    y = y - HEAD_H
                end
                local row = UI.CheckRow(list, def.label,
                    function() return selected[def.key] end,
                    function(v) selected[def.key] = v or nil end, 200)
                row:SetPoint("TOPLEFT", 0, y)
                y = y - ROW_H
                if def.danger then ns.Color(row.label, T.alert) end
                row.desc = ns.Text(list, 11)
                row.desc:SetPoint("LEFT", row, "RIGHT", 6, 0)
                row.desc:SetWidth(App.CONTENT_W - 232)
                row.desc:SetJustifyH("LEFT")
                row.desc:SetWordWrap(false)
                ns.Color(row.desc, T.muted)
                row.desc:SetText((def.accountWide and (L["All characters"] .. " · ") or "") .. def.desc)
                UI.Tooltip(row, { def.label, def.desc, def.accountWide and L["Applies to all characters of this account."]
                    or L["Applies to this character only."] })
                rows[#rows + 1] = row
            end
        end
    end
    area:SetContentHeight(-y + 4)
    local function RefreshRows() for _, r in ipairs(rows) do r:Refresh() end end
    local all = UI.Button(p, 110, L["Select all"], function()
        for _, def in ipairs(ns.resetCategories) do
            if not def.danger and (not def.IsVisible or def.IsVisible()) then selected[def.key] = true end
        end
        RefreshRows()
    end)
    all:SetPoint("BOTTOMLEFT", 0, 0)
    local none = UI.Button(p, 110, L["Select none"], function()
        wipe(selected)
        RefreshRows()
    end)
    none:SetPoint("LEFT", all, "RIGHT", 6, 0)
    local go = UI.ConfirmButton(p, 150, L["Reset selected"], function()
        if not next(selected) then App.Status(L["Nothing selected."], true) return end
        local done = ns.ResetCategories(selected)
        wipe(selected)
        RefreshRows()
        App.Status(L["Reset: %s."]:format(table.concat(done, ", ")))
        ns.Print(L["Reset: %s."]:format(table.concat(done, ", ")))
    end)
    go:SetPoint("BOTTOMRIGHT", 0, 0)
    go:SetAccent(true)
    resetPage.Refresh = RefreshRows
end

-- ---------------------------------------------------------------------------
-- About
-- ---------------------------------------------------------------------------
local function BuildAbout(p)
    local logo = p:CreateTexture(nil, "ARTWORK")
    logo:SetSize(128, 128)
    logo:SetPoint("TOPLEFT", 0, 0)
    logo:SetTexture("Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\Logo")
    local title = ns.Text(p, 20)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 18, -10)
    title:SetText(ns.TITLE)
    ns.Color(title, T.accent)
    local version = ns.Text(p, 12)
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    version:SetText(L["Version"] .. " " .. ns.VERSION .. "  ·  " .. L["for WoW: Forever"])
    ns.Color(version, T.muted)
    local desc = UI.Hint(p, L["A compact combat frame for health, resource, combo points, range and cooldowns, with a macro manager and player notes. Class features come as modules (see the Modules page)."], App.CONTENT_W - 146)
    desc:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -12)
    ns.Color(desc, T.text)
    desc:SetSpacing(3)

    UI.Label(p, L["CREDITS"], 0, -150)
    local credits = UI.Hint(p, table.concat({
        L["Author: %s"]:format("HeartOfD2"),
        L["License: MIT  ·  Source: github.com/HeartOfD2/BeautifulRogue"],
    }, "\n"), App.CONTENT_W)
    credits:SetPoint("TOPLEFT", 0, -168)
    credits:SetSpacing(4)

    UI.Label(p, L["CHAT COMMANDS"], 0, -236)
    local help = UI.Hint(p, "", App.CONTENT_W)
    help:SetPoint("TOPLEFT", 0, -254)
    help:SetSpacing(3)
    ns.Paint(function() help:SetText(ns.CommandHelpText and ns.CommandHelpText() or "") end)
end


modulesPage = App:AddPage({
    key = "modules", section = "addon", label = L["Modules"], order = 910,
    Build = function(_, frame) BuildModules(frame) end,
})
resetPage = App:AddPage({
    key = "reset", section = "addon", label = L["Reset"], order = 930,
    Build = function(_, frame) BuildReset(frame) end,
})
App:AddPage({
    key = "about", section = "addon", label = L["About"], order = 990,
    Build = function(_, frame) BuildAbout(frame) end,
})
