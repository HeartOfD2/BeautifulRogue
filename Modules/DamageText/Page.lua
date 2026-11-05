-- ---------------------------------------------------------------------------
-- The "Damage numbers" page (EXTRAS section): two blocks, both on by default.
--   floating numbers   font, size, gravity, duration of the numbers above the heads
--   scrolling text     font, outline, monochrome, shadow of the game's combat text fonts
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, UI = ns.L, ns.UI
local DT = ns.DamageText

local W = 280
local widgets = {}

-- every catalog font; one without the letters of the client language is marked
local function FontItems()
    local items = {}
    for _, it in ipairs(ns.FontsFor("all")) do
        local name = it[2]
        if not DT.FontSuits(it[1]) then name = name .. " " .. L["[Latin]"] end
        items[#items + 1] = { it[1], name, font = DT.FontFile(it[1]) }
    end
    return items
end

-- two columns side by side so the page fits the window without scrolling
local COL2 = 305

-- a sample in the chosen font beside the list (a font name alone says nothing)
local function Preview(frame, key)
    local box = CreateFrame("Frame", nil, frame)
    box:SetSize(W - 208, 30)
    ns.Skin(box, ns.T.hudTrack, ns.T.hudLine)
    local fs = box:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    fs:SetTextColor(1, 0.82, 0.1)
    local sample = BreakUpLargeNumbers and BreakUpLargeNumbers(12345) or "12345"
    function box:Refresh()
        -- FontFile only returns a file the client loads
        local path = DT.FontFile(DT:Get(key)) or ns.FONT_DEFAULT or STANDARD_TEXT_FONT
        UI.ShowInFont(fs, path, 18, "OUTLINE", sample)
    end
    return box
end

local function Build(frame)
    local function Put(w, x, y)
        w:SetPoint("TOPLEFT", x, y)
        widgets[#widgets + 1] = w
        return w
    end
    local function Hint(text, x, y, width)
        local h = UI.Hint(frame, text, width or 600)
        h:SetPoint("TOPLEFT", x, y)
        return h
    end
    local function Slider(label, key, x, y, fmt)
        local r = DT.RANGES[key]
        Put(UI.ValueSlider(frame, label, r[1], r[2], r[3],
            function() return DT:Get(key) end, function(v) DT:Set(key, v) end, W, fmt), x, y)
    end

    Hint(L["The combat numbers themselves are switched on in the game options. BeautifulRogue does not change that option."], 0, 0)

    -- floating numbers (left) --------------------------------------------------
    UI.Label(frame, L["FLOATING NUMBERS"], 0, -36)
    Put(UI.CheckRow(frame, L["Change the numbers above the heads"],
        function() return DT:Get("worldOn") end, function(v) DT:Set("worldOn", v) end, W), 0, -56)
    local worldPreview = Put(Preview(frame, "worldFont"), 208, -84)
    Put(UI.Dropdown(frame, FontItems, function() return DT:Get("worldFont") end,
        function(v)
            DT:Set("worldFont", v)
            worldPreview:Refresh()
            -- the client reads the world font only at login: say so where the eye is
            ns.App.Status(L["Saved. The numbers above the heads switch after logging out and in again."], true)
        end, 200), 0, -88)
    Slider(L["Size"], "worldScale", 0, -126, "%.1f")
    Slider(L["Gravity"], "worldGravity", 0, -166, "%.1f")
    Slider(L["Duration"], "worldDuration", 0, -206, "%.2f")
    Hint(L["A new font applies after logging out and in again (/reload is not enough). Size, gravity and duration apply at once."], 0, -250, W)

    -- scrolling combat text (right) -------------------------------------------------
    UI.Label(frame, L["SCROLLING COMBAT TEXT"], COL2, -36)
    Put(UI.CheckRow(frame, L["Change the font of the scrolling combat text"],
        function() return DT:Get("sctOn") end, function(v) DT:Set("sctOn", v) end, W), COL2, -56)
    local sctPreview = Put(Preview(frame, "sctFont"), COL2 + 208, -84)
    Put(UI.Dropdown(frame, FontItems, function() return DT:Get("sctFont") end,
        function(v) DT:Set("sctFont", v) sctPreview:Refresh() end, 200), COL2, -88)
    UI.Label(frame, L["OUTLINE"], COL2, -126)
    Put(UI.Segmented(frame, {
        { "none", L["None"] }, { "thin", L["Thin"] }, { "thick", L["Thick"] },
    }, function() return DT:Get("sctOutline") end, function(v) DT:Set("sctOutline", v) end, W), COL2, -146)
    Put(UI.CheckRow(frame, L["Monochrome (no smoothing)"],
        function() return DT:Get("sctMono") end, function(v) DT:Set("sctMono", v) end, W), COL2, -178)
    Slider(L["Shadow distance"], "sctShadow", COL2, -214, "%d")

    -- back to the defaults: both blocks on, the game's own values
    local reset = UI.ConfirmButton(frame, 180, L["Reset to default"], function()
        ns.ResetCategories({ damagetext = true })
        for _, w in ipairs(widgets) do w:Refresh() end
    end, 22)
    reset:SetPoint("TOPLEFT", 0, -310)
    UI.Tooltip(reset, { L["Reset to default"], L["Both blocks go back to their defaults and the game's own values; a changed world font needs a new login."] })
end

DT:Page({
    key = "damageText", section = "extras", label = L["Damage numbers"], order = 230,
    Build = function(_, frame)
        Build(frame)
        for _, w in ipairs(widgets) do w:Refresh() end
    end,
    Refresh = function()
        for _, w in ipairs(widgets) do w:Refresh() end
    end,
})
