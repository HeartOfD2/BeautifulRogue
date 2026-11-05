-- ---------------------------------------------------------------------------
-- UI: the dropdown menu.
-- ---------------------------------------------------------------------------
local _, ns = ...
local T, Skin, Text, UI = ns.T, ns.Skin, ns.Text, ns.UI

-- ---------------------------------------------------------------------------
-- Dropdown menu (one shared instance). items = { { label, fn, checked, icon,
-- isTitle, divider, font } } (font: a file path, hovering shows a sample in it). A full-screen catcher closes it on any outside click.
-- ---------------------------------------------------------------------------
do
    local ROW_H, PAD = 20, 4
    local menu = CreateFrame("Frame", "BeautifulRogueMenu", UIParent)
    menu:SetFrameStrata("TOOLTIP")
    menu:EnableMouse(true)
    menu:Hide()
    Skin(menu, T.popover)
    menu.rows = {}
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints()
    catcher:SetFrameStrata("DIALOG")
    catcher:Hide()
    -- font preview: an entry with a font file shows its name in that font beside the menu
    local preview = CreateFrame("Frame", nil, menu)
    preview:SetFrameStrata("TOOLTIP")
    preview:SetSize(240, 52)
    preview:SetClampedToScreen(true)
    Skin(preview, T.popover)
    preview.text = preview:CreateFontString(nil, "OVERLAY")
    preview.text:SetPoint("LEFT", 10, 0)
    preview.text:SetPoint("RIGHT", -10, 0)
    preview.text:SetWordWrap(false)
    ns.SetColor(preview.text, T.text)
    preview:Hide()
    local SAMPLE = BreakUpLargeNumbers and BreakUpLargeNumbers(12345) or "12345"
    local function ShowPreview(row, it)
        preview:ClearAllPoints()
        preview:SetPoint("TOPLEFT", row, "TOPRIGHT", PAD + 6, 16)
        UI.ShowInFont(preview.text, it.font, 20, "", it.label .. "   " .. SAMPLE)
        preview:Show()
    end

    local function Close() preview:Hide() menu:Hide() catcher:Hide() end
    catcher:SetScript("OnClick", Close)
    UI.CloseMenu = Close
    UI.menu = menu

    local function Row(i)
        local r = menu.rows[i]
        if r then return r end
        r = CreateFrame("Button", nil, menu)
        r:SetHeight(ROW_H)
        r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.sel:SetAllPoints()
        ns.Color(r.sel, T.accentSoft)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetPoint("TOPLEFT")
        r.mark:SetPoint("BOTTOMLEFT")
        r.mark:SetWidth(2)
        ns.Color(r.mark, T.accent)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(14, 14)
        r.icon:SetPoint("LEFT", 8, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = Text(r, 12)
        r.text:SetJustifyH("LEFT")
        r.desc = Text(r, 11)
        r.desc:SetPoint("RIGHT", -8, 0)
        ns.Color(r.desc, T.muted)
        r.div = r:CreateTexture(nil, "ARTWORK")
        r.div:SetPoint("TOPLEFT")
        r.div:SetPoint("TOPRIGHT")
        r.div:SetHeight(1)
        ns.Color(r.div, T.divider)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        ns.Color(r.hl, T.hover)
        menu.rows[i] = r
        return r
    end

    -- opts.point/relPoint/x/y place it next to the anchor; opts.width
    function UI.OpenMenu(anchor, items, opts)
        opts = opts or {}
        if menu:IsShown() and menu.anchor == anchor then Close() return end
        local anyIcon = false
        for _, it in ipairs(items) do if it.icon then anyIcon = true end end
        for i, it in ipairs(items) do
            local r = Row(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", -PAD, -PAD - (i - 1) * ROW_H)
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT", anyIcon and 28 or 10, 0)
            if it.isTitle then
                r.text:SetText(ns.Muted(it.label))
                r:EnableMouse(false)
                r:SetScript("OnClick", nil)
                r:SetScript("OnEnter", nil)
                r:SetScript("OnLeave", nil)
            else
                r.text:SetText(it.label)
                r:EnableMouse(true)
                r:SetScript("OnClick", function() Close() if it.fn then it.fn() end end)
                if it.font then
                    r:SetScript("OnEnter", function(self) ShowPreview(self, it) end)
                    r:SetScript("OnLeave", function() preview:Hide() end)
                elseif it.tooltip then UI.Tooltip(r, it.tooltip) else
                    r:SetScript("OnEnter", nil)
                    r:SetScript("OnLeave", nil)
                end
            end
            r.icon:SetShown(it.icon ~= nil)
            if it.icon then r.icon:SetTexture(it.icon) end
            r.desc:SetText(it.desc or "")
            r.sel:SetShown(it.checked and true or false)
            r.mark:SetShown(it.checked and true or false)
            r.div:SetShown(it.divider and true or false)
            r:Show()
        end
        for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
        menu:SetSize(opts.width or 190, PAD * 2 + #items * ROW_H)
        menu:ClearAllPoints()
        menu:SetPoint(opts.point or "TOPRIGHT", anchor, opts.relPoint or "BOTTOMRIGHT", opts.x or 0, opts.y or -4)
        menu.anchor = anchor
        catcher:Show()
        menu:Show()
    end
end
