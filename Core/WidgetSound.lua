-- ---------------------------------------------------------------------------
-- UI: the sound picker. Every place where BeautifulRogue lets you pick a
-- sound uses this one control: a field with the chosen sound and a play
-- button, below it the volume. The field opens a list of every sound the
-- client has (ns.Sound) with a search and groups by name prefix; a click on a
-- row picks the sound and plays it, the arrow in front of a row only plays it.
--   UI.SoundPicker(parent, get, set, width)
--     get() -> name, volume (0-100)      set(name, volume)
-- The list is one shared popover, like the dropdown menu.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, UI, Text = ns.L, ns.T, ns.UI, ns.Text
local Sound = ns.Sound

UI.SOUND_PICKER_H = 62   -- field + volume slider

local POP_W, ROW_H, VIEW = 340, 20, 14
local TOP, FOOT, PAD = 40, 36, 8
local ALL = "*"   -- the group value for "all sounds"

local pop, catcher, rows, bar, search, groupDD, countText
local current                     -- the open picker's state { get, set, box }
local view, offset, group, query = {}, 0, ALL, ""

local function Close()
    if pop then pop:Hide() end
end
UI.CloseSoundPicker = Close

local function ChosenName() return current and (current.get()) end
local function ChosenVolume()
    local _, v = current.get()
    return tonumber(v) or 100
end

