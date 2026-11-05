-- ---------------------------------------------------------------------------
-- Sticky notes: any note (notebook or player) can sit on the screen as its
-- own small window. The bar in the note's color moves it, the corner resizes
-- it; the bar's buttons fold it to the bar, lock it and close it. Position,
-- size and the open state live on the note itself (note.sticky), so open
-- sticky notes come back after a reload.
-- Dropped at the edge of another sticky note, a note docks there: it takes
-- that note's width and height and moves with it (note.sticky.dock).
-- Split: Stickies.lua (windows, open/close), StickyDock.lua (docking and
-- snapping), StickySettings.lua (the settings tab); they share the public
-- ns.Stickies table.
-- The text shows formatted, a click switches to editing (ns.NoteEditor:
-- checkboxes, bullet and numbered lists, the same in every note).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T = ns.L, ns.T
local UI, Notes, NoteEditor = ns.UI, ns.Notes, ns.NoteEditor
local Text = ns.Text

local Stickies = {}
ns.Stickies = Stickies

local BAR_H, FOOT_H = 26, 24
local MIN_W, MIN_H = 160, 90
Stickies.BAR_H, Stickies.MIN_W, Stickies.MIN_H = BAR_H, MIN_W, MIN_H
local MEDIA = "Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\"
Stickies.DEFAULTS = { w = 240, h = 200, size = 12 }

function Stickies.Settings()
    local d = Notes.DB()
    d.sticky = d.sticky or {}
    local s = d.sticky
    for k, v in pairs(Stickies.DEFAULTS) do if s[k] == nil then s[k] = v end end
    return s
end

local function IsOpen(note) return note and note.sticky and note.sticky.open and true or false end
Stickies.IsOpen = IsOpen

-- line helpers live in the editor (kept here for older callers)
Stickies.ParseLine, Stickies.Progress, Stickies.ToggleLine = NoteEditor.ParseLine, NoteEditor.Progress, NoteEditor.ToggleLine

-- ---------------------------------------------------------------------------
-- Windows (pooled; one per open note)
-- ---------------------------------------------------------------------------
local frames, cascade = {}, 0
local byNote = {}
Stickies.byNote = byNote   -- open windows by note (read by the dock and settings parts)
local Render, SetEditing, ApplyGeometry

local function Geo(note)
    note.sticky = note.sticky or {}
    return note.sticky
end
Stickies.Geo = Geo

local function SaveGeometry(f)
    local l, t = f:GetLeft(), f:GetTop()
    if not (l and t and f.note) then return end
    if Stickies.HostOf(f) then return end   -- docked: the host decides
    local g = Geo(f.note)
    g.l, g.t, g.w = l, t, f:GetWidth()
    if not g.collapsed then g.h = f:GetHeight() end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
end

local function IconButton(parent, size, file, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(size - 6, size - 6)
    b.icon:SetPoint("CENTER")
    if file then b.icon:SetTexture(file) end
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.18)
    if tip then UI.Tooltip(b, tip, "ANCHOR_TOP") end
    return b
end

-- dark text on light note colors, white on dark ones
local function InkFor(c)
    local lum = 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
    return lum > 0.5 and { 0.07, 0.08, 0.10 } or { 1, 1, 1 }
end

-- all sticky notes sit on one layer: it steps aside in combat if wanted
local layer = Notes.Layer("stickies")

