-- ---------------------------------------------------------------------------
-- Miscellaneous, tab Hide chat: a button hides all chat windows with their tabs, the edit
-- boxes and the chat menu buttons, and brings them back. Nothing is hooked and no button is
-- made while the switch is off. Hidden frames are only Hide()/Show()n; protected chat
-- functions are never called. The hooks are hooksecurefunc and stay inert after switching off.
-- Tabs and docks stay hidden when the game docks them again, and Enter / Reply reveal the
-- chat through the hooks below.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T = ns.L, ns.T
local Misc = ns.Misc
local Chat = {}
Misc.ChatHide = Chat

Chat.DEFAULTS = { on = true, hidden = false, locked = true, corner = "BOTTOMLEFT", size = 20, alpha = 0.9 }
Chat.RANGES = { size = { 16, 48, 2 }, alpha = { 0.2, 1, 0.05 } }
Chat.CORNERS = { BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }

local function Global(name) return rawget(_G, name) end

local function Store() return Misc.Store("chathide") end

function Chat.Get(key)
    local d = Chat.DEFAULTS[key]
    local v = Store()[key]
    if type(d) == "number" then
        if type(v) ~= "number" or v ~= v then return d end
        local r = Chat.RANGES[key]
        return math.max(r[1], math.min(r[2], v))
    end
    if key == "corner" then return Chat.CORNERS[v] and v or d end
    if type(v) == "boolean" then return v end
    return d
end

-- the custom color is stored as { r, g, b }; nil = the theme's accent
function Chat.GetColor()
    local c = Store().color
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then return c end
end

-- the dragged position: { x, y } from the bottom left of the screen; nil = the quick place
function Chat.GetPos()
    local p = Store().pos
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then return p end
end

function Chat.Set(key, value)
    Store()[key] = value
    if key == "corner" then Store().pos = nil end
    Misc:Apply()
end

function Chat.SetColor(c)
    Store().color = c and { c[1], c[2], c[3] } or nil
    Chat.Layout()
end

function Chat.ResetAnchor()
    local s = Store()
    s.pos, s.corner, s.size, s.alpha, s.color, s.locked = nil, nil, nil, nil, nil, nil
end

-- ---------------------------------------------------------------- the managed frames
local SINGLES = { "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton" }
local managed = {}   -- frame -> { forcing = bool }
local order = {}
local wasShown = {}  -- frame -> true when the game wanted it visible while we hid it
local active, editMode, installed = false, false, false

local function Hidden() return active and Chat.Get("hidden") and not editMode end

