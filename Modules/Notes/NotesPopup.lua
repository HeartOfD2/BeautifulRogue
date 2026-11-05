-- ---------------------------------------------------------------------------
-- Notes: the target popup. Movable, resizable and lockable (geometry in DB().popup);
-- shows the targeted player's notes, or a slim "+ Note" bar when there are none.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX, UI, App, Text, Muted = ns.L, ns.T, ns.HEX, ns.UI, ns.App, ns.Text, ns.Muted
local Notes = ns.Notes
local Stamp, Untitled, DB, NewNote, RemoveNote = Notes.Stamp, Notes.Untitled, Notes.DB, Notes.NewNote, Notes.RemoveNote
local Discard, Touch, Latest, DisplayName, TargetKey = Notes.Discard, Notes.Touch, Notes.Latest, Notes.DisplayName, Notes.TargetKey
local Player, EnsurePlayer, DropPlayerIfEmpty, Changed = Notes.Player, Notes.EnsurePlayer, Notes.DropPlayerIfEmpty, Notes.Changed

-- ---------------------------------------------------------------------------
-- Target popup: movable, resizable and lockable; geometry in DB().popup
-- ---------------------------------------------------------------------------
local COMPACT_H = 30
local POPUP_DEF = { point = "CENTER", x = 260, y = 120, w = 280, h = 170 }
local POPUP_MIN_W, POPUP_MIN_H = 220, 120

local pop = UI.Window("BeautifulRogueTargetNote", POPUP_DEF.w, POPUP_DEF.h, "", { noEscape = true, fixed = true })
local popLayer = Notes.Layer("popup")
pop:SetParent(popLayer)
pop:SetFrameStrata("MEDIUM")
-- stepping aside in combat ends the writing (the text is saved as you type)
popLayer:SetScript("OnHide", function() if pop.body.edit:HasFocus() then pop.body.edit:ClearFocus() end end)
pop:SetMovable(true)
pop:SetResizable(true)
pop:SetClampedToScreen(true)
if pop.SetResizeBounds then pop:SetResizeBounds(POPUP_MIN_W, POPUP_MIN_H, 1200, 900) end
pop:RegisterForDrag("LeftButton")
pop:SetPoint(POPUP_DEF.point, UIParent, POPUP_DEF.point, POPUP_DEF.x, POPUP_DEF.y)
pop.title:SetPoint("TOPRIGHT", -112, -11)   -- long names stop short of the buttons
pop.title:SetJustifyH("LEFT")
pop.title:SetWordWrap(false)

local function Geom()
    local d = DB()
    d.popup = d.popup or {}
    return d.popup
end
function pop:IsLocked() return Geom().locked and true or false end
-- re-anchor by the top-left corner so the compact bar keeps its top edge
function pop:SaveGeometry()
    local l, t = self:GetLeft(), self:GetTop()
    if not (l and t) then return end
    local g = Geom()
    g.l, g.t, g.w = l, t, self:GetWidth()
    if not self.compact then g.h = self:GetHeight() end
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
end
function pop:FullHeight() return math.max(POPUP_MIN_H, Geom().h or POPUP_DEF.h) end
function pop:ApplyGeometry()
    local g = Geom()
    self:ClearAllPoints()
    if g.l and g.t then
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.l, g.t)
    else
        self:SetPoint(POPUP_DEF.point, UIParent, POPUP_DEF.point, POPUP_DEF.x, POPUP_DEF.y)
    end
    self:SetWidth(math.max(POPUP_MIN_W, g.w or POPUP_DEF.w))
    self:SetHeight(self.compact and COMPACT_H or self:FullHeight())
    self:UpdateLock()
end

pop.grip = CreateFrame("Button", nil, pop)
pop.grip:SetSize(16, 16)
pop.grip:SetPoint("BOTTOMRIGHT", -2, 2)
pop.grip:SetFrameLevel(pop:GetFrameLevel() + 10)
pop.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
pop.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
pop.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
pop.grip:SetScript("OnMouseDown", function() if not pop:IsLocked() then pop:StartSizing("BOTTOMRIGHT") end end)
pop.grip:SetScript("OnMouseUp", function()
    pop:StopMovingOrSizing()
    pop:SaveGeometry()
end)