local function Create()
    local i = #frames + 1
    local f = CreateFrame("Frame", "BeautifulRogueSticky" .. i, layer)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, 1000, 1000) end
    ns.Skin(f, T.window, T.line)

    -- bar in the note's color: drag to move
    local bar = CreateFrame("Button", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAR_H)
    bar:RegisterForDrag("LeftButton")
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar:SetScript("OnDragStart", function()
        if Geo(f.note).locked then return end
        if Stickies.HostOf(f) then Stickies.Undock(f) end   -- pulled away: free again
        f:StartMoving()
        bar:SetScript("OnUpdate", function() Stickies.ShowSnap(f) end)
    end)
    bar:SetScript("OnDragStop", function()
        bar:SetScript("OnUpdate", nil)
        f:StopMovingOrSizing()
        Stickies.HideSnap()
        local x, side = Stickies.FindSnap(f)
        if x then Stickies.Dock(f, x, side) else SaveGeometry(f) end
    end)
    bar:SetScript("OnDoubleClick", function() Stickies.Fold(f) end)
    f.bar = bar

    f.menu = IconButton(bar, 22, nil, { L["More"] })
    f.menu:SetPoint("LEFT", 4, 0)
    f.menu.label = Text(f.menu, 14)
    f.menu.label:SetPoint("CENTER", 0, 0)
    f.menu.label:SetText("···")
    f.menu:SetScript("OnClick", function(self)
        local items = { { label = L["Open in the notes"], fn = function() Notes.Reveal(f.note) end } }
        if Stickies.HostOf(f) then
            items[#items + 1] = { label = L["Undock"], fn = function() Stickies.Undock(f) end }
        else
            items[#items + 1] = { label = L["Default size"], fn = function()
                local s, g = Stickies.Settings(), Geo(f.note)
                g.w, g.h, g.collapsed = s.w, s.h, nil
                ApplyGeometry(f)
                Render(f)
            end }
        end
        items[#items + 1] = { label = L["Close"], fn = function() Stickies.Close(f.note) end }
        UI.OpenMenu(self, items, { width = 170, point = "TOPLEFT", relPoint = "BOTTOMLEFT" })
    end)
    f.close = IconButton(bar, 22, nil, { L["Close"], L["The note stays in your notes."] })
    f.close:SetPoint("RIGHT", -4, 0)
    f.close.label = Text(f.close, 16)
    f.close.label:SetPoint("CENTER", 0, 1)
    f.close.label:SetText("×")
    f.close:SetScript("OnClick", function() Stickies.Close(f.note) end)
    f.lock = IconButton(bar, 22, nil, function()
        return { Geo(f.note).locked and L["Unlock: allow moving and resizing"] or L["Lock position and size"] }
    end)
    f.lock:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
    f.lock:SetScript("OnClick", function()
        local g = Geo(f.note)
        g.locked = not g.locked or nil
        Stickies.Paint(f)
    end)
    f.fold = IconButton(bar, 22, nil, { L["Fold to the bar"] })
    f.fold:SetPoint("RIGHT", f.lock, "LEFT", -2, 0)
    f.fold.arrow = UI.Arrow(f.fold, 12, "up")
    f.fold.arrow:SetPoint("CENTER")
    f.fold:SetScript("OnClick", function() Stickies.Fold(f) end)
    f.title = Text(bar, 12)
    f.title:SetPoint("LEFT", f.menu, "RIGHT", 4, 0)
    f.title:SetPoint("RIGHT", f.fold, "LEFT", -6, 0)
    f.title:SetJustifyH("CENTER")
    f.title:SetWordWrap(false)
    -- ink on a colored bar: no shadow
    for _, fs in ipairs({ f.title, f.menu.label, f.close.label }) do
        fs.uerThemed = nil   -- keep it shadow-free in both modes
        fs:SetShadowOffset(0, 0)
    end

    -- the note: formatted, a click on it starts writing (ns.NoteEditor)
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 0, -BAR_H)
    body:SetPoint("BOTTOMRIGHT", 0, FOOT_H)
    f.body = body
    body.tint = body:CreateTexture(nil, "BACKGROUND")   -- a breath of the note's color
    body.tint:SetPoint("TOPLEFT", 0, 0)
    body.tint:SetPoint("BOTTOMRIGHT", 0, -FOOT_H)
    local ne = NoteEditor.Create(body, { size = Stickies.Settings().size })
    ne:SetPoint("TOPLEFT", 4, -2)
    ne:SetPoint("BOTTOMRIGHT", -4, 0)
    ne.canEdit = function() return f.note and not Geo(f.note).collapsed end
    ne.onEditing = function(on)
        f.editing = on or nil
        Stickies.Paint(f)
    end
    ne.onChange = function(text)
        if not f.note then return end
        f.note.text = text
        Notes.Touch(f.note)
        Stickies.Paint(f)
        Notes.Changed("sticky")
    end
    f.ne, f.rows, f.editor = ne, ne.rows, ne.area

    -- footer: checkbox and list buttons, progress, resize corner
    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(FOOT_H)
    f.foot = foot
    f.checkBtn, f.listBtn, f.numBtn = ne:ToolButtons(foot)
    f.checkBtn:SetPoint("LEFT", 6, 0)
    f.done = UI.Button(foot, 60, L["Done"], function() SetEditing(f, false) end, 18)
    f.done:SetPoint("LEFT", f.numBtn, "RIGHT", 6, 0)
    f.progress = Text(foot, 11)
    f.progress:SetPoint("RIGHT", -24, 0)
    ns.Color(f.progress, T.muted)
    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetSize(16, 16)
    f.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    f.grip:SetFrameLevel(f:GetFrameLevel() + 10)
    f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    f.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    f.grip:SetScript("OnMouseDown", function() if not Geo(f.note).locked then f:StartSizing("BOTTOMRIGHT") end end)
    f.grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SaveGeometry(f)
        Render(f)
    end)
    f:SetScript("OnSizeChanged", function()
        if not f.note then return end
        if not f.editing then Render(f) end
        Stickies.Relayout(f)   -- docked notes keep the same size
    end)
    -- snap preview: a bold accent line along the edge where the notes meet,
    -- on both notes, exactly as long as the edge (drawn above the content)
    f.snapBar = CreateFrame("Frame", nil, f)
    f.snapBar:SetAllPoints()
    f.snapBar:SetFrameLevel(f:GetFrameLevel() + 30)
    f.snapLine = f.snapBar:CreateTexture(nil, "OVERLAY")
    ns.Color(f.snapLine, T.accent)
    f.snapLine:Hide()

    frames[i] = f
    return f
