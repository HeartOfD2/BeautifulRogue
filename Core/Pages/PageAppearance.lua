-- ---------------------------------------------------------------------------
-- Settings page "Appearance" (Addon section): how BeautifulRogue itself looks. Dark or light
-- mode and accent color, the font and the minimap button. All of it is account-wide.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, UI, App = ns.L, ns.T, ns.UI, ns.App

local appearancePage   -- set at the end of the file; filled in while building

local function BuildAppearance(p)
    local COLW = 400

    -- colors --------------------------------------------------------------------
    UI.Label(p, L["COLORS"], 0, 0)
    local modeBtns, accentBtns = {}, {}
    local function RefreshColors()
        local th = ns.ThemeSettings()
        for key, b in pairs(modeBtns) do
            b:SetAccent(th.mode == key)
            ns.SetColor(b.text, th.mode == key and T.accent or T.text)
        end
        for key, b in pairs(accentBtns) do
            b:SetAccent(th.accent == key)
            ns.SetColor(b.text, th.accent == key and T.accent or T.text)
        end
    end
    for i, key in ipairs(ns.THEME_MODES) do
        local b = UI.Button(p, 122, key == "dark" and L["Dark"] or L["Light"], function()
            ns.SetTheme(key, nil)
            RefreshColors()
        end)
        b:SetPoint("TOPLEFT", (i - 1) * 128, -18)
        modeBtns[key] = b
    end
    local ACCENT_LABEL = { teal = L["Teal"], amber = L["Amber"], blue = L["Blue"] }
    for i, key in ipairs(ns.THEME_ACCENTS) do
        local b = UI.Button(p, 80, ACCENT_LABEL[key], function()
            ns.SetTheme(nil, key)
            RefreshColors()
        end)
        b:SetPoint("TOPLEFT", (i - 1) * 86, -46)
        b.text:ClearAllPoints()
        b.text:SetPoint("CENTER", 6, 0)
        b.swatch = b:CreateTexture(nil, "ARTWORK")
        b.swatch:SetSize(8, 8)
        b.swatch:SetPoint("RIGHT", b.text, "LEFT", -5, 0)
        local c = ns.ACCENT_SAMPLES[key]
        b.swatch:SetColorTexture(c[1], c[2], c[3], 1)
        accentBtns[key] = b
    end
    local themeHint = UI.Hint(p, L["The combat frame keeps its dark tiles in both modes; the accent color applies everywhere."], COLW)
    themeHint:SetPoint("TOPLEFT", 0, -74)

    -- font ------------------------------------------------------------------------
    UI.Label(p, L["FONT"], 0, -118)
    local fontBox = UI.Dropdown(p, function()
        return ns.FontsFor("global")   -- full coverage and meant for text
    end, ns.FontChoice, function(key)
        if key == ns.FontChoice() then return end
        ns.SetFontChoice(key)
        -- the font only changes on a fresh load: offer the reload right away. ReloadUI is
        -- protected: it only runs as the click handler itself (4th entry = direct), not
        -- when called from our own function.
        UI.MessageBox(L["Font changed"], L["The new font applies after a reload. Reload the interface now?"],
            { { L["Later"] }, { L["Reload now"], ReloadUI, true, true } })
    end, 200)
    fontBox:SetPoint("TOPLEFT", 0, -136)
    local fontHint = UI.Hint(p, L["Applies to all BeautifulRogue texts after /reload."], COLW)
    fontHint:SetPoint("TOPLEFT", 0, -164)

    -- minimap button -----------------------------------------------------------------
    UI.Label(p, L["MINIMAP"], 0, -204)
    local mmRow = UI.CheckRow(p, L["Minimap button"],
        function() return ns.IsMinimapButtonShown() end,
        function(v) ns.SetMinimapButtonShown(v) end)
    mmRow:SetPoint("TOPLEFT", 0, -222)
    local mmHint = UI.Hint(p, ns.MinimapHint(), COLW)
    mmHint:SetPoint("TOPLEFT", 0, -246)

    appearancePage.Refresh = function()
        RefreshColors()
        fontBox:Refresh()
        mmRow:Refresh()
        mmHint:SetText(ns.MinimapHint())
    end
end

appearancePage = App:AddPage({
    key = "appearance", section = "addon", label = L["Appearance"], order = 920,
    Build = function(_, frame) BuildAppearance(frame) end,
})
