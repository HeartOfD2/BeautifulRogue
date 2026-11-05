-- ---------------------------------------------------------------------------
-- Miscellaneous, tab Copy chat: a small icon on every chat window opens its text in a window
-- where it can be selected and copied. Nothing is hooked and no icon is made while the switch
-- is off. Lines are read through GetNumMessages / GetMessageInfo; a line whose text is
-- a secret value is never read or joined, only counted.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, UI = ns.L, ns.T, ns.UI
local Misc = ns.Misc
local Copy = {}
Misc.ChatCopy = Copy

Copy.DEFAULTS = { on = true, corner = "BOTTOMRIGHT", hover = true, iconSize = 18, size = 13,
    limit = 300, time = false, colors = true }
Copy.RANGES = { iconSize = { 14, 32, 2 }, size = { 9, 24, 1 }, limit = { 50, 1000, 50 } }
Copy.CORNERS = { TOPLEFT = { 3, -3 }, TOPRIGHT = { -3, -3 }, BOTTOMLEFT = { 3, 3 }, BOTTOMRIGHT = { -3, 3 } }
Copy.TEXTURE = "Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\ChatCopy"

local function Global(name) return rawget(_G, name) end
local function IsSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) and true or false end
local function Store() return Misc.Store("chatcopy") end

function Copy.Get(key)
    local d = Copy.DEFAULTS[key]
    local v = Store()[key]
    if type(d) == "number" then
        if type(v) ~= "number" or v ~= v then return d end
        local r = Copy.RANGES[key]
        return math.max(r[1], math.min(r[2], v))
    end
    if key == "corner" then return Copy.CORNERS[v] and v or d end
    if type(v) == "boolean" then return v end
    return d
end

function Copy.Set(key, value)
    Store()[key] = value
    Misc:Apply()
end

-- ---------------------------------------------------------------- reading the chat
-- the clock time of each line, counted from the newest message (kept per chat window)
local stamps, hooked = {}, {}
local active, installed = false, false

local function HookAdd(cf)
    if hooked[cf] or type(cf.AddMessage) ~= "function" then return end
    hooked[cf] = true
    stamps[cf] = { n = 0 }
    hooksecurefunc(cf, "AddMessage", function(self)
        local s = stamps[self]
        if not (active and s) then return end
        s.n = s.n + 1
        s[s.n] = time()
        s[s.n - 2000] = nil
    end)
end

-- links show their text, icons and colors go: the window sets the color itself. With names on,
-- the class color of a player name (inside the player link) stays, and the line color resumes after it
local function Clean(text, names, resume)
    text = text:gsub("|Hplayer:.-|h(.-)|h", function(inner)
        if names then inner = inner:gsub("|c(%x%x%x%x%x%x%x%x)(.-)|r", "%1%2") end
        return inner
    end)
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    if names then
        text = text:gsub("(%x+)(.-)", function(c, n) return "|c" .. c .. n .. resume end)
    end
    return text
end

