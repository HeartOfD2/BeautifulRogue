-- ---------------------------------------------------------------------------
-- UI building blocks in the addon's flat style: windows, tabs, buttons,
-- checkboxes, sliders, text boxes, a dropdown menu and a message box.
-- Split over Widgets.lua (basic controls), WidgetMenu.lua, WidgetColor.lua
-- and WidgetDialog.lua; all add to ns.UI.
-- No Blizzard templates are needed, so they look the same on every client.
-- ---------------------------------------------------------------------------
local _, ns = ...
local T, HEX = ns.T, ns.HEX
local Skin, Text, SetEdgeColor = ns.Skin, ns.Text, ns.SetEdgeColor
local UI = {}
ns.UI = UI

-- window with an accent strip on top, a title and a close cross.
-- opts.noEscape: ESC doesn't close it; opts.fixed: not draggable
function UI.Window(name, w, h, title, opts)
    opts = opts or {}
    local p = CreateFrame("Frame", name, UIParent)
    p:SetSize(w, h)
    p:SetFrameStrata(opts.strata or "DIALOG")
    p:EnableMouse(true)
    p:Hide()
    Skin(p, T.window)
    local strip = p:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(2)
    ns.Color(strip, T.accent)
    p.title = Text(p, 13)
    p.title:SetPoint("TOPLEFT", 14, -11)
    p.title:SetText(title or "")
    local close = CreateFrame("Button", nil, p)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -6, -7)
    close.text = Text(close, 16)
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("×")
    ns.Color(close.text, T.muted)
    close:SetScript("OnEnter", function(self) ns.SetColor(self.text, T.text) end)
    close:SetScript("OnLeave", function(self) ns.SetColor(self.text, T.muted) end)
    close:SetScript("OnClick", function() p:Hide() end)
    p.close = close
    if name and not opts.noEscape then table.insert(UISpecialFrames, name) end
    if not opts.fixed then
        p:SetMovable(true)
        p:SetClampedToScreen(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", function(self) self:StartMoving() end)
        p:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    end
    return p
end

-- one line of status text at the bottom of a window
function UI.StatusLine(parent, inset)
    local fs = Text(parent, 11)
    fs:SetPoint("BOTTOMLEFT", inset or 14, 10)
    fs:SetPoint("BOTTOMRIGHT", -(inset or 14), 10)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return function(msg, isAlert)
        fs:SetText(msg and ns.Colorize(isAlert and HEX.alert or HEX.muted, msg) or "")
    end, fs
end

-- small muted capital heading above a group of controls
function UI.Label(parent, text, x, y)
    local fs = Text(parent, 11)
    fs:SetPoint("TOPLEFT", x, y)
    ns.Color(fs, T.muted)
    fs:SetText(text)
    return fs
end

-- muted text that wraps at the given width
-- puts a font file on a FontString so that it shows at once: the client does not always
-- repaint an unchanged text after SetFont, and a face loaded for the first time may only
-- be ready a frame later, so the text is set fresh now and once more on the next frame.
-- SetFont's return value says nothing on this client, so it is not trusted.
function UI.ShowInFont(fs, path, size, flags, text)
    local function apply()
        if not (path and pcall(fs.SetFont, fs, path, size, flags or "")) then
            pcall(fs.SetFont, fs, ns.FONT_DEFAULT or STANDARD_TEXT_FONT, size, flags or "")
        end
        fs:SetText("")
        fs:SetText(text)
    end
    apply()
    if C_Timer and C_Timer.After then C_Timer.After(0, apply) end
end

function UI.Hint(parent, text, width)
    local fs = Text(parent, 11)
    fs:SetJustifyH("LEFT")
    ns.Color(fs, T.muted)
    if width then fs:SetWidth(width) end
    fs:SetText(text or "")
    return fs
end

-- dialogs open in the upper third of the screen
function UI.PlaceDialog(frame)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", 0, -math.floor((UIParent:GetHeight() or 768) * 0.14))
end

function UI.Button(parent, width, label, onClick, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 20)
    Skin(b, T.control)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    ns.Color(b.hl, T.hover)
    b.text = Text(b, 12)
    b.text:SetPoint("CENTER")
    b.text:SetText(label or "")
    if onClick then b:SetScript("OnClick", onClick) end
    function b:SetAccent(on)
        SetEdgeColor(self, on and T.accent or nil)
    end
    return b
end

-- attaches a simple tooltip (lines: first is the title)
function UI.Tooltip(frame, lines, anchor)
    frame:SetScript("OnEnter", function(self)
        local l = lines
        if type(l) == "function" then l = l(self) end   -- may return nothing: no tooltip
        if type(l) ~= "table" or #l == 0 then return end
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        for i, line in ipairs(l) do
            if i == 1 then
                GameTooltip:AddLine(line, 1, 1, 1)
            else
                GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
            end
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- two clicks within 3 seconds: the first one only arms the button
function UI.ConfirmButton(parent, width, label, onConfirm, height)
    local b
    local armedUntil = 0
    b = UI.Button(parent, width, label, function()
        if GetTime() > armedUntil then
            armedUntil = GetTime() + 3
            b.text:SetText(ns.Colorize(HEX.alert, ns.L["Click again"]))
            C_Timer.After(3.05, function()
                if GetTime() >= armedUntil then b.text:SetText(b.label) end
            end)
            return
        end
        armedUntil = 0
        b.text:SetText(b.label)
        onConfirm(b)
    end, height)
    b.label = label
    function b:SetLabel(s) self.label = s self.text:SetText(s) end
    return b
end

-- chevron texture: dir "right" | "down" | "left" | "up"
local ARROW_ROT = { right = 0, down = -90, left = 180, up = 90 }
function UI.Arrow(parent, size, dir)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetSize(size or 12, size or 12)
    t:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    t:SetDesaturated(true)
    ns.Paint(function() t:SetVertexColor(T.text[1], T.text[2], T.text[3], 0.85) end)
    function t:Point(d) self:SetRotation(math.rad(ARROW_ROT[d])) end
    t:Point(dir or "right")
    return t
end

-- the pointer's height in the units of `frame` (to compare with frame:GetTop())
function UI.CursorY(frame)
    local _, y = GetCursorPosition()
    return (y or 0) / (frame:GetEffectiveScale() or 1)
end

-- Drag handle (three short lines) that puts a list row in a new place: press it, drag up or
-- down, let go. The list keeps its own way of moving an item one step; the handle only asks
-- it step by step until the item sits where the pointer is.
--   spec.key()          the item this row shows (nil: an empty row, nothing to drag)
--   spec.indexOf(key)   its place in the list now (1 = first)
--   spec.targetAt()     the place under the pointer (1 .. count), nil when it cannot be told
--   spec.move(key, dir) one step up (-1) or down (1); redraws the list
--   spec.edge()         optional, called while dragging: scrolls a list that is longer than its view
--   spec.start/done()   optional, the list redraws to mark / unmark the item (UI.dragKey)
--   spec.ghost(key)     optional, text (and icon) of the floating copy that follows the pointer
-- While dragging, the row keeps its place as a dimmed slot (lists dim the row of UI.dragKey) and a
-- lifted copy of it (opaque card, accent edge, soft shadow) floats with the pointer.
UI.dragKey = nil   -- the item being dragged; lists paint its row highlighted
local dragger, dragging, ghost = CreateFrame("Frame"), nil, nil
dragger:Hide()

local function MakeGhost()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f.isDragGhost = true
    for i = 1, 3 do   -- a soft shadow: three growing plates, shifted down
        local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetPoint("TOPLEFT", -i * 2, i * 2 - 4)
        t:SetPoint("BOTTOMRIGHT", i * 2, -i * 2 - 4)
        t:SetColorTexture(0, 0, 0, 0.16)
    end
    ns.Skin(f, T.popover, T.accent)
    f.bar = f:CreateTexture(nil, "ARTWORK")   -- accent bar on the left edge
    f.bar:SetPoint("TOPLEFT")
    f.bar:SetPoint("BOTTOMLEFT")
    f.bar:SetWidth(3)
    ns.Color(f.bar, T.accent)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(18, 18)
    f.icon:SetPoint("LEFT", 12, 0)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.text = ns.Text(f, 12)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(false)
    f:Hide()
    return f
end

-- the copy sits over the row the grip belongs to, a little larger, and follows the pointer's height
local function MoveGhost()
    if not (ghost and dragging) then return end
    local row = dragging.row
    ghost:ClearAllPoints()
    ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", (row:GetLeft() or 0) - 4, UI.CursorY(row))
end

local function ShowGhost(g, key)
    ghost = ghost or MakeGhost()
    local row = g.row
    ghost:SetScale((row:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1))
    ghost:SetSize((row:GetWidth() or 200) + 8, (row:GetHeight() or 24) + 6)
    local text, icon
    if g.spec.ghost then text, icon = g.spec.ghost(key) end
    ghost.icon:SetShown(icon ~= nil)
    if icon then ghost.icon:SetTexture(icon) end
    ghost.text:SetText(text or "")
    ghost.text:ClearAllPoints()
    ghost.text:SetPoint("LEFT", icon and 36 or 14, 0)
    ghost.text:SetPoint("RIGHT", -12, 0)
    ghost:Show()
    MoveGhost()
end

local function StopDrag()
    local g = dragging
    if not g then return end
    dragging, UI.dragKey = nil, nil
    if ghost then ghost:Hide() end
    dragger:Hide()
    dragger:SetScript("OnUpdate", nil)
    g.hot = g:IsMouseOver()
    g:Paint()
    if g.spec.done then g.spec.done() end
end

local function DragStep()
    local g = dragging
    if not g then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then StopDrag() return end
    local spec, key = g.spec, UI.dragKey
    MoveGhost()
    if spec.edge then spec.edge() end
    local target = spec.targetAt()
    for _ = 1, 50 do
        local cur = target and spec.indexOf(key)
        if not cur or cur == target then break end
        local dir = target > cur and 1 or -1
        spec.move(key, dir)
        local now = spec.indexOf(key)
        -- stuck (an edge, or a neighbour in another group) or past the mark: stop
        if not now or now == cur or (target - now) * dir <= 0 then break end
    end
end

function UI.DragHandle(parent, spec)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(18, 18)
    g:EnableMouse(true)
    g.spec = spec
    g.lines = {}
    for i = 1, 3 do
        local t = g:CreateTexture(nil, "OVERLAY")
        t:SetSize(10, 2)
        t:SetPoint("CENTER", 0, (2 - i) * 4)
        g.lines[i] = t
    end
    function g:Paint()
        local c = self.hot and T.accent or T.muted
        for _, t in ipairs(self.lines) do t:SetColorTexture(c[1], c[2], c[3], 1) end
    end
    ns.Paint(function() g:Paint() end)
    UI.Tooltip(g, { ns.L["Drag to reorder"], ns.L["Hold the left mouse button and move up or down."] })
    g:HookScript("OnEnter", function() g.hot = true g:Paint() end)
    g:HookScript("OnLeave", function() g.hot = dragging == g g:Paint() end)
    g:SetScript("OnMouseDown", function(self, button)
        if button and button ~= "LeftButton" then return end
        local key = spec.key()
        if key == nil then return end
        dragging, UI.dragKey = self, key
        self.row = parent
        self.hot = true
        self:Paint()
        if spec.start then spec.start(key) end
        ShowGhost(self, key)
        dragger:SetScript("OnUpdate", DragStep)
        dragger:Show()
    end)
    g:SetScript("OnMouseUp", function(self) if dragging == self then StopDrag() end end)
    g:SetScript("OnHide", function(self) if dragging == self then StopDrag() end end)
    return g
end

-- thin scroll bar for a list that shows `view` of `total` items. The list calls
-- bar:Update(total, view, offset) whenever those change; a click or drag on the
-- bar calls onScroll(offset) (0-based, the first item shown). Hidden while all fit.
function UI.ScrollBar(parent, onScroll)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(6)
    bar:EnableMouse(true)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    ns.Color(bar.track, T.divider)
    bar.thumb = bar:CreateTexture(nil, "ARTWORK")
    bar.thumb:SetWidth(6)
    ns.Color(bar.thumb, T.muted)
    bar.total, bar.view, bar.offset = 0, 0, 0
    local function Range() return math.max(0, bar.total - bar.view) end
    function bar:Update(total, view, offset)
        self.total, self.view, self.offset = total, view, offset
        local range = Range()
        self:SetShown(range > 0)
        if range <= 0 then return end
        local h = self:GetHeight() or 100
        local thumbH = math.max(14, h * view / total)
        self.thumb:SetHeight(thumbH)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self, "TOP", 0, -(h - thumbH) * offset / range)
    end
    -- the pointer's place on the bar -> an offset
    local function OffsetAt()
        local _, y = GetCursorPosition()
        local top, h = bar:GetTop(), bar:GetHeight()
        if not (y and top and h and h > 0) then return bar.offset end
        local frac = (top - y / (UIParent:GetEffectiveScale() or 1)) / h
        return math.max(0, math.min(Range(), math.floor(frac * (Range() + 1))))
    end
    bar:SetScript("OnMouseDown", function(self)
        onScroll(OffsetAt())
        self:SetScript("OnUpdate", function(me)   -- only while the button is held
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then me:SetScript("OnUpdate", nil) return end
            onScroll(OffsetAt())
        end)
    end)
    bar:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    return bar
end

-- a scrolling column: area.child holds the content (its width follows the area), the wheel
-- and a thin bar scroll it when area:SetContentHeight(h) is taller than the area. Without
-- overflow nothing scrolls and the bar stays hidden.
local WHEEL_STEP = 24
-- pad: a margin inside the clipping edge, so the 1 px outlines our controls draw
-- just outside their frame are not cut off (sf.child is then the inset content frame)
function UI.ScrollArea(parent, pad)
    pad = pad or 0
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    local content = child
    if pad > 0 then
        content = CreateFrame("Frame", nil, child)
        content:SetPoint("TOPLEFT", pad, -pad)
        content:SetPoint("TOPRIGHT", -pad, -pad)
        content:SetHeight(1)
    end
    sf.child, sf.contentH = content, 1
    sf:EnableMouseWheel(true)
    sf.bar = UI.ScrollBar(parent, function(offset) sf:ScrollTo(offset) end)
    sf.bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0)
    sf.bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 0)
    local function Range() return math.max(0, sf.contentH - (sf:GetHeight() or 0)) end
    function sf:ScrollTo(px)
        px = math.max(0, math.min(Range(), px or 0))
        self:SetVerticalScroll(px)
        self.bar:Update(self.contentH, self:GetHeight() or 0, px)
    end
    function sf:SetContentHeight(h)
        h = h + 2 * pad
        self.contentH = h
        child:SetHeight(math.max(1, h))
        self:ScrollTo(self:GetVerticalScroll())   -- clamp to the new range
    end
    -- scrolls just far enough to show the band top..bottom (distances below the top of the content)
    function sf:EnsureVisible(top, bottom)
        local cur, view = self:GetVerticalScroll(), self:GetHeight() or 0
        if top < cur then
            self:ScrollTo(top)
        elseif bottom > cur + view then
            self:ScrollTo(bottom - view)
        end
    end
    sf:SetScript("OnMouseWheel", function(self, delta)
        self:ScrollTo(self:GetVerticalScroll() - delta * WHEEL_STEP)
    end)
    sf:SetScript("OnSizeChanged", function(self, w)
        child:SetWidth(math.max(1, w or 1))
        self:ScrollTo(self:GetVerticalScroll())
    end)
    return sf
