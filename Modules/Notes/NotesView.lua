-- ---------------------------------------------------------------------------
-- Notes page, shared part: the page frame with its tabs, and MakeView, one tree +
-- editor view (used for the notebook and for the players).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, UI, App, Text, Skin, Muted, IsBlank = ns.L, ns.T, ns.UI, ns.App, ns.Text, ns.Skin, ns.Muted, ns.IsBlank
local Notes = ns.Notes
local Stamp, Untitled, RemoveNote, IsSticky, Discard = Notes.Stamp, Notes.Untitled, Notes.RemoveNote, Notes.IsSticky, Notes.Discard
local Touch, Changed = Notes.Touch, Notes.Changed

-- ---------------------------------------------------------------------------
-- Notes page: Notebook (groups) and Players, both as a tree + editor
-- ---------------------------------------------------------------------------
local page = CreateFrame("Frame", "BeautifulRogueNotes", UIParent)
page:SetSize(App.CONTENT_W, App.CONTENT_H)
page:Hide()
local function Status(msg, alert) App.Status(msg, alert) end

local subpages, views = {}, {}
local tabs = UI.Tabs(page, { { "book", L["Notebook"] }, { "players", L["Players"] }, { "stickies", L["Sticky notes"] } },
    0, 0, 120, function(key) Notes.ShowSub(key) end)

local TREE_W, ROW_H, BAR_H = 220, 22, 30