end
function Stickies.Paint(f)
    local note = f.note
    if not note then return end
    local kind, c = Notes.Owner(note)
    local color = kind and Notes.Color(kind, c) or T.muted
    f.bar.bg:SetColorTexture(color[1], color[2], color[3], 1)
    f.body.tint:SetColorTexture(color[1], color[2], color[3], T.mode == "light" and 0.07 or 0.05)
    local ink = InkFor(color)
    f.title:SetTextColor(ink[1], ink[2], ink[3], 1)
    f.close.label:SetTextColor(ink[1], ink[2], ink[3], 1)
    f.menu.label:SetTextColor(ink[1], ink[2], ink[3], 1)
    f.fold.arrow:SetVertexColor(ink[1], ink[2], ink[3], 0.9)
    local g = Geo(note)
    f.lock.icon:SetTexture(MEDIA .. (g.locked and "Lock" or "Unlock"))
    f.lock.icon:SetVertexColor(ink[1], ink[2], ink[3], g.locked and 1 or 0.55)
    f.fold.arrow:Point(g.collapsed and "down" or "up")
    local title = Notes.Untitled(note)
    if kind == "p" then title = Notes.OwnerName(kind, c) .. " · " .. title end
    f.title:SetText(title)
    local done, total = Stickies.Progress(note.text)
    f.progress:SetText(total > 0 and ("%d/%d"):format(done, total) or "")
    f.grip:SetShown(not g.locked and not g.collapsed and not Stickies.HostOf(f))
    f.done:SetShown(f.editing and true or false)
end

ApplyGeometry = function(f)
    local g, s = Geo(f.note), Stickies.Settings()
    local host = Stickies.HostOf(f)
    if host then
        f.body:SetShown(not g.collapsed)
        f.foot:SetShown(not g.collapsed)
        if g.collapsed then f.ne:StopEditing() end
        Stickies.Relayout(host)   -- places f (and what hangs on it)
        return
    end
    f:ClearAllPoints()
    if not (g.l and g.t) then
        -- new on screen: a little cascade around the middle
        cascade = (cascade % 8) + 1
        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        g.l, g.t = w / 2 - (g.w or s.w) / 2 + cascade * 24 - 96, h / 2 + 120 - cascade * 24
    end
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.l, g.t)
    f:SetWidth(math.max(MIN_W, g.w or s.w))
    f:SetHeight(g.collapsed and BAR_H or math.max(MIN_H, g.h or s.h))
    f.body:SetShown(not g.collapsed)
    f.foot:SetShown(not g.collapsed)
    if g.collapsed then f.ne:StopEditing() end
    Stickies.Relayout(f)