local function Render()
    local name = ChosenName()
    offset = math.max(0, math.min(offset, #view - VIEW))
    for i = 1, VIEW do
        local r, e = rows[i], view[offset + i]
        r.entry = e
        if e then
            r.text:SetText(Sound.Title(e.name))
            local on = e.name == name
            r.sel:SetShown(on)
            r.mark:SetShown(on)
            r:Show()
        else
            r:Hide()
        end
    end
    bar:Update(#view, VIEW, offset)
    countText:SetText(L["%d sounds"]:format(#view))
end

local function Refilter()
    view = Sound.Filter(query, group ~= ALL and group or nil)
    Render()
end

local function Pick(e)
    local vol = ChosenVolume()
    current.set(e.name, vol)
    current.box:Refresh()
    Sound.Preview(e.name, vol)
    Render()
end

local function GroupItems()
    local _, groups = Sound.List()
    local items = { { ALL, L["All sounds"] } }
    for _, g in ipairs(groups) do
        local label = g.key == Sound.OTHER and L["Other"] or g.key
        items[#items + 1] = { g.key, label, tostring(g.count) }
    end
    return items
end

local function Row(i)
    local r = CreateFrame("Button", nil, pop)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", PAD, -TOP - (i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", -PAD - 10, -TOP - (i - 1) * ROW_H)   -- (room for the scroll bar)
    r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.sel:SetAllPoints()
    ns.Color(r.sel, T.accentSoft)
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetPoint("TOPLEFT")
    r.mark:SetPoint("BOTTOMLEFT")
    r.mark:SetWidth(2)
    ns.Color(r.mark, T.accent)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    ns.Color(r.hl, T.hover)
    -- only listen
    r.play = CreateFrame("Button", nil, r)
    r.play:SetSize(18, 18)
    r.play:SetPoint("LEFT", 4, 0)
    r.play.arrow = UI.Arrow(r.play, 10, "right")
    r.play.arrow:SetPoint("CENTER")
    r.play.hl = r.play:CreateTexture(nil, "HIGHLIGHT")
    r.play.hl:SetAllPoints()
    ns.Color(r.play.hl, T.hover)
    r.play:SetScript("OnClick", function() if r.entry then Sound.Preview(r.entry.name, ChosenVolume()) end end)
    r.text = Text(r, 12)
    r.text:SetPoint("LEFT", 26, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function() if r.entry then Pick(r.entry) end end)
    return r
end

local function Build()
    if pop then return end
    pop = CreateFrame("Frame", "BeautifulRogueSoundPicker", UIParent)
    pop:SetFrameStrata("FULLSCREEN_DIALOG")   -- under the group menu (TOOLTIP)
    pop:SetSize(POP_W, TOP + VIEW * ROW_H + FOOT)
    pop:SetClampedToScreen(true)
    pop:EnableMouse(true)
    pop:EnableMouseWheel(true)
    pop:Hide()
    ns.Skin(pop, T.popover)
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints()
    catcher:SetFrameStrata("FULLSCREEN")      -- over the app window: a click outside closes
    catcher:Hide()
    catcher:SetScript("OnClick", Close)
    pop:SetScript("OnHide", function()
        catcher:Hide()
        search:ClearFocus()
        UI.CloseMenu()   -- the group menu, if it is open
        current = nil
    end)

    search = UI.LineEdit(pop, 12)
    search:SetPoint("TOPLEFT", PAD, -PAD)
    search:SetPoint("TOPRIGHT", -PAD - 136, -PAD)
    search:SetHeight(22)
    UI.Placeholder(search, L["Search sounds ..."])
    search:SetScript("OnTextChanged", function(self)
        query = self:GetText() or ""
        offset = 0
        Refilter()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() Close() end)

    groupDD = UI.Dropdown(pop, GroupItems, function() return group end, function(v)
        group = v
        offset = 0
        Refilter()
    end, 130)
    groupDD:SetPoint("TOPRIGHT", -PAD, -PAD)

    rows = {}
    for i = 1, VIEW do rows[i] = Row(i) end
    bar = UI.ScrollBar(pop, function(o)
        offset = o
        Render()
    end)
    bar:SetPoint("TOPRIGHT", -PAD, -TOP)
    bar:SetHeight(VIEW * ROW_H)
    pop:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Render()
    end)

    countText = UI.Hint(pop, "")
    countText:SetPoint("BOTTOMLEFT", PAD + 2, 14)
    local done = UI.Button(pop, 80, L["Done"], Close, 22)
    done:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    done:SetAccent(true)
end

local function Open(box)
    Build()
    if pop:IsShown() and current == box.state then Close() return end
    UI.CloseMenu()
    current = box.state
    group = ALL
    search:SetText("")
    search:ClearFocus()
    query = ""
    groupDD:Refresh()
    view = Sound.Filter("", nil)
    -- the chosen sound in the middle of the list
    offset = 0
    local name = ChosenName()
    for i, e in ipairs(view) do
        if e.name == name then
            offset = i - math.floor(VIEW / 2)
            break
        end
    end
    pop:SetWidth(math.max(POP_W, (box:GetWidth() or 0) + 4))   -- (covers the volume slider underneath)
    pop:ClearAllPoints()
    pop:SetPoint("TOPLEFT", box.field, "BOTTOMLEFT", 0, -4)
    catcher:Show()
    pop:Show()
    Render()
end

function UI.SoundPicker(parent, get, set, width)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, UI.SOUND_PICKER_H)
    box.state = { get = get, set = set, box = box }

    local field = UI.Button(box, width - 26, "", function() Open(box) end, 22)
    field:SetPoint("TOPLEFT")
    field.text:ClearAllPoints()
    field.text:SetPoint("LEFT", 10, 0)
    field.text:SetPoint("RIGHT", -24, 0)
    field.text:SetJustifyH("LEFT")
    field.text:SetWordWrap(false)
    field.arrow = UI.Arrow(field, 12, "down")
    field.arrow:SetPoint("RIGHT", -6, 0)
    UI.Tooltip(field, function()
        local name = get()
        if Sound.Exists(name) then return { L["Sound"], L["Click to choose from every sound of the game."] } end
        return { tostring(name or ""), L["This game client doesn't have this sound; the default sound plays instead."] }
    end)
    field:HookScript("OnHide", function() if current == box.state then Close() end end)
    box.field = field

    local play = UI.Button(box, 22, "", function()
        local name, vol = get()
        Sound.Preview(name, vol)
    end, 22)
    play:SetPoint("TOPRIGHT")
    play.arrow = UI.Arrow(play, 12, "right")
    play.arrow:SetPoint("CENTER")
    UI.Tooltip(play, { L["Play"], L["Plays the chosen sound at the volume below."] })
    box.play = play

    box.volume = UI.ValueSlider(box, L["Volume"], 0, 100, 5, function()
        local _, vol = get()
        return tonumber(vol) or 100
    end, function(v)
        local name = get()
        set(name, v)
    end, width, "%d%%")
    box.volume:SetPoint("TOPLEFT", 0, -28)
    UI.Tooltip(box.volume.slider, { L["Volume"], L["A share of the game's master volume: it is turned down for a moment while the sound plays."] })
    box.volume.slider:HookScript("OnMouseUp", function()   -- hear the new volume
        local name, vol = get()
        Sound.Preview(name, vol)
    end)

    function box:Refresh()
        local name = get()
        field.text:SetText(Sound.Exists(name) and Sound.Title(name) or ns.Muted(tostring(name or Sound.DEFAULT)))
        self.volume:Refresh()
    end
    box:Refresh()
    return box
end