-- the lock, as on the sticky notes; shown in the compact bar too
pop.lockBtn = CreateFrame("Button", nil, pop)
pop.lockBtn:SetSize(18, 18)
pop.lockBtn:SetPoint("TOPRIGHT", -28, -6)
pop.lockBtn.icon = pop.lockBtn:CreateTexture(nil, "ARTWORK")
pop.lockBtn.icon:SetSize(14, 14)
pop.lockBtn.icon:SetPoint("CENTER")
pop.lockBtn.hl = pop.lockBtn:CreateTexture(nil, "HIGHLIGHT")
pop.lockBtn.hl:SetAllPoints()
ns.Color(pop.lockBtn.hl, T.hover)
pop.lockBtn:SetScript("OnClick", function()
    local g = Geom()
    g.locked = not g.locked or nil
    pop:UpdateLock()
end)
UI.Tooltip(pop.lockBtn, function()
    return { pop:IsLocked() and L["Unlock: allow moving and resizing"] or L["Lock position and size"] }
end, "ANCHOR_TOP")
function pop:UpdateLock()
    local locked = self:IsLocked()
    local c = locked and T.accent or T.muted
    self.lockBtn.icon:SetTexture("Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\" .. (locked and "Lock" or "Unlock"))
    self.lockBtn.icon:SetVertexColor(c[1], c[2], c[3], 1)
    self.grip:SetShown(not locked and not self.compact)
end
ns.Paint(function() if ns.ready then pop:UpdateLock() end end)
pop:SetScript("OnDragStart", function(self) if not self:IsLocked() then self:StartMoving() end end)
pop:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SaveGeometry()
end)

local popKey, popNote, dismissedKey
local RefreshPopup, NoteForTarget, OpenInNotes
local function Status(msg, alert) App.Status(msg, alert) end

-- the title opens this player's notes in the app (and still drags the popup)
pop.titleBtn = CreateFrame("Button", nil, pop)
pop.titleBtn:SetPoint("TOPLEFT", 8, -5)
pop.titleBtn:SetPoint("TOPRIGHT", -112, -5)
pop.titleBtn:SetHeight(22)
pop.titleBtn:RegisterForDrag("LeftButton")
pop.titleBtn.hl = pop.titleBtn:CreateTexture(nil, "HIGHLIGHT")
pop.titleBtn.hl:SetAllPoints()
ns.Color(pop.titleBtn.hl, T.hover)
pop.titleBtn:SetScript("OnClick", function() OpenInNotes() end)
pop.titleBtn:SetScript("OnDragStart", function() if not pop:IsLocked() then pop:StartMoving() end end)
pop.titleBtn:SetScript("OnDragStop", function()
    pop:StopMovingOrSizing()
    pop:SaveGeometry()
end)
UI.Tooltip(pop.titleBtn, function()
    local who = pop.who
    return { who and DisplayName(who) or L["NOTES"], L["Open in the notes"] }
end, "ANCHOR_TOP")

local function NavButton(dir, x)
    local b = CreateFrame("Button", nil, pop)
    b:SetSize(16, 16)
    b:SetPoint("TOPLEFT", x, -33)
    b.arrow = UI.Arrow(b, 12, dir)
    b.arrow:SetPoint("CENTER")
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.1)
    return b
end
pop.prev = NavButton("left", 8)
pop.next = NavButton("right", 26)
pop.noteTitle = Text(pop, 12)
pop.noteTitle:SetPoint("TOPLEFT", 48, -34)
pop.noteTitle:SetPoint("TOPRIGHT", -126, -34)
pop.noteTitle:SetJustifyH("LEFT")
pop.noteTitle:SetWordWrap(false)
pop.date = CreateFrame("Frame", nil, pop)
pop.date:SetSize(100, 16)
pop.date:SetPoint("TOPRIGHT", -30, -33)
pop.date.text = Text(pop.date, 10)
pop.date.text:SetPoint("RIGHT")
pop.date:EnableMouse(true)
UI.Tooltip(pop.date, function()
    if not popNote then return end
    return { Untitled(popNote), L["Created: %s"]:format(Stamp(popNote.created)), L["Updated: %s"]:format(Stamp(popNote.updated)) }
end, "ANCHOR_TOP")