-- one tree + editor view. cfg:
--   headers()           ordered list of { ref = container, label = text, color = rgb }
--   headerPanel(view)   builds the right-hand panel for a selected header
--   noteMenu, noteMenuLabel   optional "move to" dropdown for notes
--   afterRemove, afterRender  optional hooks
--   barH                      optional height of the bottom bar (default BAR_H)
local function MakeView(key, cfg)
    local barH = cfg.barH or BAR_H
    local sub = CreateFrame("Frame", nil, page)
    sub:SetPoint("TOPLEFT", 0, -32)
    sub:SetPoint("BOTTOMRIGHT", 0, 0)
    sub:Hide()
    subpages[key] = sub
    local v = { page = sub, items = {}, rows = {}, scroll = 0, cfg = cfg }
    views[key] = v

    -- tree ------------------------------------------------------------------
    local tree = CreateFrame("Frame", nil, sub)
    tree:SetPoint("TOPLEFT")
    tree:SetPoint("BOTTOMLEFT", 0, barH)
    tree:SetWidth(TREE_W)
    Skin(tree, T.panel)
    tree:EnableMouseWheel(true)
    tree.thumb = tree:CreateTexture(nil, "OVERLAY")
    tree.thumb:SetWidth(2)
    ns.Color(tree.thumb, T.accent, 0.6)
    tree.empty = UI.Hint(tree, cfg.emptyText)
    tree.empty:SetPoint("TOPLEFT", 10, -10)
    tree.empty:SetPoint("TOPRIGHT", -10, -10)
    v.tree = tree

    -- editor for a selected note ---------------------------------------------
    local ed = CreateFrame("Frame", nil, sub)
    ed:SetPoint("TOPLEFT", TREE_W + 12, 0)
    ed:SetPoint("BOTTOMRIGHT", 0, barH)
    ed.title = UI.LineEdit(ed, 14)
    ed.title:SetPoint("TOPLEFT")
    ed.title:SetPoint("TOPRIGHT", -164, 0)
    ed.title:SetHeight(24)
    ed.del = UI.ConfirmButton(ed, 72, L["Delete"], function()
        local note, c = v.sel, v.selC
        if not (note and c) then return end
        local i = RemoveNote(c, note)
        if cfg.afterRemove then cfg.afterRemove(v, c) end
        Status(L["Deleted \"%s\"."]:format(Untitled(note)))
        v.sel = c.notes[math.min(i or 1, #c.notes)] or c
        v.selC = (v.sel ~= c) and c or nil
        Changed(key)
        v:Refresh()
    end, 24)
    ed.del:SetPoint("TOPRIGHT")
    ed.sticky = UI.Button(ed, 80, L["Sticky"], function()
        if not (v.sel and v.selC) then return end
        ns.Stickies.Toggle(v.sel)
        ed.sticky:SetAccent(IsSticky(v.sel))
    end, 24)
    ed.sticky:SetPoint("RIGHT", ed.del, "LEFT", -6, 0)
    UI.Tooltip(ed.sticky, { L["Sticky note"], L["Puts this note on the screen. Drag its colored bar to move it, its corner to resize it."] })
    ed.meta = Text(ed, 10)
    ed.meta:SetPoint("TOPLEFT", 2, -30)
    ed.meta:SetPoint("TOPRIGHT", -124, -30)
    ed.meta:SetJustifyH("LEFT")
    ed.meta:SetWordWrap(false)
    if cfg.noteMenu then
        ed.move = UI.Button(ed, 120, "", function(self) cfg.noteMenu(v, self) end, 18)
        ed.move:SetPoint("TOPRIGHT", 0, -28)
    end
    ed.body = ns.NoteEditor.Create(ed, { skin = true, toolbar = true })
    ed.body:SetPoint("TOPLEFT", 0, -50)
    ed.body:SetPoint("BOTTOMRIGHT")
    v.ed = ed

    -- panel for a selected group / player ------------------------------------
    v.head = CreateFrame("Frame", nil, sub)
    v.head:SetPoint("TOPLEFT", TREE_W + 12, 0)
    v.head:SetPoint("BOTTOMRIGHT", 0, barH)
    cfg.headerPanel(v)

    local function MetaText(note)
        return Muted(L["Created %s   ·   Updated %s"]:format(Stamp(note.created), Stamp(note.updated)))
    end

    ed.title:SetScript("OnTextChanged", function(self, userInput)
        local note = v.sel
        if not (userInput and v.selC and note) then return end
        note.title, note.titled = self:GetText(), true
        Touch(note)
        ed.meta:SetText(MetaText(note))
        v:Render()
        Changed(key)
    end)
    ed.body.onChange = function(text)
        local note = v.sel
        if not (v.selC and note) then return end
        note.text = text
        Touch(note)
        ed.meta:SetText(MetaText(note))
        v:Render()
        Changed(key)
    end

    -- rows ------------------------------------------------------------------
    local function GetRow(i)
        local r = v.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, tree)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -4, -(i - 1) * ROW_H)
        r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.sel:SetAllPoints()
        ns.Color(r.sel, T.accentSoft)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetPoint("TOPLEFT")
        r.mark:SetPoint("BOTTOMLEFT")
        r.mark:SetWidth(2)
        ns.Color(r.mark, T.accent)
        r.toggle = CreateFrame("Button", nil, r)
        r.toggle:SetSize(18, ROW_H)
        r.toggle:SetPoint("LEFT", 2, 0)
        r.toggle.arrow = UI.Arrow(r.toggle, 11)
        r.toggle.arrow:SetPoint("CENTER")
        r.toggle:SetScript("OnClick", function()
            local it = r.item
            if it and it.kind == "header" then
                it.h.ref.collapsed = not it.h.ref.collapsed or nil
                v:Refresh()
            end
        end)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(8, 8)
        r.dot:SetPoint("LEFT", 22, 0)
        r.text = Text(r, 12)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r.meta = Text(r, 10)
        r.meta:SetPoint("RIGHT", -6, 0)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        ns.Color(r.hl, T.hover)
        r:SetScript("OnClick", function(self)
            local it = self.item
            if not it then return end
            if it.kind == "header" then
                it.h.ref.collapsed = nil
                v:Select(it.h.ref, nil)
            else
                v:Select(it.note, it.h.ref)
            end
        end)
        UI.Tooltip(r, function(self)
            local it = self.item
            if not (it and it.kind == "note") then return end
            local lines = { Untitled(it.note) }
            if not IsBlank(it.note.text) then lines[#lines + 1] = it.note.text end
            lines[#lines + 1] = L["Created: %s"]:format(Stamp(it.note.created))
            lines[#lines + 1] = L["Updated: %s"]:format(Stamp(it.note.updated))
            return lines
        end)
        v.rows[i] = r
        return r
    end

    function v:Rebuild()
        wipe(self.items)
        for _, h in ipairs(cfg.headers()) do
            self.items[#self.items + 1] = { kind = "header", h = h }
            if not h.ref.collapsed then
                for _, n in ipairs(h.ref.notes) do
                    self.items[#self.items + 1] = { kind = "note", h = h, note = n }
                end
            end
        end
    end

    function v:Render()
        local visible = math.max(1, math.floor((tree:GetHeight() or 0) / ROW_H))
        local maxScroll = math.max(0, #self.items - visible)
        self.scroll = math.max(0, math.min(self.scroll, maxScroll))
        for i = 1, math.max(visible, #self.rows) do
            local it = (i <= visible) and self.items[self.scroll + i] or nil
            if it then
                local r = GetRow(i)
                r.item = it
                local isSel
                r.text:ClearAllPoints()
                if it.kind == "header" then
                    local c = it.h.ref
                    isSel = self.sel == c
                    r.toggle:Show()
                    r.toggle.arrow:Point(c.collapsed and "right" or "down")
                    r.dot:Show()
                    r.dot:SetColorTexture(unpack(it.h.color))
                    r.text:SetPoint("LEFT", 36, 0)
                    r.text:SetPoint("RIGHT", -28, 0)
                    r.text:SetText(it.h.label)
                    r.meta:SetText(Muted(tostring(#c.notes)))
                else
                    isSel = self.sel == it.note
                    r.toggle:Hide()
                    r.dot:Hide()
                    r.text:SetPoint("LEFT", 36, 0)
                    r.text:SetPoint("RIGHT", -50, 0)
                    r.text:SetText((it.note.title and it.note.title ~= "") and it.note.title or Muted(L["(untitled)"]))
                    r.meta:SetText(Muted(Stamp(it.note.updated, true)))
                end
                r.sel:SetShown(isSel)
                r.mark:SetShown(isSel)
                r:Show()
            elseif self.rows[i] then
                self.rows[i]:Hide()
            end
        end
        tree.empty:SetShown(#self.items == 0)
        if maxScroll > 0 then
            local trackH = tree:GetHeight()
            local thumbH = math.max(16, trackH * visible / #self.items)
            tree.thumb:ClearAllPoints()
            tree.thumb:SetPoint("TOPRIGHT", tree, "TOPRIGHT", -1, -(trackH - thumbH) * self.scroll / maxScroll)
            tree.thumb:SetHeight(thumbH)
            tree.thumb:Show()
        else
            tree.thumb:Hide()
        end
        if cfg.afterRender then cfg.afterRender(self) end
    end

    -- the right side follows the selection: note editor or header panel
    function v:ShowSelection()
        local note, c = self.sel, self.selC
        if note and c then
            self.head:Hide()
            ed:Show()
            if not ed.title:HasFocus() then ed.title:SetText(note.title or "") end
            ed.meta:SetText(MetaText(note))
            if not ed.body.edit:HasFocus() then ed.body:SetValue(note.text) end
            if ed.move and cfg.noteMenuLabel then ed.move.text:SetText(cfg.noteMenuLabel(self)) end
            ed.sticky:SetAccent(IsSticky(note))
        else
            ed:Hide()
            if self.sel then
                self.head:Show()
                self.head:Fill(self.sel)
            else
                self.head:Hide()
            end
        end
    end

    function v:Select(ref, container)
        -- leaving a fresh, unwritten note: drop it
        local old, oldC = self.sel, self.selC
        if oldC and old ~= ref and Discard(oldC, old) then
            if cfg.afterRemove then cfg.afterRemove(self, oldC) end
            Changed(key)
        end
        ed.title:ClearFocus()
        ed.body.edit:ClearFocus()
        self.sel, self.selC = ref, container
        self:Rebuild()
        for i, it in ipairs(self.items) do
            if (it.kind == "note" and it.note == ref) or (it.kind == "header" and it.h.ref == ref) then
                local visible = math.max(1, math.floor((tree:GetHeight() or 0) / ROW_H))
                if i <= self.scroll then self.scroll = i - 1 elseif i > self.scroll + visible then self.scroll = i - visible end
                break
            end
        end
        self:Render()
        self:ShowSelection()
    end

    -- redraw after outside changes; a selection that vanished falls back
    function v:Refresh()
        local exists = false
        for _, h in ipairs(cfg.headers()) do
            if h.ref == self.sel then exists = true end
            if self.selC == h.ref and ns.IndexOf(h.ref.notes, self.sel) then exists = true end
        end
        if not exists then self.sel, self.selC = nil, nil end
        self:Rebuild()
        self:Render()
        self:ShowSelection()
    end

    tree:SetScript("OnMouseWheel", function(_, delta)
        v.scroll = v.scroll - delta
        v:Render()
    end)
    tree:SetScript("OnSizeChanged", function() if sub:IsVisible() then v:Render() end end)
    return v
end

local function HeadLabel(parent, text, y) return UI.Label(parent, text, 2, y) end

local function Plural(n, one, many) return (n == 1 and one or many):format(n) end

-- the page and the tree + editor view, for the notebook / players views and the page code
Notes.page, Notes.subpages, Notes.views, Notes.tabs = page, subpages, views, tabs
Notes.MakeView, Notes.HeadLabel, Notes.Plural, Notes.TREE_W = MakeView, HeadLabel, Plural, TREE_W
