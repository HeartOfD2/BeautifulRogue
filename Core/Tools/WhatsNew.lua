-- ---------------------------------------------------------------------------
-- "What's new": a window with the new features of a version, in the player's
-- language. It opens once by itself after an update (a few seconds after
-- login, never during a fight) and again with /brogue news or the button on
-- the Modules page; a switch there (account-wide) keeps it from opening by
-- itself. A fresh install skips it: everything is new then.
--
-- The notes are written here, newest version first, as short entries (title +
-- text, translated in Locales). make_release.py --version should match the
-- newest one; a version without an entry of its own opens nothing.
--   Acct().news = { show = false|nil, seen = "<version>" }
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, UI, App = ns.L, ns.T, ns.UI, ns.App

local NOTES = {
    {
        version = "1.13.0", date = "2026-11-23",
        entries = {
            { L["Edit the rogue macros"], L["Rogue macros page: select a macro and click \"Edit ...\" (or double-click it). Change the text with placeholders; the preview beside it shows what goes into the game. Your version is kept for all characters and follows new weapons and poisons."] },
            { L["Reset one macro or all of them"], L["\"Reset\" under Selected macro gives one macro its default text again, \"Reset all macros\" every one. Both ask first; names, groups and action buttons stay."] },
            { L["Shift-click: the next missing poison or stone"], L["Shift-left-click on any poison or stone button applies what is missing next: the poison on the main hand, then on the off hand, then the sharpening stones in the same order. Click again for the next one."] },
            { L["Poison warning your way"], L["Layout › Poison tracker: from how many minutes the warning begins (also for the stones), whether it blinks, and sharpening stones on or off."] },
            { L["This window"], L["It opens once after an update. Switch it off under Addon › Modules › What's new; /brogue news opens it again."] },
        },
    },
}
ns.WHATS_NEW = NOTES

local W, H, PAD = 520, 440, 16
local win, area, versionText, showRow
local News = {}
ns.WhatsNew = News

local function Settings()
    local a = ns.Acct()
    if type(a.news) ~= "table" then a.news = {} end
    return a.news
end
function News.Enabled() return Settings().show ~= false end
function News.SetEnabled(on)
    Settings().show = on and true or false
    if showRow then showRow:Refresh() end
    App:RefreshCurrent()   -- the card on the Modules page
end
function News.Latest() return NOTES[1] and NOTES[1].version end