local function Add(f, edit)
    if type(f) ~= "table" or managed[f] or type(f.Hide) ~= "function" then return end
    managed[f] = {}
    order[#order + 1] = f
    if edit then return end   -- an edit box shows itself while typing; the hooks below reveal the chat
    -- the game shows tabs and windows again when it docks them: keep them away while hidden
    hooksecurefunc(f, "Show", function(self)
        if Hidden() and not managed[self].forcing then
            wasShown[self] = true
            self:Hide()
        end
    end)
    hooksecurefunc(f, "SetShown", function(self, shown)
        if shown and Hidden() and not managed[self].forcing then
            wasShown[self] = true
            self:Hide()
        end
    end)
end

local function Collect()
    local n = tonumber(Global("NUM_CHAT_WINDOWS")) or 10
    local i = 1
    while i <= n or Global("ChatFrame" .. i) do
        local name = "ChatFrame" .. i
        Add(Global(name))
        Add(Global(name .. "Tab"))
        Add(Global(name .. "ButtonFrame"))
        Add(Global(name .. "EditBox"), true)
        i = i + 1
    end
    for _, name in ipairs(SINGLES) do Add(Global(name)) end
end

-- hide or show everything to match the state
function Chat.Update()
    if not installed then return end
    Collect()
    if Hidden() then
        for _, f in ipairs(order) do
            if f:IsShown() then wasShown[f] = true end
            f:Hide()
        end
    else
        for _, f in ipairs(order) do
            if wasShown[f] then
                wasShown[f] = nil
                managed[f].forcing = true
                f:Show()
                managed[f].forcing = false
            end
        end
    end
    Chat.Layout()
end

function Chat.SetHidden(v)
    Store().hidden = v and true or false
    Chat.Update()
end

-- ---------------------------------------------------------------- the button
local btn

local function BuildButton()
    btn = CreateFrame("Button", "BeautifulRogueChatButton", UIParent)
    btn:SetFrameStrata("HIGH")
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:RegisterForClicks("LeftButtonUp")
    btn:RegisterForDrag("LeftButton")
    ns.Skin(btn, T.panel, T.accent)
    btn.dots = {}
    for i = 1, 3 do
        btn.dots[i] = btn:CreateTexture(nil, "ARTWORK")
        btn.dots[i]:SetTexture(ns.WHITE)
    end
    btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.hl:SetAllPoints()
    btn.hl:SetColorTexture(1, 1, 1, 0.12)
    -- the plate that marks the drag area while unlocked
    btn.mover = CreateFrame("Frame", nil, btn)
    btn.mover:SetPoint("TOPLEFT", -3, 3)
    btn.mover:SetPoint("BOTTOMRIGHT", 3, -3)
    btn.mover:SetFrameLevel(btn:GetFrameLevel())
    ns.Skin(btn.mover, T.accentSoft, T.accent)
    btn.mover.text = ns.HudText(btn.mover, 11)
    btn.mover.text:SetPoint("BOTTOM", btn.mover, "TOP", 0, 4)
    ns.Color(btn.mover.text, T.accent)
    btn.mover.text:SetText(L["Drag to move"])
    btn.mover:Hide()
    btn:SetScript("OnClick", function() Chat.SetHidden(not Chat.Get("hidden")) end)
    btn:SetScript("OnDragStart", function(self)
        if not Chat.Get("locked") then self:StartMoving() end
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetLeft(), self:GetBottom()
        if x and y then Store().pos = { x = x, y = y } end
        Chat.Layout()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Chat.Get("hidden") and L["Show chat"] or L["Hide chat"])
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:Hide()
end

-- size, place, opacity and color from the settings
function Chat.Layout()
    if not btn then return end
    local size = Chat.Get("size")
    btn:SetSize(size, size)
    btn:ClearAllPoints()
    local p = Chat.GetPos()
    if p then
        btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else
        local c = Chat.Get("corner")
        btn:SetPoint(c, UIParent, c, Chat.CORNERS[c][1], Chat.CORNERS[c][2])
    end
    btn:SetAlpha(Chat.Get("alpha"))
    local col = Chat.GetColor() or T.accent
    btn.edgeColor = { col[1], col[2], col[3], 1 }
    for _, e in ipairs(btn.edges) do e:SetColorTexture(col[1], col[2], col[3], 1) end
    local d = math.max(2, math.floor(size / 7 + 0.5))
    local on = not Chat.Get("hidden")
    for i, t in ipairs(btn.dots) do
        t:SetSize(d, d)
        t:ClearAllPoints()
        t:SetPoint("CENTER", btn, "CENTER", (i - 2) * (d * 2), 0)
        t:SetColorTexture(col[1], col[2], col[3], on and 1 or 0.35)
    end
    btn.mover:SetShown(not Chat.Get("locked"))
    Chat.PlaceMoverText()
end

-- the label of the drag plate always reads towards the middle of the screen
function Chat.PlaceMoverText()
    local t = btn.mover.text
    local cx, cy = btn:GetCenter()
    local right = not (cx and cx > UIParent:GetWidth() / 2)   -- on the left half: text runs to the right
    local above = not (cy and cy > UIParent:GetHeight() / 2)  -- on the bottom half: text sits above
    local h, v = right and "LEFT" or "RIGHT", above and "BOTTOM" or "TOP"
    t:ClearAllPoints()
    -- starts at the button's corner that faces the middle of the screen
    t:SetPoint(v .. h, btn, (above and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"), right and 4 or -4, above and 6 or -6)
    t:SetJustifyH(h)
end

function Chat.Button() return btn end

-- ---------------------------------------------------------------- hooks (made once, on first use)
local function Reveal()
    if active and Chat.Get("hidden") then Chat.SetHidden(false) end
end

local function Install()
    if installed then return end
    installed = true
    BuildButton()
    -- typing or replying shows the chat again
    for _, name in ipairs({ "ChatEdit_ActivateChat", "ChatFrame_OpenChat" }) do
        if type(Global(name)) == "function" then hooksecurefunc(name, Reveal) end
    end
    if type(Global("ChatFrameUtil")) == "table" and type(Global("ChatFrameUtil").OpenChat) == "function" then
        hooksecurefunc(Global("ChatFrameUtil"), "OpenChat", Reveal)
    end
    -- new and re-docked windows are taken in
    for _, name in ipairs({ "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow", "FCF_DockFrame", "FCF_DockUpdate" }) do
        if type(Global(name)) == "function" then
            hooksecurefunc(name, function() if active then C_Timer.After(0, Chat.Update) end end)
        end
    end
    -- the Edit Mode shows the chat while it is open
    local em = Global("EditModeManagerFrame")
    if type(em) == "table" and type(em.HookScript) == "function" then
        em:HookScript("OnShow", function() editMode = true Chat.Update() end)
        em:HookScript("OnHide", function() editMode = false Chat.Update() end)
        editMode = em:IsShown() and true or false
    end
end

Misc.OnApply(function()
    active = Misc:Wanted() and Chat.Get("on")
    if active then Install() end
    if not installed then return end
    btn:SetShown(active)
    Chat.Update()
end)

-- the game adds and re-docks windows on these
for _, ev in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
    ns.RegisterEvent(ev, function() if active then Chat.Update() end end)
end
ns.On("THEME_CHANGED", function() Chat.Layout() end)

Misc:Status(function()
    return L["Miscellaneous: hide chat %s"]:format(Chat.Get("on") and L["active"] or L["off"])
end)