-- small red delete button right of the date: the first click arms it, the second deletes
pop.del = CreateFrame("Button", nil, pop)
pop.del:SetSize(16, 16)
pop.del:SetPoint("TOPRIGHT", -10, -33)
pop.del.bg = pop.del:CreateTexture(nil, "BACKGROUND")
pop.del.bg:SetAllPoints()
pop.del.x = Text(pop.del, 13)
pop.del.x:SetPoint("CENTER", 0, 1)
pop.del.x:SetText("×")
pop.del.hl = pop.del:CreateTexture(nil, "HIGHLIGHT")
pop.del.hl:SetAllPoints()
pop.del.hl:SetColorTexture(1, 1, 1, 0.15)
local delArmedUntil = 0
local function DisarmDelete()
    delArmedUntil = 0
    pop.del.bg:SetColorTexture(0.55, 0.12, 0.14, 1)
end
DisarmDelete()
UI.Tooltip(pop.del, { L["Delete this note"], L["Click twice to confirm."] }, "ANCHOR_TOP")

pop.body = ns.NoteEditor.Create(pop, { skin = true, toolbar = true, size = 12 })
pop.body:SetPoint("TOPLEFT", 10, -54)
pop.body:SetPoint("BOTTOMRIGHT", -10, 10)

pop.addBtn = UI.Button(pop, 64, "+ " .. L["Note"], function() NoteForTarget() end, 18)
pop.addBtn:SetPoint("TOPRIGHT", -50, -6)
pop.newBtn = UI.Button(pop, 22, "+", function() NoteForTarget() end, 18)
pop.newBtn:SetPoint("TOPRIGHT", -50, -6)
UI.Tooltip(pop.newBtn, { L["New note for this player"] }, "ANCHOR_TOP")

pop.close:SetScript("OnClick", function()
    dismissedKey = popKey   -- stays closed until you target someone else
    pop.body.edit:ClearFocus()
    pop:Hide()
end)

local function SetCompact(compact)
    pop.compact = compact
    for _, r in ipairs({ pop.body, pop.prev, pop.next, pop.noteTitle, pop.date, pop.del, pop.newBtn }) do
        r:SetShown(not compact)
    end
    pop.addBtn:SetShown(compact)
    pop:SetHeight(compact and COMPACT_H or pop:FullHeight())
    pop:UpdateLock()
end