end

-- flat checkbox: accent square when on
function UI.Check(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(14, 14)
    Skin(c, T.control, T.input)
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints()
    ns.Color(c.hl, T.hover)
    c.mark = c:CreateTexture(nil, "ARTWORK")
    c.mark:SetPoint("TOPLEFT", 3, -3)
    c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    ns.Color(c.mark, T.accent)
    function c:SetOn(on) self.on = on and true or false self.mark:SetShown(self.on) end
    function c:IsOn() return self.on end
    c:SetOn(false)
    return c
end

-- checkbox with a label; get/set read and write the setting
function UI.CheckRow(parent, label, get, set, width)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width or 260, 20)
    row.check = UI.Check(row)
    row.check:SetPoint("LEFT", 0, 0)
    row.label = Text(row, 12)
    row.label:SetPoint("LEFT", 22, 0)
    row.label:SetPoint("RIGHT", 0, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetText(label)
    local function Toggle()
        if row.disabled then return end
        set(not get())
        row:Refresh()
    end
    row:SetScript("OnClick", Toggle)
    row.check:SetScript("OnClick", Toggle)
    function row:Refresh() self.check:SetOn(get()) end
    function row:SetDisabled(d)
        self.disabled = d
        self:SetAlpha(d and 0.4 or 1)
    end
    return row
end

-- click/drag slider: thin track, accent fill, white thumb
function UI.Slider(parent, minV, maxV, step, get, set, width)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(width or 192, 12)
    s:EnableMouse(true)
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetPoint("LEFT")
    s.track:SetPoint("RIGHT")
    s.track:SetHeight(4)
    ns.Color(s.track, T.control)
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetPoint("LEFT")
    s.fill:SetHeight(4)
    ns.Color(s.fill, T.accent)
    s.thumb = s:CreateTexture(nil, "OVERLAY", nil, 1)
    s.thumb:SetSize(6, 12)
    ns.Color(s.thumb, T.text)
    s.thumbEdge = s:CreateTexture(nil, "OVERLAY", nil, 0)
    s.thumbEdge:SetPoint("TOPLEFT", s.thumb, -1, 1)
    s.thumbEdge:SetPoint("BOTTOMRIGHT", s.thumb, 1, -1)
    ns.Color(s.thumbEdge, T.line)
    local function FromCursor()
        local x = GetCursorPosition() / s:GetEffectiveScale()
        local left, w = s:GetLeft(), s:GetWidth()
        if not left or w <= 0 then return end
        local pct = math.max(0, math.min(1, (x - left) / w))
        set(math.floor((minV + (maxV - minV) * pct) / step + 0.5) * step)
        s:Refresh()
    end
    s:SetScript("OnMouseDown", function(self)
        if self.disabled then return end
        self.dragging = true
        FromCursor()
    end)
    s:SetScript("OnMouseUp", function(self) self.dragging = false end)
    s:SetScript("OnUpdate", function(self) if self.dragging then FromCursor() end end)
    function s:SetDisabled(d)
        self.disabled = d
        if d then self.dragging = false end
        self:SetAlpha(d and 0.4 or 1)
    end
    function s:Refresh()
        local pct = math.max(0, math.min(1, (get() - minV) / (maxV - minV)))
        self.fill:SetWidth(math.max(1, pct * self:GetWidth()))
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("CENTER", self, "LEFT", pct * self:GetWidth(), 0)
    end
    return s
end

-- single-line text box
function UI.LineEdit(parent, size, maxLetters)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetAutoFocus(false)
    e:SetFontObject(GameFontHighlight)
    ns.ThemeEdit(e)
    ns.ApplyFont(e, size or 13, "")
    ns.Color(e, T.text)
    e:SetTextInsets(8, 8, 0, 0)
    if maxLetters then e:SetMaxLetters(maxLetters) end
    Skin(e, T.control, T.input)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(self) SetEdgeColor(self, T.accent) end)
    e:SetScript("OnEditFocusLost", function(self) SetEdgeColor(self) end)
    return e
