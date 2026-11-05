-- ---------------------------------------------------------------------------
-- Macro Manager: the icon picker (docked to the right of the page).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, UI, Text = ns.L, ns.T, ns.UI, ns.Text
local Macros, IconFilter = ns.Macros, ns.IconFilter
-- The search looks at the names of the spells and items that use an icon --
-- straight from the client, so it works in every language; the name index is
-- built in the background the first time you type. With the icon data
-- (BeautifulRogue_IconData, loaded when the picker opens) it also matches icon names
-- and file IDs and can be narrowed down by category (IconFilter*.lua).
local App = ns.App
local mm, Status = Macros.page, Macros.Status
local IconPath, QUESTION_ICON = Macros.IconPath, Macros.QUESTION_ICON
local PAGE_W, PAGE_H = App.CONTENT_W, App.CONTENT_H

local ICON, IGAP = 30, 4
local COLS = math.floor((PAGE_W - 12 + IGAP) / (ICON + IGAP))
local GRID_TOP = -64
local IROWS = math.floor((PAGE_H + GRID_TOP - 24 + IGAP) / (ICON + IGAP))
local picker = CreateFrame("Frame", "BeautifulRogueMacroIconPicker", mm)
picker:SetAllPoints(mm)
picker:SetFrameLevel(mm:GetFrameLevel() + 20)
picker:EnableMouse(true)
picker:EnableMouseWheel(true)
picker:Hide()
ns.Skin(picker, T.background)
picker.title = Text(picker, 13)
picker.title:SetPoint("TOPLEFT", 0, -4)
picker.title:SetText(L["Choose icon"])
ns.Color(picker.title, T.accent)
picker.done = UI.Button(picker, 90, L["Done"], function() picker:Hide() end)
picker.done:SetPoint("TOPRIGHT", 0, 0)
picker.done:SetAccent(true)
picker.thumb = picker:CreateTexture(nil, "OVERLAY")
picker.thumb:SetWidth(2)
ns.Color(picker.thumb, T.accent, 0.6)
picker.info = UI.Hint(picker, "")
picker.info:SetPoint("BOTTOMLEFT", 0, 0)
picker.info:SetPoint("BOTTOMRIGHT", 0, 0)

local icons, iconScroll = nil, 0
local iconView, query = nil, ""
local dataList, dataKey, dataDone, dataProgress = nil, nil, true, 1   -- result of the icon-data search
local cells = {}
-- spells whose icons lead the list; modules add theirs (rank-1 IDs)
Macros.featuredSpells = {}
Macros.featuredItems = {}

local nameIndex, indexDone, indexNext = nil, false, 1
local INDEX_MAX_SPELL, INDEX_STEP = 40000, 2500
local function AddName(icon, name)
    if not icon or type(name) ~= "string" or name == "" then return end
    local e = nameIndex[icon]
    if not e then
        e = { names = {}, key = "" }
        nameIndex[icon] = e
    end
    for _, n in ipairs(e.names) do if n == name then return end end
    if #e.names < 6 then e.names[#e.names + 1] = name end
    e.key = e.key .. "\n" .. ns.Fold(name)
end