end

-- the formatted text
Render = function(f)
    local note = f.note
    if not note then return end
    Stickies.Paint(f)
    f.ne.size = Stickies.Settings().size
    if not f.editing then f.ne:SetValue(note.text) end
end

SetEditing = function(f, on)
    if not f.note then return end
    f.ne:SetEditing(on)
end
Stickies.SetEditing = SetEditing
Stickies.Render, Stickies.ApplyGeometry = Render, ApplyGeometry
-- stepping aside in combat ends the writing (the text is saved as you type)
layer:SetScript("OnHide", function()
    for _, f in pairs(byNote) do if f.editing then SetEditing(f, false) end end
end)

function Stickies.Tick(f, i) f.ne:Tick(i) end
function Stickies.LineButton(f, kind) f.ne:LineButton(kind) end

function Stickies.Fold(f)
    local g = Geo(f.note)
    if f.editing then SetEditing(f, false) end
    if not g.collapsed then SaveGeometry(f) end
    g.collapsed = not g.collapsed or nil
    ApplyGeometry(f)
    if not g.collapsed then Render(f) else Stickies.Paint(f) end
end

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------
function Stickies.Frame(note) return byNote[note] end

function Stickies.Open(note)
    if not note then return end
    local f = byNote[note]
    if not f then
        for _, x in ipairs(frames) do
            if not x.note then f = x break end
        end
        f = f or Create()
        f.note = note
        byNote[note] = f
    end
    Geo(note).open = true
    f.ne:StopEditing()
    ApplyGeometry(f)
    f:Show()
    f:Raise()
    Render(f)
    -- notes that were docked here and are already open come back to it
    for _, x in ipairs(Stickies.DockedTo(f)) do ApplyGeometry(x) Stickies.Paint(x) end
    return f
end

function Stickies.Close(note)
    local f = byNote[note]
    if note and note.sticky then note.sticky.open = nil end
    if f then
        -- what hangs here stays where it is, as a free note
        for _, x in ipairs(Stickies.DockedTo(f)) do Stickies.Undock(x) end
        if Stickies.HostOf(f) then
            local l, t = f:GetLeft(), f:GetTop()
            if l and t then note.sticky.l, note.sticky.t = l, t end
        end
        if f.editing then SetEditing(f, false) end
        f:Hide()
        f.note = nil
        byNote[note] = nil
    end
    Notes.Changed("sticky")
end

function Stickies.Toggle(note)
    if IsOpen(note) then Stickies.Close(note) else Stickies.Open(note) end
end

function Stickies.CloseAll()
    local list = {}
    for note in pairs(byNote) do list[#list + 1] = note end
    for _, note in ipairs(list) do Stickies.Close(note) end
end

function Stickies.Count()
    local n = 0
    for _ in pairs(byNote) do n = n + 1 end
    return n
end

-- after any change: drop windows of deleted notes, show new text
local function Sync(source)
    if not next(byNote) then return end   -- nothing on the screen
    local alive = {}
    Notes.ForEach(function(note) alive[note] = true end)
    for note, f in pairs(byNote) do
        if not alive[note] then
            for _, x in ipairs(Stickies.DockedTo(f)) do Stickies.Undock(x) end
            f:Hide()
            f.note = nil
            byNote[note] = nil
        elseif source ~= "sticky" and not f.editing then
            Render(f)
        else
            Stickies.Paint(f)
        end
    end
end
Notes.OnChange(Sync)

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
ns.On("LOGIN", function()
    Notes.ForEach(function(note) if IsOpen(note) then Stickies.Open(note) end end)
    -- docks: every host is open now
    for _, f in pairs(byNote) do
        if Stickies.HostOf(f) then ApplyGeometry(f) Stickies.Paint(f) end
    end
end)
ns.On("THEME_CHANGED", function()
    for _, f in pairs(byNote) do if not f.editing then Render(f) end end
end)
ns.On("SETTINGS_RESET", function(keys)
    if keys.notes then Sync("reset") end
end)

