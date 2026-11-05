-- ---------------------------------------------------------------------------
-- Macro assistant: a window (opened by the "Assistant" button of the Macro
-- Manager) that builds macro text from parts: spells and items (typed search
-- with suggestions from your spellbook and bags), target, conditions, extras
-- (several entries become one line each; /castsequence is not offered).
-- The text itself comes from MacroBuilder.lua; the preview is live. Save as a
-- new macro (needs no combat) or as a template ({s:ID} follows the game language).
--   ns.MacroAssistant.Toggle() / Open() / Hide() / IsShown()
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX, UI = ns.L, ns.T, ns.HEX, ns.UI
local Text, Skin = ns.Text, ns.Skin
local Macros, Builder = ns.Macros, ns.MacroBuilder

local Assistant = {}
ns.MacroAssistant = Assistant

local W, H = 640, 552
local COL_W, RIGHT_X = 296, 330
local MAX_ENTRIES, ENTRY_H = 8, 20
local SUGGESTIONS, SUGGEST_H = 7, 22

-- ---------------------------------------------------------------------------
-- What the player picked
-- ---------------------------------------------------------------------------
local st
local function Fresh()
    return { entries = {}, target = "target", conditions = {}, extras = {} }
end
st = Fresh()

local function EntryName(e)
    if e.spell then return ns.SpellName(e.spell) or ("spell " .. e.spell) end
    return e.name or "?"
end

local function SetList(set, order)
    local out = {}
    for _, key in ipairs(order) do if set[key] then out[#out + 1] = key end end
    return out
end

-- the table Builder.Build works on
local function BuilderState()
    return {
        entries = st.entries,
        target = st.target,
        conditions = SetList(st.conditions, Builder.CONDITION_ORDER),
        extras = SetList(st.extras, Builder.EXTRAS),
        aura = st.entries[1],   -- /cancelaura takes the first entry
    }
end

-- text with the spell names written out (for a macro) or as {s:ID} (for a template)
function Assistant.Text(forTemplate)
    return Builder.Build(BuilderState(), (not forTemplate) and ns.SpellName or nil)
end

-- ---------------------------------------------------------------------------
-- Labels (the builder holds keys only)
-- ---------------------------------------------------------------------------
local TARGET_LABEL = {
    target = L["Current target"], mouseover = L["Mouseover"], focus = L["Focus"], cursor = L["At the cursor"],
    player = L["Yourself"], targettarget = L["Target's target"], pet = L["Pet"],
    heal = L["Heal: mouseover, target, yourself"], harm = L["Harm: mouseover, target"],
    mouseover_target_self = L["Mouseover, target, yourself"],
}
for i = 1, 4 do TARGET_LABEL["party" .. i] = L["Party member %d"]:format(i) end

local CONDITION_LABEL = {
    shift = L["Shift held"], ctrl = L["Ctrl held"], alt = L["Alt held"],
    combat = L["In combat"], nocombat = L["Not in combat"],
    stealth = L["Stealthed"], nostealth = L["Not stealthed"],
    raid = L["In a raid"], party = L["In a party"], channeling = L["Channeling"],
}

local EXTRA_TIP = {
    showtooltip = L["The macro shows the icon and tooltip of its spell."],
    stopcasting = L["Stops the current cast first, so the new spell goes off at once."],
    cancelaura = L["Removes the buff of the first spell or item in the list."],
    focus = L["Sets your focus to the target."],
    startattack = L["Starts auto attack."],
    petattack = L["Sends your pet to attack."],
}

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
local win = UI.Window("BeautifulRogueMacroAssistant", W, H, L["Macro assistant"], { strata = "FULLSCREEN" })
local Status = UI.StatusLine(win)
local Refresh

local function Section(text, x, y) return UI.Label(win, text, x, y) end

-- ---- spells and items: search with suggestions
Section(L["SPELL OR ITEM"], 14, -38)
local search = UI.LineEdit(win, 13)
search:SetPoint("TOPLEFT", 14, -52)
search:SetSize(COL_W, 22)
UI.Placeholder(search, L["Type a name or ID ..."])

local pop = CreateFrame("Frame", nil, win)
pop:SetFrameStrata("FULLSCREEN_DIALOG")
pop:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -1)
pop:SetSize(COL_W, SUGGESTIONS * SUGGEST_H)
Skin(pop, T.panel, T.line)
pop:Hide()

local candidates     -- { { kind, id, name, icon, key }, ... } read when the window opens
local shown = {}     -- the suggestions on display