local function IndexQuickSources()
    -- the spellbook (covers this client's own spell IDs, however high)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local ok, lines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
        for line = 1, (ok and lines or 0) do
            local okL, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
            if okL and info and info.itemIndexOffset and info.numSpellBookItems then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local okI, item = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
                    if okI and item then AddName(item.iconID, item.name) end
                end
            end
        end
    end
    for _, id in ipairs(Macros.featuredSpells) do AddName(ns.SpellIcon(id), ns.SpellName(id)) end
    ns.ForEachBagItem(function(id, name) AddName(ns.ItemIcon(id), name) end)
    for slot = 1, 19 do
        local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", slot)
        local name = ns.EquippedName(slot)
        if tex and name then AddName(tex, name) end
    end
end

local RunSearch
local indexer = CreateFrame("Frame", nil, picker)
indexer:Hide()
indexer:SetScript("OnUpdate", function(self)
    if not (C_Spell and C_Spell.GetSpellInfo) then indexDone = true self:Hide() RunSearch() return end
    local last = math.min(INDEX_MAX_SPELL, indexNext + INDEX_STEP - 1)
    pcall(function()
        for id = indexNext, last do
            local info = C_Spell.GetSpellInfo(id)
            if info and info.iconID then AddName(info.iconID, info.name) end
        end
    end)
    indexNext = last + 1
    if indexNext > INDEX_MAX_SPELL then
        indexDone = true
        self:Hide()
    end
    RunSearch()
end)

local function EnsureIndex()
    if nameIndex then return end
    nameIndex = {}
    IndexQuickSources()
    indexer:Show()
end

local function BuildIcons()
    icons = {}
    local seen = {}
    local function add(v)
        if v and not seen[v] then
            seen[v] = true
            icons[#icons + 1] = v
        end
    end
    add(QUESTION_ICON)
    for _, id in ipairs(Macros.featuredSpells) do add(ns.SpellIcon(id)) end
    for _, id in ipairs(Macros.featuredItems) do add(ns.ItemIcon(id)) end
    -- the game's own macro icon lists (fill a table on modern clients)
    for _, fname in ipairs({ "GetLooseMacroIcons", "GetMacroIcons", "GetLooseMacroItemIcons", "GetMacroItemIcons" }) do
        local fn = _G[fname]
        if fn then
            local t = {}
            local ok, ret = pcall(fn, t)
            if ok and type(ret) == "table" then t = ret end
            for _, v in ipairs(t) do add(v) end
        end
    end
    if #icons < 100 and GetNumMacroIcons and GetMacroIconInfo then
        for i = 1, GetNumMacroIcons() do add(GetMacroIconInfo(i)) end
    end
    iconView = icons
end

local function RenderIcons()
    local maxRow = math.max(0, math.ceil(#iconView / COLS) - IROWS)
    iconScroll = math.max(0, math.min(iconScroll, maxRow))
    for i, c in ipairs(cells) do
        local v = iconView[iconScroll * COLS + i]
        c.value = v
        if v then
            c.tex:SetTexture(IconPath(v))
            c.edge:SetColorTexture(unpack(v == Macros.GetIcon() and T.accent or T.line))
            c:Show()
        else
            c:Hide()
        end
    end
    if maxRow > 0 then
        local trackH = IROWS * (ICON + IGAP) - IGAP
        local thumbH = math.max(16, trackH * IROWS / (maxRow + IROWS))
        picker.thumb:ClearAllPoints()
        picker.thumb:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -1, GRID_TOP - (trackH - thumbH) * iconScroll / maxRow)
        picker.thumb:SetHeight(thumbH)
        picker.thumb:Show()
    else
        picker.thumb:Hide()
    end
    local filtered = IconFilter.HasSelection()
    if not dataDone then
        picker.info:SetText(L["%d matches  ·  searching %d%%"]:format(#iconView, math.floor(dataProgress * 100)))
    elseif query == "" and not filtered then
        picker.info:SetText(L["%d icons"]:format(#iconView))
    elseif query == "" then
        picker.info:SetText(#iconView > 0 and L["%d matches"]:format(#iconView) or L["No icon matches that name."])
    elseif not indexDone and not query:match("^%d+$") then
        picker.info:SetText(L["%d matches  ·  indexing names %d%%"]:format(#iconView,
            math.floor(math.min(1, indexNext / INDEX_MAX_SPELL) * 100)))
    else
        picker.info:SetText(#iconView > 0 and L["%d matches"]:format(#iconView) or L["No icon matches that name."])
    end
end

-- icons whose spell or item names contain the query, best matches first
local function NameHits()
    EnsureIndex()
    local hits = {}
    for icon, e in pairs(nameIndex) do
        local pos = e.key:find(query, 1, true)
        if pos then
            -- names that start with the query rank first
            local prefix = e.key:sub(pos - 1, pos - 1) == "\n" and 0 or 1
            hits[#hits + 1] = { icon = icon, rank = prefix, name = e.names[1] or "" }
        end
    end
    table.sort(hits, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.name < b.name
    end)
    for i, h in ipairs(hits) do hits[i] = h.icon end
    return hits
end

-- spell/item name hits first, then what the icon data found (names, IDs, categories)
local function CombineView()
    local out, seen = {}, {}
    local function add(v)
        if not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    if query ~= "" and not query:match("^%d+$") then
        local selected = IconFilter.selected
        local filtered = IconFilter.HasSelection()
        for _, icon in ipairs(NameHits()) do
            if not filtered or IconFilter.InCategories(icon, selected) then add(icon) end
        end
    end
    for _, v in ipairs(dataList or {}) do add(v) end
    iconView = out
end

local function SearchKey()
    local keys = {}
    for k in pairs(IconFilter.selected) do keys[#keys + 1] = k end
    table.sort(keys)
    return query .. "\n" .. table.concat(keys, ",")
end

RunSearch = function()
    if not icons then BuildIcons() end
    local filtered = IconFilter.HasSelection()
    if IconFilter.Available() and (filtered or query ~= "") then
        -- the icon data search runs in portions; the view updates as results come in
        local key = SearchKey()
        if key ~= dataKey then
            dataKey, dataList, dataDone, dataProgress = key, {}, false, 0
            IconFilter.Start({
                query = IconFilter.Normalize(query), selected = IconFilter.selected,
                onUpdate = function(list, done, progress)
                    dataList, dataDone, dataProgress = list, done, progress
                    CombineView()
                    RenderIcons()
                end,
            })
        end
        CombineView()
        RenderIcons()
        return
    end
    IconFilter.Cancel()
    dataKey, dataList, dataDone = nil, nil, true
    if query == "" then
        iconView = icons
    elseif query:match("^%d+$") then
        iconView = {}
        for _, v in ipairs(icons) do
            if tostring(v):find(query, 1, true) then iconView[#iconView + 1] = v end
        end
    else
        iconView = NameHits()
    end
    RenderIcons()
end

local search = UI.LineEdit(picker, 13)
search:SetPoint("TOPLEFT", 0, -28)
search:SetPoint("TOPRIGHT", -78, -28)
search:SetHeight(22)
UI.Placeholder(search, L["Search name or ID ..."])
search:SetScript("OnTextChanged", function(self)
    query = ns.Fold(ns.Trim(self:GetText()))
    iconScroll = 0
    RunSearch()
end)

-- category filter (needs the icon data addon)
local function OnFilterChanged()
    iconScroll = 0
    picker.filter:SetAccent(IconFilter.HasSelection())
    RunSearch()
end
picker.filter = UI.Button(picker, 72, L["Filter"], function(self)
    IconFilter.OpenMenu(self, OnFilterChanged, { point = "TOPRIGHT", relPoint = "BOTTOMRIGHT", width = 200 })
end, 22)
picker.filter:SetPoint("TOPRIGHT", 0, -28)
UI.Tooltip(picker.filter, { L["Filter"],
    L["Inside a group the ticked categories add up, across groups they narrow down. Example: Abilities (General) and Rogue (Classes) show the rogue abilities."] })

for i = 1, COLS * IROWS do
    local c = CreateFrame("Button", nil, picker)
    c:SetSize(ICON, ICON)
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    c:SetPoint("TOPLEFT", 1 + col * (ICON + IGAP), GRID_TOP - row * (ICON + IGAP))
    c.edge = c:CreateTexture(nil, "BACKGROUND")
    c.edge:SetPoint("TOPLEFT", -1, 1)
    c.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    ns.Color(c.edge, T.line)
    c.tex = c:CreateTexture(nil, "ARTWORK")
    c.tex:SetAllPoints()
    c.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.hl = c:CreateTexture(nil, "HIGHLIGHT")
    c.hl:SetAllPoints()
    c.hl:SetColorTexture(1, 1, 1, 0.2)
    c:SetScript("OnClick", function(self)
        if not self.value then return end
        Macros.SetIcon(self.value)
        RenderIcons()
        Status(L["Icon chosen. Save to keep it."])
    end)
    c:SetScript("OnEnter", function(self)
        local e = nameIndex and nameIndex[self.value]
        local iconName = IconFilter.NameOf(self.value)
        if not e and not iconName then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if e then
            for _, n in ipairs(e.names) do GameTooltip:AddLine(n, 1, 1, 1) end
        end
        if iconName then GameTooltip:AddLine(iconName, 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cells[i] = c
end

picker:SetScript("OnMouseWheel", function(_, delta)
    iconScroll = iconScroll - delta * 2
    RenderIcons()
end)
picker:SetScript("OnShow", function()
    if not icons then BuildIcons() end
    -- the icon data loads here, the first time the picker opens
    local ready = IconFilter.Load()
    picker.filter:SetShown(ready)
    search:SetPoint("TOPRIGHT", ready and -78 or 0, -28)
    search.hint:SetText(ready and L["Search name or ID ..."] or L["Search spell or item name ..."])
    RunSearch()
end)
picker:SetScript("OnHide", function()
    search:ClearFocus()
    IconFilter.Cancel()
    dataKey, dataDone = nil, true   -- a half-finished search starts over on the next open
end)
Macros.OnHide(function() picker:Hide() end)


function Macros.ToggleIconPicker()
    if picker:IsShown() then picker:Hide() else picker:Show() end
end