-- the notes newer than the version seen last; one version when it is unknown
local function Since(seen)
    local out = {}
    for _, n in ipairs(NOTES) do
        if n.version == seen then break end
        out[#out + 1] = n
    end
    if #out == 0 or (seen and #out == #NOTES and #NOTES > 1) then out = { NOTES[1] } end
    return out
end

-- height of a wrapped text: what the font says, at least the lines its full width needs
-- (a font not measured yet, or a client that reports one line)
local function TextHeight(fs, width, size, spacing)
    local h = fs:GetStringHeight() or 0
    local full = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
    if full <= 0 then full = #(fs:GetText() or "") * size * 0.5 end
    local lines = math.max(1, math.ceil(full / width))
    return math.max(h, lines * (size + (spacing or 0)) + 1)
end

local function Build()
    win = UI.Window("BeautifulRogueWhatsNew", W, H, L["What's new in %s"]:format(ns.TITLE), { strata = "FULLSCREEN" })   -- above the settings window (DIALOG), below its message boxes
    versionText = ns.Text(win, 11)
    versionText:SetPoint("TOPRIGHT", -32, -13)
    ns.Color(versionText, T.muted)

    area = UI.ScrollArea(win)
    area:SetPoint("TOPLEFT", PAD, -40)
    area:SetPoint("BOTTOMRIGHT", -PAD - 10, 48)
    area.child:SetWidth(W - 2 * PAD - 10)
    area.bar:ClearAllPoints()   -- beside the text, not over it
    area.bar:SetPoint("TOPLEFT", area, "TOPRIGHT", 4, 0)
    area.bar:SetPoint("BOTTOMLEFT", area, "BOTTOMRIGHT", 4, 0)
    area.items = {}

    local line = win:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", PAD, 42)
    line:SetPoint("BOTTOMRIGHT", -PAD, 42)
    line:SetHeight(1)
    ns.Color(line, T.line)

    showRow = UI.CheckRow(win, L["Show after updates"], News.Enabled, News.SetEnabled, 260)
    showRow:SetPoint("BOTTOMLEFT", PAD, 13)
    UI.Tooltip(showRow, { L["Show after updates"], L["Opens this window once after an update. Off: only with /brogue news or the button under Addon › Modules."] })
    local ok = UI.Button(win, 110, L["Got it"], function() win:Hide() end, 22)
    ok:SetPoint("BOTTOMRIGHT", -PAD, 11)
    ok:SetAccent(true)
end

-- the entries of the given notes, top down: version heading, then title + text per entry
local function Fill(list)
    local c = area.child
    local width = c:GetWidth()
    for _, o in ipairs(area.items) do o:Hide() end
    local used = 0
    local function Take(kind, make)
        used = used + 1
        local o = area.items[used]
        if not o or o.kind ~= kind then
            o = make()
            o.kind = kind
            area.items[used] = o
        end
        o:ClearAllPoints()
        o:Show()
        return o
    end
    local y = 0
    for i, n in ipairs(list) do
        if #list > 1 or i > 1 then
            local head = Take("head", function() return UI.Label(c, "", 0, 0) end)
            head:SetPoint("TOPLEFT", 0, y)
            head:SetText(L["VERSION %s"]:format(n.version))
            y = y - 20
        end
        for _, e in ipairs(n.entries) do
            local dot = Take("dot", function()
                local t = c:CreateTexture(nil, "ARTWORK")
                t:SetSize(6, 6)
                ns.Color(t, T.accent)
                return t
            end)
            dot:SetPoint("TOPLEFT", 2, y - 5)
            local title = Take("title", function()
                local fs = ns.Text(c, 13)
                fs:SetJustifyH("LEFT")
                ns.Color(fs, T.text)
                return fs
            end)
            title:SetPoint("TOPLEFT", 16, y)
            title:SetWidth(width - 16)
            title:SetText(e[1])
            y = y - TextHeight(title, width - 16, 13) - 4
            local body = Take("body", function()
                local fs = ns.Text(c, 12)
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(true)
                fs:SetSpacing(2)
                ns.Color(fs, T.muted)
                return fs
            end)
            body:SetPoint("TOPLEFT", 16, y)
            body:SetWidth(width - 16)
            body:SetText(e[2])
            y = y - TextHeight(body, width - 16, 12, 2) - 14
        end
    end
    area:SetContentHeight(-y)
    area:ScrollTo(0)
end

-- opens the window: all = the newest version (button, command), else what is new since the version seen last
function News.Open(all)
    if not NOTES[1] then return end
    if not win then Build() end
    local s = Settings()
    local list = all and { NOTES[1] } or Since(s.seen)
    versionText:SetText(L["Version"] .. " " .. list[1].version)
    s.seen = NOTES[1].version   -- seen once it opened: a /reload doesn't bring it back
    UI.PlaceDialog(win)
    win:Show()
    win:Raise()
    showRow:Refresh()
    Fill(list)
    return win
end
function News.IsShown() return win and win:IsShown() or false end
function News.Hide() if win then win:Hide() end end

-- after login: a fresh install only notes the version, an update opens the window once
local function Check()
    local s = Settings()
    local latest = News.Latest()
    if not latest or s.seen == latest then return end
    if s.seen == nil and ns.freshDatabase then
        s.seen = latest
        return
    end
    if not News.Enabled() then
        s.seen = latest
        return
    end
    if ns.InCombat() then
        News.waiting = true   -- after the fight
        return
    end
    News.Open()
end
News.Check = Check   -- for the tests

ns.On("LOGIN", function()
    if C_Timer and C_Timer.After then C_Timer.After(4, Check) else Check() end
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if News.waiting then
        News.waiting = false
        Check()
    end
end)

ns.AddCommand({ "news", "whatsnew" }, function() News.Open(true) end, L["what's new in this version"])

-- ---------------------------------------------------------------------------
-- Card on the Modules page: the switch and a button to open it
-- ---------------------------------------------------------------------------
App:AddBlock("modules", {
    key = "whatsnew", order = 20,
    Build = function(self, f, width)
        ns.Skin(f, T.panel)
        local title = ns.Text(f, 13)
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText(L["What's new"])
        ns.Color(title, T.text)
        local desc = UI.Hint(f, L["A window with the new features opens once after an update (for all characters)."], width - 20)
        desc:SetPoint("TOPLEFT", 10, -30)
        local y = -36 - math.max(14, desc:GetStringHeight() or 0)
        self.row = UI.CheckRow(f, L["Show after updates"], News.Enabled, News.SetEnabled, width - 190)
        self.row:SetPoint("TOPLEFT", 10, y)
        UI.Tooltip(self.row, { L["Show after updates"], L["Opens this window once after an update. Off: only with /brogue news or the button under Addon › Modules."] })
        local open = UI.Button(f, 160, L["Show now"] .. "  ›", function() News.Open(true) end, 20)
        open:SetPoint("TOPRIGHT", -10, y)
        return -y + 30
    end,
    Refresh = function(self) self.row:Refresh() end,
})
