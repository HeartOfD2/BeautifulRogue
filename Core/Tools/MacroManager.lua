-- ---------------------------------------------------------------------------
-- Macro Manager: the page. Browse, edit, create and delete your WoW macros in
-- the addon's style: general and character macros, sorted into groups of your
-- own (general: account-wide, character: per character), drag onto a group
-- header or an action bar.
-- Parts: MacroIcons (icon picker), MacroTransfer (export / import),
-- MacroActions (header buttons); they use the interface near the end of this
-- file. The model (limits, helpers, registries) is Macros.lua.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX, UI = ns.L, ns.T, ns.HEX, ns.UI
local Text, Skin, SetEdgeColor = ns.Text, ns.Skin, ns.SetEdgeColor
local Macros = ns.Macros
local App = ns.App
local NAME_MAX, BODY_MAX, QUESTION_ICON, MAX_CHAR = Macros.NAME_MAX, Macros.BODY_MAX, Macros.QUESTION_ICON, Macros.MAX_CHAR
local IconPath, CharBase = Macros.IconPath, Macros.CharBase
local PAGE_W, PAGE_H = App.CONTENT_W, App.CONTENT_H
local LIST_W, ROW_H, ROWS = 220, 26, 14
local ED_X = LIST_W + 16
local ED_W = PAGE_W - ED_X


local data = {}   -- macros of the current tab: { index, name, icon, body }
local view = {}   -- what the list shows: group headers and macros
local state = { tab = "general", sel = nil, isNew = false, dirty = false, icon = QUESTION_ICON,
                iconChanged = false, scroll = 0, selGroup = nil, groupValue = nil }