local function ReadCandidates()
    candidates = {}
    local seen = {}
    -- spells: one line per name (the highest rank), the macro text follows the client language
    local list = ns.SpellSearch.List() or {}
    for i = #list, 1, -1 do
        local s = list[i]
        if not seen["s" .. s.name] then
            seen["s" .. s.name] = true
            candidates[#candidates + 1] = { kind = "spell", id = s.id, name = s.name, icon = s.icon, key = s.key }
        end
    end
    ns.ForEachBagItem(function(id, name)
        if seen["i" .. id] then return end
        seen["i" .. id] = true
        name = name or ns.ItemName(id)
        if type(name) == "string" and name ~= "" then
            candidates[#candidates + 1] = { kind = "item", id = id, name = name, icon = ns.ItemIcon(id), key = ns.Fold(name) }
        end
    end)
    table.sort(candidates, function(a, b)
        if a.key ~= b.key then return a.key < b.key end
        return a.kind < b.kind
    end)
end

local function AddEntry(e)
    if #st.entries >= MAX_ENTRIES then
        Status(L["Up to %d entries."]:format(MAX_ENTRIES), true)
        return
    end
    st.entries[#st.entries + 1] = e
    search:SetText("")
    pop:Hide()
    Refresh()
end

local function Pick(c)
    if not c then return end
    if c.kind == "spell" then AddEntry({ spell = c.id }) else AddEntry({ item = c.id, name = c.name }) end
    search:SetFocus()
end

local sugRows = {}
for i = 1, SUGGESTIONS do
    local r = CreateFrame("Button", nil, pop)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * SUGGEST_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * SUGGEST_H)
    r:SetHeight(SUGGEST_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = Text(r, 12)
    r.name:SetPoint("LEFT", 28, 0)
    r.name:SetPoint("RIGHT", -64, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.kind = Text(r, 11)
    r.kind:SetPoint("RIGHT", -8, 0)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    ns.Color(r.hl, T.hover)
    r:SetScript("OnClick", function(self) Pick(self.candidate) end)
    sugRows[i] = r
end

local function Suggest()
    local q = ns.Fold(ns.Trim(search:GetText()))
    shown = {}
    if q ~= "" and candidates then
        local starts, inside = {}, {}
        for _, c in ipairs(candidates) do
            if c.key:sub(1, #q) == q or tostring(c.id) == q then
                starts[#starts + 1] = c
            elseif c.key:find(q, 1, true) then
                inside[#inside + 1] = c
            end
        end
        for _, list in ipairs({ starts, inside }) do
            for _, c in ipairs(list) do
                if #shown < SUGGESTIONS then shown[#shown + 1] = c end
            end
        end
    end
    for i, r in ipairs(sugRows) do
        local c = shown[i]
        r.candidate = c
        if c then
            r.icon:SetTexture(c.icon)
            r.name:SetText(c.name)
            r.kind:SetText(ns.Muted(c.kind == "spell" and L["Spell"] or L["Item"]))
            r:Show()
        else
            r:Hide()
        end
    end
    pop:SetHeight(math.max(1, #shown * SUGGEST_H))
    pop:SetShown(#shown > 0)
end
search:SetScript("OnTextChanged", Suggest)
search:SetScript("OnEscapePressed", function(self)
    if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
    pop:Hide()
end)
-- Enter takes the first suggestion; a name nothing matches is written as typed
search:SetScript("OnEnterPressed", function(self)
    local typed = ns.Trim(self:GetText())
    local id = tonumber(typed)
    if shown[1] then
        Pick(shown[1])
    elseif id and ns.SpellName(id) then
        -- a spell ID the spellbook doesn't hold: still a spell, never "/cast 1234"
        AddEntry({ spell = id })
        self:SetFocus()
    elseif typed ~= "" then
        AddEntry({ name = typed })
        self:SetFocus()
    end
end)

-- ---- the entries
local entryPanel = CreateFrame("Frame", nil, win)
entryPanel:SetPoint("TOPLEFT", 14, -80)
entryPanel:SetSize(COL_W, MAX_ENTRIES * ENTRY_H)
Skin(entryPanel, T.panel)
local emptyHint = UI.Hint(entryPanel, L["Search above. Several entries become one line each."], COL_W - 20)
emptyHint:SetPoint("TOPLEFT", 10, -10)

local entryRows = {}
local function Move(i, d)
    local j = i + d
    if j < 1 or j > #st.entries then return end
    st.entries[i], st.entries[j] = st.entries[j], st.entries[i]
    Refresh()
end
for i = 1, MAX_ENTRIES do
    local r = CreateFrame("Frame", nil, entryPanel)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ENTRY_H)
    r:SetSize(COL_W, ENTRY_H)
    r.num = Text(r, 11)
    r.num:SetPoint("LEFT", 6, 0)
    ns.Color(r.num, T.muted)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 24, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = Text(r, 12)
    r.name:SetPoint("LEFT", 46, 0)
    r.name:SetPoint("RIGHT", -50, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.hl = r:CreateTexture(nil, "BACKGROUND")   -- marks the entry being dragged
    r.hl:SetAllPoints()
    ns.Color(r.hl, T.accentSoft)
    r.hl:Hide()
    -- drag the grip up or down; the entries are the items of st.entries
    r.grip = UI.DragHandle(r, {
        key = function() return st.entries[i] end,
        indexOf = function(entry) return ns.IndexOf(st.entries, entry) end,
        targetAt = function()
            local top = entryPanel:GetTop()
            if not top then return end
            local slot = math.floor((top - UI.CursorY(entryPanel)) / ENTRY_H) + 1
            return math.max(1, math.min(#st.entries, slot))
        end,
        move = function(entry, dir) Move(ns.IndexOf(st.entries, entry), dir) end,
        start = function() Refresh(true) end,
        done = function() Refresh(true) end,
        ghost = function(entry)
            return EntryName(entry), entry.spell and ns.SpellIcon(entry.spell) or (entry.item and ns.ItemIcon(entry.item)) or Macros.QUESTION_ICON
        end,
    })
    r.grip:SetPoint("RIGHT", -26, 0)
    r.del = UI.Button(r, 16, "×", function() table.remove(st.entries, i) Refresh() end, 16)
    r.del:SetPoint("RIGHT", -6, 0)
    entryRows[i] = r
end

-- ---- target
Section(L["TARGET"], 14, -250)
local targetDD = UI.Dropdown(win, function()
    local items = {}
    for _, key in ipairs(Builder.TARGET_ORDER) do items[#items + 1] = { key, TARGET_LABEL[key] or key } end
    return items
end, function() return st.target end, function(v) st.target = v Refresh() end, COL_W)
targetDD:SetPoint("TOPLEFT", 14, -264)

-- ---- conditions and extras
local checks = {}
local function CheckGrid(order, labelOf, set, x0, y0, colW, perCol, tip)
    for i, key in ipairs(order) do
        local col, row = math.floor((i - 1) / perCol), (i - 1) % perCol
        local c = UI.CheckRow(win, labelOf(key), function() return set[key] or false end,
            function(v) set[key] = v or nil Refresh() end, colW)
        c:SetPoint("TOPLEFT", x0 + col * colW, y0 - row * 22)
        if tip and tip[key] then UI.Tooltip(c, { labelOf(key), tip[key] }) end
        checks[#checks + 1] = c
    end
end

Section(L["CONDITIONS (all must apply)"], 14, -296)
CheckGrid(Builder.CONDITION_ORDER, function(k) return CONDITION_LABEL[k] end, st.conditions, 14, -312, COL_W / 2, 5)
Section(L["EXTRAS"], 14, -432)
CheckGrid(Builder.EXTRAS, function(k) return k == "showtooltip" and "#showtooltip" or ("/" .. k) end,
    st.extras, 14, -448, COL_W / 2, 3, EXTRA_TIP)

-- ---- preview (right column)
Section(L["PREVIEW"], RIGHT_X, -38)
local counter = Text(win, 11)
counter:SetPoint("TOPRIGHT", -14, -38)
local previewBox = CreateFrame("Frame", nil, win)
previewBox:SetPoint("TOPLEFT", RIGHT_X, -52)
previewBox:SetSize(COL_W, 200)
Skin(previewBox, T.control, T.input)
local previewText = Text(previewBox, 12)
previewText:SetPoint("TOPLEFT", 8, -8)
previewText:SetPoint("BOTTOMRIGHT", -8, 8)
previewText:SetJustifyH("LEFT")
previewText:SetJustifyV("TOP")
previewText:SetWordWrap(true)
local previewHint = UI.Hint(previewBox, L["The macro text appears here as you choose."], COL_W - 20)
previewHint:SetPoint("TOPLEFT", 10, -10)

-- ---- saving
Section(L["NAME"], RIGHT_X, -270)
local nameBox = UI.LineEdit(win, 13, Macros.NAME_MAX)
nameBox:SetPoint("TOPLEFT", RIGHT_X, -284)
nameBox:SetSize(COL_W, 22)
UI.Placeholder(nameBox, L["Default: the first entry"])

local function SaveName()
    local name = ns.Trim(nameBox:GetText())
    if name == "" and st.entries[1] then name = ns.Trim(EntryName(st.entries[1])) end
    return Macros.ShortName(name)
end

local function Checked()
    local text, info = Assistant.Text(false)
    if text == "" then Status(L["Add a spell or item first."], true) return end
    if info.tooLong then
        Status(L["The text is %d characters long; a macro holds %d."]:format(info.length, Macros.BODY_MAX), true)
        return
    end
    return text
end

local macroBtn, templateBtn
macroBtn = UI.Button(win, 118, L["Create macro"], function()
    local text = Checked()
    if not text then return end
    local name = SaveName()
    local perChar = Macros.Tab() == "character"
    local idx, why = Macros.Create(name, text, perChar)
    if not idx then Status(why, true) return end
    Macros.Reload()
    Status(L["Macro \"%s\" created under %s. Drag it from the macro list onto an action bar."]:format(
        name, perChar and L["Character"] or L["General"]))
end)
macroBtn:SetPoint("TOPLEFT", RIGHT_X, -318)
UI.Tooltip(macroBtn, function()
    return { L["Create macro"], L["Writes the text as a new macro on the open tab (%s). Not possible in combat."]:format(
        Macros.Tab() == "character" and L["Character"] or L["General"]) }
end)

templateBtn = UI.Button(win, 118, L["Save as template"], function()
    local text, info = Assistant.Text(true)
    if text == "" then Status(L["Add a spell or item first."], true) return end
    if info.tooLong then
        Status(L["The text is %d characters long; a macro holds %d."]:format(info.length, Macros.BODY_MAX), true)
        return
    end
    local t, why = ns.Templates.Add(SaveName(), "", text)
    if not t then Status(why, true) return end
    Status(L["Template \"%s\" saved. Find it on the Templates page."]:format(t.name))
end)
templateBtn:SetPoint("LEFT", macroBtn, "RIGHT", 6, 0)
UI.Tooltip(templateBtn, { L["Save as template"],
    L["Keeps the text on the Templates page; the spell names follow the game language ({s:ID})."] })

local clearBtn = UI.Button(win, 48, L["Clear"], function()
    -- cleared in place: the check rows keep their tables
    local fresh = Fresh()
    wipe(st.entries) wipe(st.conditions) wipe(st.extras)
    st.target = fresh.target
    nameBox:SetText("")
    search:SetText("")
    Refresh()
end)
clearBtn:SetPoint("LEFT", templateBtn, "RIGHT", 6, 0)

-- ---------------------------------------------------------------------------
-- Refresh: everything the state shows
-- ---------------------------------------------------------------------------
local function UpdateButtons()
    macroBtn:SetAlpha(ns.InCombat() and 0.4 or 1)
end

Refresh = function(keepStatus)
    for i, r in ipairs(entryRows) do
        local e = st.entries[i]
        if e then
            r.num:SetText(i)
            r.icon:SetTexture(e.spell and ns.SpellIcon(e.spell) or (e.item and ns.ItemIcon(e.item)) or Macros.QUESTION_ICON)
            r.name:SetText(EntryName(e))
            r.hl:SetShown(UI.dragKey == e)
            r:SetAlpha(UI.dragKey == e and 0.4 or 1)
            r:Show()
        else
            r:Hide()
        end
    end
    emptyHint:SetShown(#st.entries == 0)
    targetDD:Refresh()
    for _, c in ipairs(checks) do c:Refresh() end
    local text, info = Assistant.Text(false)
    previewText:SetText(text)
    previewHint:SetShown(text == "")
    counter:SetText(info.tooLong and ns.Colorize(HEX.alert, ("%d/%d"):format(info.length, Macros.BODY_MAX))
        or ns.Muted(("%d/%d"):format(info.length, Macros.BODY_MAX)))
    if info.tooLong then
        Status(L["The text is %d characters long; a macro holds %d."]:format(info.length, Macros.BODY_MAX), true)
    elseif not keepStatus then
        Status(nil)
    end
    UpdateButtons()
end

-- ---------------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------------
local placed
function Assistant.Open()
    ReadCandidates()
    if not placed then UI.PlaceDialog(win) placed = true end
    win:Show()
    win:Raise()
    Refresh()
    search:SetFocus()
end
function Assistant.Hide() win:Hide() end
function Assistant.IsShown() return win:IsShown() end
function Assistant.Toggle()
    if win:IsShown() then win:Hide() else Assistant.Open() end
end
win:SetScript("OnHide", function() pop:Hide() UI.CloseMenu() end)

Macros.OnHide(function() win:Hide() end)   -- leaving the Macro Manager closes it
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() if win:IsShown() then UpdateButtons() end end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if win:IsShown() then UpdateButtons() end end)
