-- ---------------------------------------------------------------------------
-- UI: the color swatch.
-- ---------------------------------------------------------------------------
local _, ns = ...
local T, Skin, Text, UI = ns.T, ns.Skin, ns.Text, ns.UI

-- ---------------------------------------------------------------------------
-- Color swatch: shows a color; a click opens a small popover with the theme's
-- palette, "Default" and (where the game has one) its full color picker.
-- get() -> color or nil (= default), set(color or nil); fallback = the default
-- ---------------------------------------------------------------------------
do
    local pop = CreateFrame("Frame", "BeautifulRogueColorPopover", UIParent)
    pop:SetFrameStrata("TOOLTIP")
    pop:EnableMouse(true)
    pop:Hide()
    Skin(pop, T.popover)
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints()
    catcher:SetFrameStrata("DIALOG")
    catcher:Hide()
    local function Close() pop:Hide() catcher:Hide() end
    catcher:SetScript("OnClick", Close)
    UI.CloseColorPopover = Close

    local EXTRA = { { 1, 1, 1 }, { 0.62, 0.65, 0.70 }, { 0.22, 0.80, 0.45 }, { 1.00, 0.80, 0.22 },
                    { 0.25, 0.50, 1.00 }, { 0.92, 0.24, 0.30 } }
    local SW, GAP, COLS = 20, 6, 8
    pop.cells = {}
    local current
    local function Cell(i)
        local c = pop.cells[i]
        if c then return c end
        c = CreateFrame("Button", nil, pop)
        c:SetSize(SW, SW)
        Skin(c, { 1, 1, 1, 1 }, T.line)
        c.hl = c:CreateTexture(nil, "HIGHLIGHT")
        c.hl:SetAllPoints()
        c.hl:SetColorTexture(1, 1, 1, 0.25)
        c:SetScript("OnClick", function(self)
            current.set({ self.color[1], self.color[2], self.color[3] })
            Close()
        end)
        pop.cells[i] = c
        return c
    end
    pop.title = Text(pop, 11)
    pop.title:SetPoint("TOPLEFT", 10, -8)
    ns.Color(pop.title, T.muted)
    pop.more = UI.Button(pop, 10, ns.L["More colors ..."], function()
        local cur = current.get() or current.fallback
        if type(cur) == "function" then cur = cur() end
        local set = current.set
        Close()
        local before = { cur[1], cur[2], cur[3] }
        local function Changed()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            set({ r, g, b })
        end
        if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({ r = cur[1], g = cur[2], b = cur[3], hasOpacity = false,
                swatchFunc = Changed, cancelFunc = function() set(before) end })
        elseif ColorPickerFrame then
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.func = Changed
            ColorPickerFrame.cancelFunc = function() set(before) end
            ColorPickerFrame:SetColorRGB(cur[1], cur[2], cur[3])
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end, 20)
    pop.default = UI.Button(pop, 10, ns.L["Default"], function()
        current.set(nil)
        Close()
    end, 20)

    local function Open(anchor, spec)
        current = spec
        pop.title:SetText(spec.title or ns.L["Color"])
        local colors = {}
        for i = 1, #T.tags do colors[#colors + 1] = T.tags[i] end
        for _, c in ipairs(EXTRA) do colors[#colors + 1] = c end
        for i, col in ipairs(colors) do
            local c = Cell(i)
            local row, column = math.floor((i - 1) / COLS), (i - 1) % COLS
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 10 + column * (SW + GAP), -26 - row * (SW + GAP))
            c.color = col
            ns.SetFill(c, { col[1], col[2], col[3], 1 })
            c:Show()
        end
        local rows = math.ceil(#colors / COLS)
        local width = 20 + COLS * SW + (COLS - 1) * GAP
        local y = -26 - rows * (SW + GAP) - 4
        local hasPicker = ColorPickerFrame ~= nil
        pop.default:ClearAllPoints()
        pop.default:SetPoint("TOPLEFT", 10, y)
        pop.default:SetWidth(hasPicker and 70 or (width - 20))
        pop.more:SetShown(hasPicker)
        pop.more:ClearAllPoints()
        pop.more:SetPoint("TOPRIGHT", -10, y)
        pop.more:SetWidth(width - 20 - 76)
        pop:SetSize(width, -y + 30)
        -- open towards the middle of the screen
        pop:ClearAllPoints()
        local x = anchor:GetCenter()
        if x and x > UIParent:GetWidth() / 2 then
            pop:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
        else
            pop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        end
        catcher:Show()
        pop:Show()
    end
    UI.OpenColorPopover = Open

    function UI.ColorSwatch(parent, title, get, set, fallback)
        local b = CreateFrame("Button", nil, parent)
        b.isSwatch = true
        b:SetSize(46, 20)
        Skin(b, { 1, 1, 1, 1 }, T.input)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.15)
        local spec = { title = title, get = get, fallback = fallback }
        spec.set = function(c)
            set(c)
            b:Refresh()
        end
        b:SetScript("OnClick", function(self) Open(self, spec) end)
        function b:Refresh()
            local c = get() or (type(fallback) == "function" and fallback() or fallback)
            ns.SetFill(self, { c[1], c[2], c[3], 1 })
        end
        b:Refresh()
        return b
    end
end
