-- ---------------------------------------------------------------------------
-- UI: the message box.
-- ---------------------------------------------------------------------------
local _, ns = ...
local T, Skin, Text, UI = ns.T, ns.Skin, ns.Text, ns.UI

-- ---------------------------------------------------------------------------
-- Message box. Deliberately not a Blizzard StaticPopup: the poison macros
-- click StaticPopup1 to confirm "replace enchantment?".
-- buttons = { { label, fn, primary, direct }, ... } up to three, right-aligned.
-- direct = true: fn is hooked up as the button's click handler itself, without
-- our wrapper. A protected function (ReloadUI) is blocked when our own code calls
-- it, but runs when the game's function is the handler.
-- ---------------------------------------------------------------------------
do
    local box = CreateFrame("Frame", "BeautifulRogueMessageBox", UIParent)
    box:SetSize(400, 190)
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    box:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the app window (DIALOG)
    box:EnableMouse(true)
    box:SetMovable(true)
    box:SetClampedToScreen(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", function(self) self:StartMoving() end)
    box:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    box:Hide()
    Skin(box, T.popover)
    local strip = box:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT")
    strip:SetPoint("TOPRIGHT")
    strip:SetHeight(2)
    ns.Color(strip, T.accent)
    table.insert(UISpecialFrames, "BeautifulRogueMessageBox")
    box.title = Text(box, 14)
    box.title:SetPoint("TOPLEFT", 16, -14)
    ns.Color(box.title, T.accent)
    box.text = Text(box, 12)
    box.text:SetPoint("TOPLEFT", 16, -38)
    box.text:SetPoint("BOTTOMRIGHT", -16, 44)
    box.text:SetJustifyH("LEFT")
    box.text:SetJustifyV("TOP")
    box.buttons = {}
    for i = 1, 3 do
        local function Wrapped(self)
            box:Hide()
            if self.fn then self.fn() end
        end
        local b = UI.Button(box, 118, "", Wrapped, 22)
        b.wrapped = Wrapped
        b:SetPoint("BOTTOMRIGHT", -16 - (3 - i) * 124, 14)
        box.buttons[i] = b
    end
    -- optional text field (UI.Prompt)
    box.input = UI.LineEdit(box, 13, 40)
    box.input:SetPoint("BOTTOMLEFT", 16, 48)
    box.input:SetPoint("BOTTOMRIGHT", -16, 48)
    box.input:SetHeight(24)
    box.input:Hide()
    function UI.MessageBox(title, text, buttons)
        UI.PlaceDialog(box)
        box.input:Hide()
        box.input:ClearFocus()
        box.text:SetPoint("BOTTOMRIGHT", -16, 44)
        box.title:SetText(title)
        box.text:SetText(text)
        for i, b in ipairs(box.buttons) do
            local spec = buttons[#buttons - 3 + i]
            if spec then
                b.text:SetText(spec[1])
                b.fn = spec[2]
                b:SetScript("OnClick", spec[4] and spec[2] or b.wrapped)
                b:SetAccent(spec[3])
                b:Show()
            else
                b:Hide()
            end
        end
        box:Show()
    end
    -- asks for one line of text; onOK(text) gets it trimmed (not called when empty)
    function UI.Prompt(title, text, default, onOK, okLabel)
        local function OK()
            local v = ns.Trim(box.input:GetText())
            box:Hide()
            if v ~= "" then onOK(v) end
        end
        UI.MessageBox(title, text, { { ns.L["Cancel"] }, { okLabel or ns.L["OK"], OK, true } })
        box.text:SetPoint("BOTTOMRIGHT", -16, 80)
        box.input:SetText(default or "")
        box.input:Show()
        box.input:SetFocus()
        box.input:HighlightText()
        box.input:SetScript("OnEnterPressed", OK)
        box.input:SetScript("OnEscapePressed", function() box:Hide() end)
    end
    UI.messageBox = box
end