local function Byte(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end

-- the lines of a chat window as text (newest last): lines, protected count, total read
function Copy.Lines(cf, query)
    local out, secret, total = {}, 0, 0
    if type(cf) ~= "table" or type(cf.GetNumMessages) ~= "function" or type(cf.GetMessageInfo) ~= "function" then
        return out, secret, total
    end
    local n = cf:GetNumMessages()
    if type(n) ~= "number" or IsSecret(n) then return out, secret, total end
    local first = math.max(1, n - Copy.Get("limit") + 1)
    local st = stamps[cf]
    local colors, withTime = Copy.Get("colors"), Copy.Get("time")
    query = query and query ~= "" and query:lower() or nil
    for i = first, n do
        local text, r, g, b = cf:GetMessageInfo(i)
        total = total + 1
        if IsSecret(text) then
            secret = secret + 1
        elseif type(text) == "string" then
            local tint = colors and type(r) == "number" and type(g) == "number" and type(b) == "number"
                and not IsSecret(r) and not IsSecret(g) and not IsSecret(b)
            local base = tint and ("|cff%02x%02x%02x"):format(Byte(r), Byte(g), Byte(b)) or nil
            local line = Clean(text, colors, base or "|r")
            if not query or line:lower():find(query, 1, true) then
                if withTime and st then
                    local t = st[st.n - (n - i)]
                    if t then line = date("%H:%M:%S", t) .. " " .. line end
                end
                if base then line = base .. line .. "|r" end
                out[#out + 1] = line
            end
        end
    end
    return out, secret, total
end

local function FrameName(cf)
    local id = type(cf.GetID) == "function" and cf:GetID() or nil
    if type(Global("GetChatWindowInfo")) == "function" and type(id) == "number" then
        local name = Global("GetChatWindowInfo")(id)
        if type(name) == "string" and not IsSecret(name) and name ~= "" then return name end
    end
    return L["Chat window %d"]:format(type(id) == "number" and id or 1)
end

-- ---------------------------------------------------------------- the window
local win

local function SetStatus()
    local lines, secret = win.shown or 0, win.secret or 0
    if secret > 0 then
        win.setStatus(L["%d lines · %d lines protected by the game · Ctrl+A, Ctrl+C to copy"]:format(lines, secret))
    else
        win.setStatus(L["%d lines · Ctrl+A, Ctrl+C to copy"]:format(lines))
    end
end

function Copy.Refresh()
    if not (win and win:IsShown() and win.cf) then return end
    local lines, secret = Copy.Lines(win.cf, win.search:GetText())
    win.shown, win.secret = #lines, secret
    win.full = table.concat(lines, "\n")
    win.area:SetValue(win.full)
    ns.ApplyFont(win.area.edit, Copy.Get("size"), "")
    SetStatus()
    -- the newest lines first: scroll down once the text has its height
    C_Timer.After(0, function()
        if win:IsShown() then
            local sf = win.area.scroll
            sf:SetVerticalScroll(sf:GetVerticalScrollRange() or 0)
        end
    end)
end

local function BuildWindow()
    win = UI.Window("BeautifulRogueChatCopy", 680, 480, L["Copy chat"])
    win:SetPoint("CENTER")

    win.search = UI.LineEdit(win, 12, 60)
    win.search:SetSize(170, 22)
    win.search:SetPoint("TOPLEFT", 14, -38)
    UI.Placeholder(win.search, L["Search"])
    win.search:SetScript("OnTextChanged", function(_, user) if user then Copy.Refresh() end end)

    win.timeCheck = UI.CheckRow(win, L["Timestamps"],
        function() return Copy.Get("time") end, function(v) Store().time = v Copy.Refresh() end, 110)
    win.timeCheck:SetPoint("LEFT", win.search, "RIGHT", 14, 0)
    win.colorCheck = UI.CheckRow(win, L["Channel colors"],
        function() return Copy.Get("colors") end, function(v) Store().colors = v Copy.Refresh() end, 130)
    win.colorCheck:SetPoint("LEFT", win.timeCheck, "RIGHT", 8, 0)

    local r = Copy.RANGES.size
    win.sizeSlider = UI.Slider(win, r[1], r[2], r[3], function() return Copy.Get("size") end, function(v)
        Store().size = v
        if win.area then ns.ApplyFont(win.area.edit, v, "") end
    end, 90)
    win.sizeSlider:SetPoint("TOPRIGHT", -34, -43)
    win.sizeLabel = ns.Text(win, 11)
    win.sizeLabel:SetPoint("RIGHT", win.sizeSlider, "LEFT", -8, 0)
    ns.Color(win.sizeLabel, T.muted)
    win.sizeLabel:SetText(L["Font size"])

    win.area = UI.TextArea(win)
    win.area:SetPoint("TOPLEFT", 14, -70)
    win.area:SetPoint("BOTTOMRIGHT", -14, 34)
    -- read-only: typing puts the text back
    win.area.edit:SetScript("OnTextChanged", function(self, user)
        if user and win.full and self:GetText() ~= win.full then self:SetText(win.full) end
    end)

    win.setStatus, win.statusText = UI.StatusLine(win)
    win:SetScript("OnShow", function()
        win.sizeSlider:Refresh()
        if win.timeCheck.Refresh then win.timeCheck:Refresh() end
        if win.colorCheck.Refresh then win.colorCheck:Refresh() end
    end)
end

function Copy.Open(cf)
    if not active then return end
    if not win then BuildWindow() end
    if win:IsShown() and win.cf == cf then win:Hide() return end
    win.cf = cf
    win.title:SetText(L["Copy chat"] .. " - " .. FrameName(cf))
    win:Show()
    Copy.Refresh()
end

function Copy.Window() return win end

-- ---------------------------------------------------------------- the icons
local buttons = {}   -- chat window -> icon button
local watch          -- shows the icons only while the mouse is over a chat window

local function MakeButton(cf)
    local b = CreateFrame("Button", nil, cf)
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("LeftButtonUp")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexture(Copy.TEXTURE)
    b:SetScript("OnClick", function() Copy.Open(cf) end)
    b:SetScript("OnEnter", function(self)
        local c = T.accent
        self.icon:SetVertexColor(c[1], c[2], c[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Copy chat"])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        local c = T.text
        self.icon:SetVertexColor(c[1], c[2], c[3], 1)
        GameTooltip:Hide()
    end)
    buttons[cf] = b
    return b
end

local function Layout(cf, b)
    local size, corner = Copy.Get("iconSize"), Copy.Get("corner")
    b:SetSize(size, size)
    b:ClearAllPoints()
    b:SetPoint(corner, cf, corner, Copy.CORNERS[corner][1], Copy.CORNERS[corner][2])
    local p, c = T.panel, T.text
    b.bg:SetColorTexture(p[1], p[2], p[3], 0.75)
    b.icon:SetVertexColor(c[1], c[2], c[3], 1)
    b:SetAlpha(Copy.Get("hover") and 0 or 0.9)
end

function Copy.Update()
    if not installed then return end
    local n = tonumber(Global("NUM_CHAT_WINDOWS")) or 10
    local i = 1
    while i <= n or Global("ChatFrame" .. i) do
        local cf = Global("ChatFrame" .. i)
        if type(cf) == "table" and type(cf.SetScript) == "function" then
            local b = buttons[cf] or MakeButton(cf)
            if active then HookAdd(cf) end
            Layout(cf, b)
            b:SetShown(active)
        end
        i = i + 1
    end
    watch:SetShown(active and Copy.Get("hover"))
    if not active and win then win:Hide() end
end

local function Install()
    if installed then return end
    installed = true
    watch = CreateFrame("Frame")
    local acc = 0
    watch:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        for cf, b in pairs(buttons) do
            b:SetAlpha((b:IsMouseOver() or cf:IsMouseOver()) and 0.9 or 0)
        end
    end)
    watch:Hide()
end

Misc.OnApply(function()
    active = Misc:Wanted() and Copy.Get("on")
    if active then Install() end
    Copy.Update()
end)

for _, ev in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
    ns.RegisterEvent(ev, function() if active then Copy.Update() end end)
end
ns.On("THEME_CHANGED", function() Copy.Update() end)

Misc:Status(function()
    return L["Miscellaneous: copy chat %s"]:format(Copy.Get("on") and L["active"] or L["off"])
end)
