-- ---------------------------------------------------------------------------
-- Editor of a rogue macro (the "Edit ..." button and a double click on the
-- Rogue macros page). Same frame and look as the macro assistant: the text
-- with placeholders on the left, the filled-in text (as it goes into the
-- game) with its length on the right. The name is fixed: "Refresh all" and
-- the action buttons find the macro by it.
--   Save      keeps the text as the player's own version and writes the macro
--   Default   drops the own version of this macro and writes the default
--   Cancel    closes without saving
-- Everything goes through WeaponMacros.lua (WeaponMacroSource, FillWeaponMacro,
-- SetWeaponMacroBody); this file only shows it.
--   Rogue:EditWeaponMacro(key) / Rogue.WeaponMacroEditor (the window, once built)
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX, UI = ns.L, ns.T, ns.HEX, ns.UI
local Text, Skin = ns.Text, ns.Skin
local Macros, Placeholders, Rogue = ns.Macros, ns.Placeholders, ns.Rogue

local W, H = 640, 362
local COL_W, RIGHT_X = 296, 330
local TEXT_MAX = 1023   -- the text with placeholders; the filled one is checked against 255

local win, area, nameText, stateText, previewText, counter, saveBtn, Status
local key, savedText   -- the macro being edited, the text it had when opened or saved

-- the placeholders on offer: the rogue's own, then those of the Placeholders page that are on
local function PlaceholderItems()
    local items = { { label = L["Insert placeholder"], isTitle = true } }
    local function add(code, desc)
        items[#items + 1] = { label = ns.Code(code) .. "  " .. ns.Muted(desc), fn = function()
            area.edit:Insert(code)
            area.edit:SetFocus()
            Rogue.WeaponMacroEditor.Refresh()
        end }
    end
    add("{r:front}", L["weapon in front (main hand)"])
    add("{r:back}", L["the other weapon (off hand; empty without Dual Wield)"])
    add("{p:MH}", L["poison for the main hand"])
    add("{p:OH}", L["poison for the off hand"])
    if Placeholders.GearEnabled() then
        add("{w:W1}", L["weapon W1"])
        add("{w:W2}", L["weapon W2"])
        add("{g:t1}", L["trinket 1"])
        add("{g:t2}", L["trinket 2"])
    end
    if Placeholders.CustomEnabled() then
        for _, c in ipairs(Placeholders.Custom()) do add("{c:" .. c.name .. "}", L["your own placeholder"]) end
    end
    return items
end

local function CurrentText() return ((area.edit:GetText() or ""):gsub("\r", "")) end

-- the preview, the counter and whether it can be saved
local function Refresh(keepStatus)
    if not (win and win:IsShown() and key) then return end
    local text = CurrentText()
    local filled, reason = Rogue:FillWeaponMacro(key, text)
    filled = filled or ""
    previewText:SetText(filled)
    local n = ns.Utf8Len(filled)
    counter:SetText(ns.Colorize(n > Macros.BODY_MAX and HEX.alert or HEX.muted, ("%d/%d"):format(n, Macros.BODY_MAX)))
    saveBtn:SetAlpha(reason and 0.4 or 1)
    saveBtn.reason = reason
    local default, own = Rogue:WeaponMacroSource(key)
    stateText:SetText((own or text ~= default) and ns.Colorize(HEX.accent, L["EDITED"]) or ns.Muted(L["default text"]))
    -- the reason it can't be saved stands in the status line while it lasts
    if reason then
        Status(L["Can't be saved: %s."]:format(reason), true)
    elseif not keepStatus then
        Status(text ~= savedText and L["Not saved yet."] or nil)
    end
end

local function Load(text)
    area:SetValue(text)
    savedText = CurrentText()
    Refresh()
end