end

-- grey placeholder text inside an empty edit box
function UI.Placeholder(edit, text)
    edit.hint = Text(edit, 12)
    edit.hint:SetPoint("LEFT", 8, 0)
    ns.Color(edit.hint, T.muted)
    edit.hint:SetText(text)
    -- watched by a tiny helper frame instead of a script hook: a later
    -- SetScript("OnTextChanged") on the box would remove a hook in game
    local watch = CreateFrame("Frame", nil, edit)
    watch:SetScript("OnUpdate", function() edit.hint:SetShown(edit:GetText() == "") end)
end

-- multi-line editor in a scroll frame that follows its container's size
function UI.TextArea(parent, maxLetters)
    local box = CreateFrame("Frame", nil, parent)
    Skin(box, T.control, T.input)
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -6, 6)
    local e = CreateFrame("EditBox", nil, sf)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject(GameFontHighlight)
    ns.ThemeEdit(e)
    ns.ApplyFont(e, 13, "")
    ns.Color(e, T.text)
    if maxLetters then e:SetMaxLetters(maxLetters) end
    e:SetWidth(100)
    e:SetHeight(50)
    sf:SetScrollChild(e)
    sf:SetScript("OnSizeChanged", function(_, w, h)
        e:SetWidth(math.max(10, w))
        e:SetHeight(math.max(10, h))
    end)
    sf:EnableMouse(true)
    sf:SetScript("OnMouseDown", function() e:SetFocus() end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 16)))
    end)
    -- keep the cursor in view while typing
    e:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local top, view, cy = sf:GetVerticalScroll(), sf:GetHeight(), -y
        if cy < top then
            sf:SetVerticalScroll(cy)
        elseif cy + h > top + view then
            sf:SetVerticalScroll(cy + h - view)
        end
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function() SetEdgeColor(box, T.accent) end)
    e:SetScript("OnEditFocusLost", function() SetEdgeColor(box) end)
    box.edit, box.scroll = e, sf
    -- programmatic text: no "user input" flag, back to the top
    function box:SetValue(text)
        e:SetText(text or "")
        e:SetCursorPosition(0)
        sf:SetVerticalScroll(0)
    end
    return box