local function ShowPopNote(p)
    local i = ns.IndexOf(p.notes, popNote) or 1
    pop.noteTitle:SetText(Untitled(popNote) .. "  " .. Muted(i .. "/" .. #p.notes))
    pop.date.text:SetText(Muted(Stamp(popNote.updated)))
    DisarmDelete()
    local many = #p.notes > 1
    pop.prev:SetAlpha(many and 1 or 0.3)
    pop.next:SetAlpha(many and 1 or 0.3)
    if not pop.body.edit:HasFocus() then pop.body:SetValue(popNote.text) end
end

local function Browse(step)
    local p = Player(popKey)
    if not (p and popNote and #p.notes > 1) then return end
    pop.body.edit:ClearFocus()
    local i = ns.IndexOf(p.notes, popNote) or 1
    popNote = p.notes[(i - 1 + step) % #p.notes + 1]
    ShowPopNote(p)
end
pop.prev:SetScript("OnClick", function() Browse(-1) end)
pop.next:SetScript("OnClick", function() Browse(1) end)

pop.del:SetScript("OnClick", function()
    local p = Player(popKey)
    if not (p and popNote) then return end
    if GetTime() > delArmedUntil then
        delArmedUntil = GetTime() + 3
        pop.del.bg:SetColorTexture(0.95, 0.22, 0.24, 1)
        pop.date.text:SetText(ns.Colorize(HEX.alert, L["click again to delete"]))
        local armedNote = popNote
        C_Timer.After(3.05, function()
            if popNote == armedNote and GetTime() >= delArmedUntil and pop:IsShown() then ShowPopNote(p) end
        end)
        return
    end
    pop.body.edit:ClearFocus()
    RemoveNote(p, popNote)
    popNote = Latest(p)
    DropPlayerIfEmpty(popKey)
    RefreshPopup()
    Changed("popup")
end)

pop.body.onChange = function(text)
    if not popNote then return end
    popNote.text = text
    Touch(popNote)
    pop.date.text:SetText(Muted(Stamp(popNote.updated)))
    Changed("popup")
end

RefreshPopup = function()
    if not ns.ready then return end
    local key, info = TargetKey()
    if key ~= popKey then
        -- leaving a player: drop a note that was created but never written
        local p = Player(popKey)
        if p and Discard(p, popNote) then
            DropPlayerIfEmpty(popKey)
            Changed("popup")
        end
        if pop.body.edit:HasFocus() then pop.body.edit:ClearFocus() end
        dismissedKey, popNote = nil, nil
    end
    popKey = key
    local d = DB()
    if not key or d.popupOff or dismissedKey == key then
        pop:Hide()
        return
    end
    local p = Player(key)
    pop.title:SetText(Muted(L["NOTES"] .. "  ·") .. "  " .. DisplayName(p or info, true))
    pop.who = p or info
    if p and #p.notes > 0 then
        if not (popNote and ns.IndexOf(p.notes, popNote)) then popNote = Latest(p) end
        SetCompact(false)
        ShowPopNote(p)
        pop:Show()
    elseif not d.addBarOff then
        popNote = nil
        SetCompact(true)
        pop:Show()
    else
        pop:Hide()
    end
end

NoteForTarget = function()
    local key, info = TargetKey()
    if not key then
        Status(L["Target a player first."], true)
        ns.Print(L["Target a player first."])
        return
    end
    local p = EnsurePlayer(key, info)
    p.collapsed = nil
    local note = NewNote(p)
    -- with the popup switched off, the notes page is where you type
    if DB().popupOff and not App:IsOpen("notes") then App:Open("notes") end
    if App:IsOpen("notes") then
        Notes.Select("players", note, p)
    end
    dismissedKey = nil
    popNote = note
    RefreshPopup()
    popNote = note
    if pop:IsShown() then
        ShowPopNote(p)
        pop.body:Edit()
    else
        Notes.EditSelected("players")
    end
    Changed("new")
end
ns.NoteForTarget = NoteForTarget

-- from the popup title: this player in the Players tab, the shown note selected
OpenInNotes = function()
    App:Open("notes")
    Notes.ShowSub("players")
    local p = Player(popKey)
    if not p then return end
    p.collapsed = nil
    if popNote and ns.IndexOf(p.notes, popNote) then
        Notes.views.players:Select(popNote, p)
    else
        Notes.views.players:Select(p, nil)
    end
end

Notes.RefreshPopup = RefreshPopup

Notes.OnChange(function(source)
    if source ~= "popup" then RefreshPopup() end
end)

ns.On("LOGIN", function()
    pop:ApplyGeometry()
    RefreshPopup()
end)
ns.On("SETTINGS_RESET", function(keys)
    -- "Window positions" puts the popup back too (its place is ours to keep)
    if keys.windows then DB().popup = nil end
    if keys.notes or keys.windows then
        popKey, popNote = nil, nil
        pop:ApplyGeometry()
        RefreshPopup()
    end
end)
Notes.module:Event("PLAYER_TARGET_CHANGED", function() RefreshPopup() end)
ns.On("THEME_CHANGED", function()
    if pop:IsShown() then
        local p = Player(popKey)
        if p and popNote then ShowPopNote(p) end
        pop:UpdateLock()
        RefreshPopup()
    end
end)