local function Build()
    win = UI.Window("BeautifulRogueWeaponMacroEditor", W, H, L["Edit rogue macro"], { strata = "FULLSCREEN" })
    Status = UI.StatusLine(win)
    local function Section(label, x, y) return UI.Label(win, label, x, y) end

    -- ---- left: the name (fixed) and the text with placeholders
    Section(L["NAME"], 14, -38)
    local nameBox = CreateFrame("Frame", nil, win)
    nameBox:SetPoint("TOPLEFT", 14, -52)
    nameBox:SetSize(COL_W, 22)
    Skin(nameBox, T.panel, T.input)
    nameText = Text(nameBox, 13)
    nameText:SetPoint("LEFT", 8, 0)
    nameText:SetJustifyH("LEFT")
    stateText = Text(nameBox, 10)
    stateText:SetPoint("RIGHT", -8, 0)
    nameBox:EnableMouse(true)
    UI.Tooltip(nameBox, { L["NAME"], L["The addon gives the names: \"Refresh all\" and your action buttons find the macro by it."] })

    Section(L["MACRO TEXT"], 14, -86)
    area = UI.TextArea(win, TEXT_MAX)
    area:SetPoint("TOPLEFT", 14, -100)
    area:SetSize(COL_W, 196)
    area.edit:SetScript("OnTextChanged", function() Refresh() end)

    local insert = UI.Button(win, 145, L["Insert placeholder"] .. "  ›", function(self)
        UI.OpenMenu(self, PlaceholderItems(), { width = 300, point = "TOPLEFT", relPoint = "BOTTOMLEFT" })
    end, 22)
    insert:SetPoint("TOPLEFT", area, "BOTTOMLEFT", 0, -8)
    UI.Tooltip(insert, { L["Insert placeholder"], L["Puts it in at the cursor. Placeholders are filled in whenever the macro is written, so it keeps up with new weapons and poisons."] })
    local spell = ns.SpellSearch.Button(win, area.edit, function() Refresh() end, 145, 22)
    spell:SetPoint("LEFT", insert, "RIGHT", 6, 0)

    -- ---- right: the filled-in text, as it goes into the game
    Section(L["PREVIEW"], RIGHT_X, -38)
    counter = Text(win, 11)
    counter:SetPoint("TOPRIGHT", -14, -38)
    local previewBox = CreateFrame("Frame", nil, win)
    previewBox:SetPoint("TOPLEFT", RIGHT_X, -52)
    previewBox:SetSize(COL_W, 244)
    Skin(previewBox, T.control, T.input)
    previewText = Text(previewBox, 12)
    previewText:SetPoint("TOPLEFT", 8, -8)
    previewText:SetPoint("BOTTOMRIGHT", -8, 8)
    previewText:SetJustifyH("LEFT")
    previewText:SetJustifyV("TOP")
    previewText:SetWordWrap(true)

    -- ---- buttons
    local BTN_W = math.floor((COL_W - 12) / 3)
    saveBtn = UI.Button(win, BTN_W, L["Save"], function()
        if saveBtn.reason then Status(L["Can't be saved: %s."]:format(saveBtn.reason), true) return end
        local text = CurrentText()
        Rogue:SetWeaponMacroBody(key, text)
        savedText = text
        win:Hide()
    end, 22)
    saveBtn:SetPoint("TOPLEFT", previewBox, "BOTTOMLEFT", 0, -8)
    saveBtn:SetAccent(true)
    UI.Tooltip(saveBtn, { L["Save"], L["Keeps this text for the macro (all characters) and writes the macro now; in combat when combat ends."] })
    local defaultBtn = UI.Button(win, BTN_W, L["Default"], function()
        Rogue:SetWeaponMacroBody(key, nil)
        Load((Rogue:WeaponMacroSource(key)))
        Status(L["Default text restored."])
    end, 22)
    defaultBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
    UI.Tooltip(defaultBtn, { L["Default"], L["Drops your own text of this macro and writes the default text into it."] })
    local cancel = UI.Button(win, BTN_W, L["Cancel"], function() win:Hide() end, 22)
    cancel:SetPoint("LEFT", defaultBtn, "RIGHT", 6, 0)
    UI.Tooltip(cancel, { L["Cancel"], L["Closes without saving."] })

    win:SetScript("OnHide", function() area.edit:ClearFocus() UI.CloseMenu() end)
    ns.RegisterEvent("BAG_UPDATE", function() Refresh(true) end)
    ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() Refresh(true) end)
end

Rogue.WeaponMacroEditor = { Refresh = function() Refresh() end }

-- opens the editor for a macro key (dagger, backstab, poisonMH, ...)
local placed
function Rogue:EditWeaponMacro(k)
    local default, own = self:WeaponMacroSource(k)
    if not default then return end
    if not win then Build() end
    Rogue.WeaponMacroEditor.window = win
    key = k
    nameText:SetText(self:WeaponMacroName(k) or k)
    if not placed then UI.PlaceDialog(win) placed = true end
    win:Show()
    win:Raise()
    Load(own or default)
    area.edit:SetFocus()
end

function Rogue.WeaponMacroEditor.Hide() if win then win:Hide() end end
function Rogue.WeaponMacroEditor.IsShown() return win and win:IsShown() or false end