-- groups of the current tab: { names, collapsed, of = { [macro name] = group } }
local Groups = ns.Transfer.Groups
local function MG() return Macros.GroupStore(state.tab ~= "general") end
local function GroupOf(m) return MG().of[m.name] end
local function GroupMembers(name)
    local out = {}
    for _, m in ipairs(data) do if Groups.IsIn(GroupOf(m), name) then out[#out + 1] = m end end
    return out
end
local function BuildView()
    local g = MG()
    view = ns.Transfer.Flatten(data, g.names, GroupOf, g.collapsed)
end

local function LoadMacros()
    wipe(data)
    local numGeneral, numChar = GetNumMacros()
    local first, count
    if state.tab == "general" then
        first, count = 1, numGeneral or 0
    else
        first, count = CharBase() + 1, numChar or 0
    end
    for i = first, first + count - 1 do
        local name, icon, body = GetMacroInfo(i)
        if name then data[#data + 1] = { index = i, name = name, icon = icon, body = body or "" } end
    end
end

-- ---------------------------------------------------------------------------
-- Page (built at load, moved into the app window the first time it opens)
-- ---------------------------------------------------------------------------
local mm = CreateFrame("Frame", "BeautifulRogueMacroManager", UIParent)
mm:SetSize(PAGE_W, PAGE_H)
mm:Hide()
Macros.page = mm
local function Status(msg, isAlert) App.Status(msg, isAlert) end
Macros.Status = Status

local function MakeEdit(parent, multi)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetAutoFocus(false)
    e:SetFontObject(GameFontHighlight)
    ns.ThemeEdit(e)
    ns.ApplyFont(e, 13, "")
    ns.Color(e, T.text)
    if multi then e:SetMultiLine(true) end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

local SetTab
local tabs = UI.Tabs(mm, { { "general", L["General"] }, { "character", L["Character"] } }, 0, 0, 104,
    function(key) SetTab(key) end)

local function UpdateTabs()
    local numGeneral, numChar = GetNumMacros()
    tabs.buttons.general.text:SetText(("%s  %s"):format(L["General"],
        ns.Muted(("%d/%d"):format(numGeneral or 0, CharBase()))))
    tabs.buttons.character.text:SetText(("%s  %s"):format(L["Character"],
        ns.Muted(("%d/%d"):format(numChar or 0, MAX_CHAR))))
    tabs:Select(state.tab)
end

-- ---------------------------------------------------------------------------
-- Macro list (ROWS row buttons, the mouse wheel scrolls the data)
-- ---------------------------------------------------------------------------
local list = CreateFrame("Frame", nil, mm)
list:SetPoint("TOPLEFT", 0, -32)
list:SetSize(LIST_W, ROW_H * ROWS)
Skin(list, T.panel)
list:EnableMouseWheel(true)
list.empty = Text(list, 12)
list.empty:SetPoint("CENTER")
ns.Color(list.empty, T.muted)
list.empty:SetText(L["No macros here yet"])
list.thumb = list:CreateTexture(nil, "OVERLAY")
list.thumb:SetWidth(2)
ns.Color(list.thumb, T.accent, 0.6)

local rows = {}
local Select, RenderList, RevealSelection, MoveMacro, DropOnGroup
local draggedIndex   -- the macro dragged out of the list, for a group header to take

for i = 1, ROWS do
    local r = CreateFrame("Button", nil, list)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetSize(LIST_W, ROW_H)
    r:RegisterForDrag("LeftButton")
    r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.sel:SetAllPoints()
    ns.Color(r.sel, T.accentSoft)
    r.mark = r:CreateTexture(nil, "ARTWORK", nil, 2)
    r.mark:SetPoint("TOPLEFT")
    r.mark:SetPoint("BOTTOMLEFT")
    r.mark:SetWidth(2)
    ns.Color(r.mark, T.accent)
    r.iconEdge = r:CreateTexture(nil, "ARTWORK")
    r.iconEdge:SetSize(22, 22)
    r.iconEdge:SetPoint("CENTER", r, "LEFT", 18, 0)
    ns.Color(r.iconEdge, T.line)
    r.icon = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("CENTER", r.iconEdge)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = Text(r, 12)
    r.text:SetPoint("LEFT", 36, 0)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.arrow = UI.Arrow(r, 11, "down")
    r.arrow:SetPoint("LEFT", 12, 0)
    r.arrow:Hide()
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    ns.Color(r.hl, T.hover)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
        local h = self.header
        if h then
            -- a macro still on the cursor lands here instead of folding the group
            if button == "LeftButton" and DropOnGroup(h.group) then return end
            if button == "RightButton" then
                Groups.Menu(MG(), h, self, {
                    members = GroupMembers,
                    setGroup = function(m, name) MG().of[m.name] = Groups.Stored(name) end,
                    changed = function()
                        if state.selGroup and not Groups.Has(MG(), state.selGroup) then state.selGroup = nil end
                        if state.sel then Select(state.sel) else RenderList() end
                    end,
                })
                return
            end
            -- a click folds the group and makes it the one new macros go into
            local c = MG().collapsed
            c[h.group] = not c[h.group] or nil
            state.selGroup = h.group
            RenderList()
            return
        end
        if self.macro and button == "RightButton" then
            local name = self.macro.name
            UI.OpenMenu(self, {
                { label = name, isTitle = true },
                { label = state.tab == "general" and L["Move to Character"] or L["Move to General"],
                  fn = function() MoveMacro(name) end },
            }, { width = 180, point = "TOPLEFT", relPoint = "BOTTOMLEFT" })
            return
        end
        if self.macro then
            state.selGroup = nil   -- a macro picked: export starts from it, not the group
            Select(self.macro.index)
        end
    end)
    r:SetScript("OnDragStart", function(self)
        if self.macro then
            draggedIndex = self.macro.index
            PickupMacro(draggedIndex)
        end
    end)
    r:SetScript("OnReceiveDrag", function(self) if self.header then DropOnGroup(self.header.group) end end)
    r:SetScript("OnEnter", function(self)
        local m = self.macro
        if not m then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(m.name, 1, 1, 1)
        GameTooltip:AddLine(m.body, 0.8, 0.8, 0.8, true)
        if ns.Templates and ns.Templates.Find(m.name) then
            GameTooltip:AddLine(L["From a template of the same name: Refresh on the templates page writes it anew."], T.accent[1], T.accent[2], T.accent[3], true)
        end
        GameTooltip:AddLine(L["Drag onto a group or an action bar"], T.muted[1], T.muted[2], T.muted[3])
        GameTooltip:AddLine(state.tab == "general" and L["Right-click: move to Character"] or L["Right-click: move to General"],
            T.muted[1], T.muted[2], T.muted[3])
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
end

RenderList = function()
    BuildView()
    local maxScroll = math.max(0, #view - ROWS)
    state.scroll = math.max(0, math.min(state.scroll, maxScroll))
    local collapsed = MG().collapsed
    for i, r in ipairs(rows) do
        local m = view[state.scroll + i]
        r.macro = (m and not m.isHeader) and m or nil
        r.header = (m and m.isHeader) and m or nil
        if m and m.isHeader then
            r.icon:Hide()
            r.iconEdge:Hide()
            r.arrow:Show()
            r.arrow:Point(collapsed[m.group] and "right" or "down")
            r.text:SetText(ns.Colorize(HEX.accent, m.group) .. "  " .. ns.Muted(tostring(#m.members)))
            local on = state.selGroup == m.group
            r.sel:SetShown(on)
            r.mark:SetShown(on)
            r:Show()
        elseif m then
            r.icon:Show()
            r.iconEdge:Show()
            r.arrow:Hide()
            r.icon:SetTexture(IconPath(m.icon) or QUESTION_ICON)
            r.text:SetText(m.name)
            -- made from a template: a 2 px accent frame (Refresh keeps it up to date)
            local fromTemplate = ns.Templates and ns.Templates.Find(m.name) and true or false
            ns.SetColor(r.iconEdge, fromTemplate and T.mark or T.line)
            r.iconEdge:SetSize(fromTemplate and 24 or 22, fromTemplate and 24 or 22)
            r.fromTemplate = fromTemplate
            local on = m.index == state.sel
            r.sel:SetShown(on)
            r.mark:SetShown(on)
            r:Show()
        else
            r:Hide()
        end
    end
    list.empty:SetShown(#view == 0 and not state.isNew)
    if maxScroll > 0 then
        local trackH = ROW_H * ROWS
        local thumbH = math.max(16, trackH * ROWS / #view)
        list.thumb:ClearAllPoints()
        list.thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -(trackH - thumbH) * state.scroll / maxScroll)
        list.thumb:SetHeight(thumbH)
        list.thumb:Show()
    else
        list.thumb:Hide()
    end
end

list:SetScript("OnMouseWheel", function(_, delta)
    state.scroll = state.scroll - delta
    RenderList()
end)

-- ---------------------------------------------------------------------------
-- Editor: icon, name, text with a letter counter
-- ---------------------------------------------------------------------------
local iconBtn = CreateFrame("Button", nil, mm)
iconBtn:SetSize(36, 36)
iconBtn:SetPoint("TOPLEFT", ED_X, -32)
Skin(iconBtn, T.control, T.input)
iconBtn.icon = iconBtn:CreateTexture(nil, "ARTWORK")
iconBtn.icon:SetAllPoints()
iconBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
iconBtn.icon:SetTexture(QUESTION_ICON)
iconBtn.hl = iconBtn:CreateTexture(nil, "HIGHLIGHT")
iconBtn.hl:SetAllPoints()
iconBtn.hl:SetColorTexture(1, 1, 1, 0.15)
UI.Tooltip(iconBtn, { L["Choose icon"], L["The question mark follows #showtooltip."] })

UI.Label(mm, L["NAME"], ED_X + 46, -32)
local nameBox = MakeEdit(mm)
nameBox:SetPoint("TOPLEFT", ED_X + 46, -46)
nameBox:SetSize(ED_W - 46 - 158, 22)
nameBox:SetMaxLetters(NAME_MAX)
nameBox:SetTextInsets(6, 6, 0, 0)
Skin(nameBox, T.control, T.input)

UI.Label(mm, L["GROUP"], PAGE_W - 150, -32)
local groupDD = UI.Dropdown(mm, function()
    local items = { { false, Groups.DEFAULT } }
    for _, n in ipairs(MG().names) do items[#items + 1] = { n, n } end
    return items
end, function() return state.groupValue or false end, function(v)
    state.groupValue = v or nil
    -- a saved macro moves at once; a new one on Save
    if state.sel and not state.isNew then
        local name = GetMacroInfo(state.sel)
        if name then MG().of[name] = state.groupValue end
        RevealSelection()   -- it moved to its group: keep it in view
        RenderList()
    end
end, 150)
groupDD:SetPoint("TOPLEFT", PAGE_W - 150, -46)

UI.Label(mm, L["MACRO TEXT"], ED_X, -80)
local counter = Text(mm, 11)
counter:SetPoint("TOPRIGHT", 0, -80)

local bodyBox = UI.TextArea(mm, BODY_MAX)
bodyBox:SetPoint("TOPLEFT", ED_X, -94)
bodyBox:SetPoint("BOTTOMRIGHT", 0, 32)
local body = bodyBox.edit
local MarkDirty, UpdateCounter
local spellBtn = ns.SpellSearch.Button(mm, body, function() MarkDirty() UpdateCounter() end, 110, 20)

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------
local Save, Delete, PickUp, NewMacro
local saveBtn = UI.Button(mm, 64, L["Save"], function() Save() end)
saveBtn:SetPoint("BOTTOMLEFT", ED_X, 0)
local delBtn = UI.Button(mm, 64, L["Delete"], function() Delete() end)
delBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
local pickBtn = UI.Button(mm, 72, L["Pick up"], function() PickUp() end)
pickBtn:SetPoint("LEFT", delBtn, "RIGHT", 6, 0)
spellBtn:SetPoint("LEFT", pickBtn, "RIGHT", 6, 0)
local LIST_BTN_W = (LIST_W - 12) / 3
local newBtn = UI.Button(mm, LIST_BTN_W, "+  " .. L["Macro"], function() NewMacro() end)
newBtn:SetPoint("BOTTOMLEFT", 0, 0)
local groupBtn = UI.Button(mm, LIST_BTN_W, "+  " .. L["Group"], function()
    Groups.AskNew(MG(), function(name)
        state.selGroup = name
        RenderList()
        Status(L["Group \"%s\" created. Right-click a group to rename or delete it."]:format(name))
    end)
end)
groupBtn:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)
UI.Tooltip(groupBtn, { L["New group"], L["Right-click a group to rename or delete it."] })
-- the macro assistant (MacroAssistant.lua, loaded later) builds macro text from parts
local assistBtn = UI.Button(mm, LIST_BTN_W, L["Assistant"], function() ns.MacroAssistant.Toggle() end)
assistBtn:SetPoint("LEFT", groupBtn, "RIGHT", 6, 0)
assistBtn:SetAccent(true)
UI.Tooltip(assistBtn, { L["Macro assistant"],
    L["Builds macro text from spells, target, conditions and extras, with a live preview."] })

local function UpdateButtons()
    local canWrite = not ns.InCombat()
    saveBtn:SetAlpha((canWrite and (state.dirty or state.isNew)) and 1 or 0.4)
    saveBtn:SetAccent(state.dirty)
    ns.SetColor(saveBtn.text, state.dirty and T.accent or T.text)
    delBtn:SetAlpha((canWrite and state.sel) and 1 or 0.4)
    pickBtn:SetAlpha(state.sel and 1 or 0.4)
    newBtn:SetAlpha(canWrite and 1 or 0.4)
end

UpdateCounter = function()
    local n = body:GetNumLetters()
    counter:SetText(ns.Colorize(n >= BODY_MAX and HEX.alert or HEX.muted, ("%d/%d"):format(n, BODY_MAX)))
end

MarkDirty = function()
    if not state.sel then state.isNew = true end
    state.dirty = true
    UpdateButtons()
end

local function SetEditor(name, icon, text)
    nameBox:SetText(name or "")
    bodyBox:SetValue(text or "")
    state.icon = icon or QUESTION_ICON
    state.iconChanged = false
    state.dirty = false
    iconBtn.icon:SetTexture(IconPath(state.icon))
    UpdateCounter()
    UpdateButtons()
end

RevealSelection = function()
    -- a macro inside a folded group: open the group first
    for _, m in ipairs(data) do
        if m.index == state.sel then
            local g = GroupOf(m)
            if g then MG().collapsed[g] = nil end
        end
    end
    BuildView()
    for pos, m in ipairs(view) do
        if not m.isHeader and m.index == state.sel then
            if pos <= state.scroll then
                state.scroll = pos - 1
            elseif pos > state.scroll + ROWS then
                state.scroll = pos - ROWS
            end
            return
        end
    end
end

-- Takes the macro dragged out of this list into a group. Only that one: a macro
-- picked up from an action bar would be lost from the bar, and the other list has
-- groups of its own. The macro itself doesn't change, so unsaved edits stay.
DropOnGroup = function(group)
    local kind, index = GetCursorInfo()
    if kind ~= "macro" or index ~= draggedIndex then return false end
    local macro
    for _, m in ipairs(data) do if m.index == index then macro = m break end end
    if not macro then return false end
    draggedIndex = nil
    ClearCursor()
    MG().of[macro.name] = Groups.Stored(group)
    if index == state.sel then
        state.groupValue = MG().of[macro.name]
        groupDD:Refresh()
        RevealSelection()
    end
    RenderList()
    Status(L["\"%s\" is now in the group \"%s\"."]:format(macro.name, group))
    return true
end

Select = function(index)
    local name, icon, text = GetMacroInfo(index)
    if not name then return end
    text = (text or ""):gsub("\n$", "")   -- the client adds one; it comes back on save anyway
    if state.dirty and index ~= state.sel then Status(L["Unsaved changes discarded."]) end
    state.sel, state.isNew = index, false
    state.groupValue = MG().of[name]
    groupDD:Refresh()
    SetEditor(name, icon, text)
    RevealSelection()
    RenderList()
end

local function ClearEditor()
    state.sel, state.isNew = nil, false
    state.groupValue = nil
    groupDD:Refresh()
    SetEditor("", QUESTION_ICON, "")
    RenderList()
end

local function SelectFirstOrClear()
    if data[1] then Select(data[1].index) else ClearEditor() end
end

SetTab = function(key)
    state.tab, state.scroll, state.selGroup = key, 0, nil
    LoadMacros()
    UpdateTabs()
    SelectFirstOrClear()
end

local IN_COMBAT = Macros.IN_COMBAT

NewMacro = function()
    if ns.InCombat() then Status(IN_COMBAT, true) return end
    state.sel, state.isNew = nil, true
    state.groupValue = Groups.Stored(state.selGroup)
    groupDD:Refresh()
    SetEditor("", QUESTION_ICON, "#showtooltip\n")
    UpdateButtons()
    RenderList()
    nameBox:SetFocus()
    Status(L["New macro: enter a name and text, then Save."])
end

Save = function()
    if ns.InCombat() then Status(IN_COMBAT, true) return end
    if not (state.dirty or state.isNew) then return end
    local name = ns.Trim(nameBox:GetText())
    local text = body:GetText() or ""
    if name == "" then
        Status(L["Enter a name first."], true)
        nameBox:SetFocus()
        return
    end
    -- one name per list; a general and a character macro may share it
    for _, m in ipairs(data) do
        if m.name == name and m.index ~= state.sel then
            Status(L["A macro named \"%s\" exists already."]:format(name), true)
            return
        end
    end
    local oldName = state.sel and not state.isNew and GetMacroInfo(state.sel)
    if state.isNew or not state.sel then
        local numGeneral, numChar = GetNumMacros()
        local perChar = state.tab == "character"
        if (perChar and (numChar or 0) >= MAX_CHAR) or (not perChar and (numGeneral or 0) >= CharBase()) then
            Status(L["This macro list is full."], true)
            return
        end
        local ok, idx = pcall(CreateMacro, name, state.icon, text, perChar)
        if not (ok and idx) and state.icon == QUESTION_ICON then
            ok, idx = pcall(CreateMacro, name, "INV_MISC_QUESTIONMARK", text, perChar)
        end
        if not (ok and idx) then
            Status(L["Couldn't create the macro."], true)
            return
        end
        state.dirty = false
        MG().of[name] = Groups.Stored(state.groupValue)
        LoadMacros()
        Select(idx)
        Status(L["Created \"%s\". Drag it onto an action bar."]:format(name))
    else
        -- nil keeps the icon: a "?" macro stays dynamic unless you picked a new one
        local ok, idx = pcall(EditMacro, state.sel, name, state.iconChanged and state.icon or nil, text)
        if not ok then
            Status(L["Couldn't save the macro."], true)
            return
        end
        state.dirty = false
        if oldName and oldName ~= name then   -- renamed: the group goes along
            local of = MG().of
            of[name], of[oldName] = of[oldName], nil
        end
        LoadMacros()
        Select(idx or GetMacroIndexByName(name) or state.sel)   -- edits can re-sort the list
        Status(L["Saved \"%s\"."]:format(name))
    end
    UpdateTabs()
end

-- two-step delete: the first click arms the button for 3 seconds
local deleteArmedUntil = 0
Delete = function()
    if not state.sel then return end
    if ns.InCombat() then Status(IN_COMBAT, true) return end
    if GetTime() > deleteArmedUntil then
        deleteArmedUntil = GetTime() + 3
        delBtn.text:SetText(ns.Colorize(HEX.alert, L["Sure?"]))
        C_Timer.After(3.05, function()
            if GetTime() >= deleteArmedUntil then delBtn.text:SetText(L["Delete"]) end
        end)
        return
    end
    deleteArmedUntil = 0
    delBtn.text:SetText(L["Delete"])
    local name = GetMacroInfo(state.sel)
    local pos = 1
    for p, m in ipairs(data) do if m.index == state.sel then pos = p break end end
    DeleteMacro(state.sel)
    if name then MG().of[name] = nil end
    state.dirty = false
    LoadMacros()
    local nextMacro = data[math.min(pos, #data)]
    if nextMacro then Select(nextMacro.index) else ClearEditor() end
    UpdateTabs()
    Status(L["Deleted \"%s\"."]:format(name or "?"))
end

-- the macro of the open tab with this name (the two lists may share a name)
local function IndexInTab(name)
    for _, m in ipairs(data) do if m.name == name then return m.index end end
end

-- to the other list; the tab stays open, so several can follow in a row
MoveMacro = function(name)
    if ns.InCombat() then Status(IN_COMBAT, true) return end
    local index = IndexInTab(name)
    if not index then return end
    local wasSelected = index == state.sel
    if wasSelected and state.dirty then
        Status(L["Save your changes first."], true)
        return
    end
    local selName = state.sel and not wasSelected and GetMacroInfo(state.sel)
    local pos = 1
    for p, m in ipairs(data) do if m.index == index then pos = p break end end
    local toChar = state.tab == "general"
    local newIndex, buttons = Macros.Move(index, toChar)
    if not newIndex then Status(buttons, true) return end   -- then it holds the reason
    LoadMacros()
    UpdateTabs()
    if wasSelected then
        local nextMacro = data[math.min(pos, #data)]
        if nextMacro then Select(nextMacro.index) else ClearEditor() end
    else
        -- the selection keeps its macro; unsaved edits stay in the editor
        if selName then state.sel = IndexInTab(selName) end
        RenderList()
    end
    local where = toChar and L["Character"] or L["General"]
    Status(buttons > 0 and L["Moved \"%s\" to %s; it stays on %d action buttons."]:format(name, where, buttons)
        or L["Moved \"%s\" to %s."]:format(name, where))
end

PickUp = function()
    if not state.sel then return end
    PickupMacro(state.sel)
    if state.dirty then
        Status(L["Picked up the saved version. Save first to include your edits."], true)
    else
        Status(L["Macro on the cursor: click an action button to place it."])
    end
end

nameBox:SetScript("OnTextChanged", function(_, userInput) if userInput then MarkDirty() end end)
nameBox:SetScript("OnTabPressed", function() body:SetFocus() end)
nameBox:SetScript("OnEnterPressed", function() body:SetFocus() end)
nameBox:SetScript("OnEditFocusGained", function(self) SetEdgeColor(self, T.accent) end)
nameBox:SetScript("OnEditFocusLost", function(self) SetEdgeColor(self) end)
body:SetScript("OnTextChanged", function(_, userInput)
    UpdateCounter()
    if userInput then MarkDirty() end
end)


-- ---------------------------------------------------------------------------
-- Interface for the other parts (MacroIcons, MacroTransfer, MacroActions): they
-- use these functions and hooks of ns.Macros, nothing else of this file
-- ---------------------------------------------------------------------------
function Macros.Tab() return state.tab end   -- "general" | "character"
function Macros.List() return data end       -- the macros of the open tab: { index, name, icon, body }
function Macros.Selection() return state.sel, state.selGroup end   -- macro index, selected group name
function Macros.GroupOf(m) return GroupOf(m) end
function Macros.Groups() return MG() end     -- { names, collapsed, of } of the open tab
function Macros.GetIcon() return state.icon end

-- the icon picker chose an icon for the macro being edited
function Macros.SetIcon(icon)
    state.icon, state.iconChanged = icon, true
    iconBtn.icon:SetTexture(IconPath(icon))
    MarkDirty()
end

-- is there a free slot on the open tab
function Macros.HasRoom()
    local numGeneral, numChar = GetNumMacros()
    if state.tab == "character" then return (numChar or 0) < MAX_CHAR end
    return (numGeneral or 0) < CharBase()
end

-- the list changed behind the page's back (import): read it again, keep the selection if it survived
function Macros.Reselect()
    LoadMacros()
    UpdateTabs()
    if state.sel and GetMacroInfo(state.sel) then Select(state.sel) else SelectFirstOrClear() end
end

local showHooks, hideHooks = {}, {}
function Macros.OnShow(fn) showHooks[#showHooks + 1] = fn end   -- the page opens
function Macros.OnHide(fn) hideHooks[#hideHooks + 1] = fn end   -- the page closes
iconBtn:SetScript("OnClick", function() Macros.ToggleIconPicker() end)   -- MacroIcons.lua



-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Macros.Reload()
    if not mm:IsShown() then return end
    local selName = state.sel and GetMacroInfo(state.sel)
    LoadMacros()
    UpdateTabs()
    if selName then
        local idx = GetMacroIndexByName(selName)
        if idx and idx > 0 then
            if state.dirty then state.sel = idx else Select(idx) end
        end
    end
    RenderList()
end

mm:SetScript("OnShow", function()
    LoadMacros()
    UpdateTabs()
    for _, fn in ipairs(showHooks) do fn() end
    if state.sel and GetMacroInfo(state.sel) then
        RevealSelection()
        RenderList()
    elseif not state.isNew then
        SelectFirstOrClear()
    else
        RenderList()
    end
    UpdateButtons()
    Status(L["Drag a macro from the list onto an action bar."])
end)
mm:SetScript("OnHide", function()
    for _, fn in ipairs(hideHooks) do fn() end
    ns.SpellSearch.Hide()
    UI.CloseMenu()
end)

ns.RegisterEvent("UPDATE_MACROS", function()
    if not mm:IsShown() then return end
    -- changed here or in Blizzard's macro UI: re-read, keep the selection if it survived
    LoadMacros()
    UpdateTabs()
    if state.sel and not GetMacroInfo(state.sel) then
        state.sel = nil
        if not state.isNew then SelectFirstOrClear() end
    end
    RenderList()
    UpdateButtons()
end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if not mm:IsShown() then return end
    Status(L["In combat: macros are read-only until combat ends."], true)
    UpdateButtons()
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if not mm:IsShown() then return end
    Status(nil)
    UpdateButtons()
end)
ns.On("MODULES_CHANGED", function() if mm:IsShown() then UpdateButtons() end end)


App:AddPage({
    key = "macros", section = "macros", label = L["Macro manager"], order = 110,
    Build = function(_, frame)
        mm:SetParent(frame)
        mm:ClearAllPoints()
        mm:SetAllPoints(frame)
        mm:Show()
    end,
})

function ns.ToggleMacroManager() App:Toggle("macros") end