end

-- tab row: tabs = { { key, label }, ... }; onSelect(key)
function UI.Tabs(parent, tabs, x, y, width, onSelect)
    local row = { buttons = {} }
    for i, t in ipairs(tabs) do
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(width, 22)
        b:SetPoint("TOPLEFT", x + (i - 1) * (width + 4), y)
        b.text = Text(b, 12)
        b.text:SetPoint("CENTER")
        b.text:SetText(t[2])
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetPoint("BOTTOMLEFT")
        b.line:SetPoint("BOTTOMRIGHT")
        b.line:SetHeight(2)
        ns.Color(b.line, T.accent)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        ns.Color(b.hl, T.hover)
        b.key = t[1]
        b:SetScript("OnClick", function() onSelect(t[1]) end)
        row.buttons[t[1]] = b
    end
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", x, y - 22)
    line:SetPoint("TOPRIGHT", -x, y - 22)
    line:SetHeight(1)
    ns.Color(line, T.divider)
    function row:Select(key)
        for k, b in pairs(self.buttons) do
            b.text:SetAlpha(k == key and 1 or 0.55)
            b.line:SetShown(k == key)
        end
    end
    return row
end


-- ---------------------------------------------------------------------------
-- Segmented control: a row of buttons, the active one in the accent color.
-- items = { { value, label }, ... }
-- ---------------------------------------------------------------------------
function UI.Segmented(parent, items, get, set, width)
    local seg = CreateFrame("Frame", nil, parent)
    seg:SetSize(width, 22)
    seg.buttons = {}
    -- button widths follow the measured label width, so a long label is not cut off:
    -- every button gets its label plus padding, the rest of the row is shared out evenly
    local room = width - (#items - 1) * 4
    local need, sum = {}, 0
    for i, it in ipairs(items) do
        local b = UI.Button(seg, 10, it[2], function()
            set(it[1])
            seg:Refresh()
        end, 22)
        b.value = it[1]
        seg.buttons[i] = b
        local tw = b.text:GetStringWidth() or 0
        if tw <= 0 then tw = #it[2] * 7 end   -- no font metrics yet
        need[i] = tw + 16
        sum = sum + need[i]
    end
    local x = 0
    for i, b in ipairs(seg.buttons) do
        local w
        if sum <= room then
            w = need[i] + (room - sum) / #items
        else
            w = room * need[i] / sum   -- too narrow anyway: shrink alike
        end
        b:SetWidth(w)
        b:SetPoint("TOPLEFT", x, 0)
        x = x + w + 4
    end
    function seg:Refresh()
        local cur = get()
        for _, b in ipairs(self.buttons) do
            local on = b.value == cur
            b:SetAccent(on)
            ns.SetColor(b.text, on and T.accent or T.text)
        end
    end
    return seg
end

-- listbox: shows the chosen entry, a click opens the list to pick another.
-- items = { { value, label, desc? }, ... } or a function returning that list
function UI.Dropdown(parent, items, get, set, width)
    local dd
    local function Items() return type(items) == "function" and items() or items end
    dd = UI.Button(parent, width, "", function()
        local list = {}
        local cur = get()
        for _, it in ipairs(Items()) do
            list[#list + 1] = { label = it[2], desc = it[3], checked = it[1] == cur, font = it.font,
                fn = function() set(it[1]) dd:Refresh() end }
        end
        UI.OpenMenu(dd, list, { width = math.max(width, 190), point = "TOPLEFT", relPoint = "BOTTOMLEFT" })
    end, 22)
    dd.items = items
    dd.text:ClearAllPoints()
    dd.text:SetPoint("LEFT", 10, 0)
    dd.text:SetPoint("RIGHT", -24, 0)
    dd.text:SetJustifyH("LEFT")
    dd.text:SetWordWrap(false)
    dd.arrow = UI.Arrow(dd, 12, "down")
    dd.arrow:SetPoint("RIGHT", -6, 0)
    function dd:Refresh()
        local cur, list = get(), Items()
        for _, it in ipairs(list) do
            if it[1] == cur then self.text:SetText(it[2]) return end
        end
        self.text:SetText(list[1] and list[1][2] or "")
    end
    dd:Refresh()
    return dd
end

-- slider with its label on the left and the value on the right (height 34)
function UI.ValueSlider(parent, label, minV, maxV, step, get, set, width, fmt)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, 34)
    box.label = Text(box, 12)
    box.label:SetPoint("TOPLEFT", 0, 0)
    box.label:SetText(label)
    box.value = Text(box, 12)
    box.value:SetPoint("TOPRIGHT", 0, 0)
    ns.Color(box.value, T.muted)
    local function Show(v) box.value:SetText((fmt or "%d"):format(v)) end
    box.slider = UI.Slider(box, minV, maxV, step, get, function(v)
        set(v)
        Show(v)
    end, width)
    box.slider:SetPoint("TOPLEFT", 0, -18)
    function box:SetDisabled(d)
        self.slider:SetDisabled(d)
        self:SetAlpha(d and 0.4 or 1)
    end
    function box:Refresh()
        self.slider:Refresh()
        Show(get())
    end
    return box
end
