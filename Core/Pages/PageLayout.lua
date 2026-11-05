-- ---------------------------------------------------------------------------
-- Layout: the parts of the frame on the left (show, order, pick one), the
-- look of the picked part on the right. Every change shows on the frame at
-- once; while this page is open the frame stays visible out of combat.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, UI, HUD, App = ns.L, ns.T, ns.UI, ns.HUD, ns.App

local layoutPage   -- set at the end of the file; filled in while building
local PRESETS = { "{cur}", "{cur} / {max}", "{cur} / {max} ({pct}%)", "{pct}%", "-{deficit}" }
local LIST_W, ROW_H = 232, 26
local VIEW_ROWS = 11   -- parts shown at once below the "Frame" row; more scroll
local INS_X = LIST_W + 20
local INS_W = App.CONTENT_W - INS_X - 12   -- room for the scroll bar

-- a style field as get/set pair; set skips unchanged values (sliders call often)
local function StyleField(key, field)
    return function() return HUD:Get(key, field) end,
        function(v)
            if HUD:Get(key, field) == v then return end
            HUD:Set(key, field, v)
            if HUD:IsLayoutPending() then App.Status(L["In combat: the frame updates when combat ends."], true) end
        end
end

local function BuildLayout(p)
    HUD:SetPreview(true)
    layoutPage.OnHide = function() HUD:SetPreview(false) end
    local selected = "frame"
    local panels, rows = {}, {}
    local Select
    local scroll = 0                  -- parts scrolled off the top of the list
    local armed = { bar = nil, untilT = 0 }   -- the cooldown bar whose × was clicked once

    -- ---------------------------------------------------------------- list
    UI.Label(p, L["PARTS, TOP TO BOTTOM"], 0, 0)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", 0, -18)
    list:SetSize(LIST_W, 8 + (VIEW_ROWS + 1) * ROW_H)
    list:EnableMouseWheel(true)
    ns.Skin(list, T.panel, T.line)

    local function RemoveBar(bar)
        ns.Cooldowns:RemoveBar(bar)
        App.Status(L["Cooldown bar %d removed."]:format(bar))
        layoutPage.Refresh()
        if HUD:IsLayoutPending() then App.Status(L["In combat: the frame updates when combat ends."], true) end
    end

    local function PaintRow(row)
        local on = row.key == selected
        row.bg:SetShown(on)
        row.bar:SetShown(on)
    end
    local function Row(i)   -- 0 = the frame itself
        if rows[i] then return rows[i] end
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H - 2)
        row:SetPoint("TOPLEFT", 4, -4 - i * ROW_H)
        row:SetPoint("TOPRIGHT", -12, -4 - i * ROW_H)   -- (room for the scroll bar)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        ns.Color(row.bg, T.accentSoft)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetPoint("TOPLEFT")
        row.bar:SetPoint("BOTTOMLEFT")
        row.bar:SetWidth(2)
        ns.Color(row.bar, T.accent)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        ns.Color(row.hl, T.hover)
        row.label = ns.Text(row, 12)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.hint = ns.Text(row, 11)
        ns.Color(row.hint, T.muted)
        if i == 0 then
            row.label:SetPoint("LEFT", 10, 0)
            row.hint:SetPoint("RIGHT", -8, 0)
        else
            local check = UI.Check(row)
            check:SetPoint("LEFT", 8, 0)
            check:SetScript("OnClick", function()
                HUD:SetHidden(row.key, not HUD:IsHidden(row.key))
                layoutPage.Refresh()
                if HUD:IsLayoutPending() then App.Status(L["In combat: the frame updates when combat ends."], true) end
            end)
            row.check = check
            row.label:SetPoint("LEFT", 30, 0)
            -- drag the grip up or down to move the part; the list scrolls when the pointer leaves it
            row.grip = UI.DragHandle(row, {
                key = function() return row.key ~= "frame" and row.key or nil end,
                indexOf = function(key) return ns.IndexOf(HUD:VisibleOrder(), key) end,
                targetAt = function()
                    local top = list:GetTop()
                    if not top then return end
                    local slot = math.floor((top - 4 - UI.CursorY(list)) / ROW_H)   -- 0 = the Frame row
                    slot = math.max(1, math.min(VIEW_ROWS, slot))
                    return math.min(#HUD:VisibleOrder(), scroll + slot)
                end,
                move = function(key, dir) HUD:Move(key, dir) layoutPage.Refresh() end,
                edge = function()
                    local top = list:GetTop()
                    local now = GetTime()
                    if not top or now < (list.scrollAt or 0) then return end
                    local y = UI.CursorY(list)
                    local first = top - 4 - ROW_H           -- top of the first part row
                    local last = first - VIEW_ROWS * ROW_H  -- bottom of the last one
                    local before = scroll
                    if y > first then scroll = scroll - 1 elseif y < last then scroll = scroll + 1 end
                    if scroll ~= before then
                        list.scrollAt = now + 0.12
                        layoutPage.Refresh()
                    end
                end,
                start = function(key) Select(key) end,
                done = function() layoutPage.Refresh() end,
                ghost = function(key) return HUD.byKey[key] and HUD.byKey[key].label or "" end,
            })
            row.grip:SetPoint("RIGHT", -2, 0)
            -- cooldown bars: × takes the bar away (click twice, like the reset buttons)
            row.remove = UI.Button(row, 18, "×", function()
                local bar = HUD.byKey[row.key] and HUD.byKey[row.key].cooldownBar
                if not bar then return end
                if armed.bar == bar and GetTime() < armed.untilT then
                    armed.bar = nil
                    RemoveBar(bar)
                    return
                end
                armed.bar, armed.untilT = bar, GetTime() + 3
                layoutPage.Refresh()
                C_Timer.After(3.05, function() if p:IsShown() then layoutPage.Refresh() end end)
            end, 18)
            row.remove:SetPoint("RIGHT", -2, 0)
            UI.Tooltip(row.remove, { L["Remove this cooldown bar"],
                L["Click twice. Its cooldowns move to the neighbour bar; the bars behind it move up."] })
            row.hint:SetPoint("RIGHT", row.grip, "LEFT", -6, 0)
        end
        row.label:SetPoint("RIGHT", row.hint, "LEFT", -6, 0)
        row:SetScript("OnClick", function(self) Select(self.key) end)
        rows[i] = row
        return row
    end

    local addBar = UI.Button(p, LIST_W, "+ " .. L["Cooldown bar"], function()
        local n, why = ns.Cooldowns:AddBar()
        if not n then App.Status(why, true) return end
        selected = "cd" .. n
        local order = HUD:VisibleOrder()   -- show the new bar: scroll to it
        scroll = math.max(0, #order - VIEW_ROWS)
        layoutPage.Refresh()
        if HUD:IsLayoutPending() then App.Status(L["In combat: the frame updates when combat ends."], true) end
    end, 22)
    addBar:SetPoint("BOTTOMLEFT", 0, 28)
    UI.Tooltip(addBar, function()
        return { L["Cooldown bar"], L["Up to %d cooldown bars."]:format(ns.Cooldowns.BARS) }
    end)

    local resetAll = UI.ConfirmButton(p, 130, L["Reset layout"], function()
        ns.ResetCategories({ layout = true })
        App.Status(L["Layout reset."])
    end)
    resetAll:SetPoint("BOTTOMLEFT", 0, 0)
    UI.Tooltip(resetAll, { L["Reset layout"], L["Order, visibility and look of the frame parts."] })

    -- ---------------------------------------------------------------- inspector
    local divider = p:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", INS_X - 10, 0)
    divider:SetPoint("BOTTOMLEFT", INS_X - 10, 0)
    divider:SetWidth(1)
    ns.Color(divider, T.divider)

    local function Panel(key, title, sub)
        -- scrolls when the content is taller than the space above the reset button
        -- 2 px inside the clip edge: the controls' outlines stay visible
        local sf = UI.ScrollArea(p, 2)
        sf:SetPoint("TOPLEFT", INS_X - 2, 2)
        sf:SetPoint("BOTTOMRIGHT", -10, 30)
        sf.bar:ClearAllPoints()   -- the bar sits beside the content, not over it
        sf.bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
        sf.bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
        sf:Hide()
        local panel = sf.child
        panel.sf = sf
        panel.widgets = {}
        panel.title = ns.Text(panel, 15)
        panel.title:SetPoint("TOPLEFT", 0, 0)
        panel.title:SetText(title)
        panel.sub = UI.Hint(panel, sub or "", INS_W)
        panel.sub:SetPoint("TOPLEFT", 0, -20)
        if sub then
            -- a long subtitle wraps (German: up to three lines); measure it
            local h = panel.sub:GetStringHeight() or 0
            if h <= 0 then h = 13 * math.ceil(#sub * 6 / INS_W) end   -- no font metrics yet
            panel.y = -20 - math.max(h, 13) - 9
        else
            panel.y = -28
        end
        panels[key] = panel
        return panel
    end
    local function Put(panel, w, h, x)
        w:SetPoint("TOPLEFT", x or 0, panel.y)
        panel.y = panel.y - h
        if w.Refresh then panel.widgets[#panel.widgets + 1] = w end
        return w
    end
    local function Section(panel, text)
        panel.y = panel.y - 6
        UI.Label(panel, text, 0, panel.y)
        panel.y = panel.y - 18
    end
    local function Slider(panel, key, field, label, minV, maxV, fmt)
        local get, set = StyleField(key, field)
        return Put(panel, UI.ValueSlider(panel, label, minV, maxV, 1, get, set, INS_W, fmt or "%d px"), 38)
    end
    local function Check(panel, key, field, label, tip)
        local get, set = StyleField(key, field)
        local row = UI.CheckRow(panel, label, function() return get() ~= false end,
            function(v) set(v and true or false) end, INS_W)
        if tip then UI.Tooltip(row, { label, tip }) end
        return Put(panel, row, 24)
    end
    -- the part's colored edge (color: Frame); key may be a function (cooldown bars)
    local function EdgeCheck(panel, key)
        local function k() return type(key) == "function" and key() or key end
        local row = UI.CheckRow(panel, L["Colored edge"], function() return HUD:EdgeOn(k()) end,
            function(v) HUD:Set(k(), "edge", v and true or nil) end, INS_W)
        UI.Tooltip(row, { L["Colored edge"], L["A 1 px line in the edge color around this part. The color and a switch for all parts: Frame."] })
        return Put(panel, row, 24)
    end
    -- bar color: own / class / custom, the swatch shows what the bar uses
    local function ColorRow(panel, key, ownLabel, ownColor)
        Section(panel, L["COLOR"])
        local seg, swatch
        seg = UI.Segmented(panel, {
            { "default", ownLabel }, { "class", L["Class color"] }, { "custom", L["Custom"] },
        }, function() return HUD:Get(key, "colorMode") or "default" end,
        function(v)
            if v == "custom" and not HUD:Get(key, "color") then
                local c = ns.StyleColor(key, ownColor())
                HUD:Set(key, "color", { c[1], c[2], c[3] })
            end
            HUD:Set(key, "colorMode", v)
            swatch:Refresh()
        end, INS_W)
        Put(panel, seg, 28)
        local text = ns.Text(panel, 12)
        text:SetPoint("TOPLEFT", 0, panel.y - 3)
        text:SetText(L["Bar color"])
        swatch = UI.ColorSwatch(panel, L["Bar color"],
            function() return ns.StyleColor(key, ownColor()) end,
            function(c)
                if c then
                    HUD:Set(key, "color", c)
                    HUD:Set(key, "colorMode", "custom")
                else
                    HUD:Set(key, "color", nil)
                    HUD:Set(key, "colorMode", "default")
                end
                seg:Refresh()
            end, ownColor)
        swatch:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, panel.y)
        panel.widgets[#panel.widgets + 1] = swatch
        panel.y = panel.y - 26
    end
    -- a labelled color swatch (nil = the default color)
    local function SwatchRow(panel, key, field, label, default)
        local text = ns.Text(panel, 12)
        text:SetPoint("TOPLEFT", 0, panel.y - 3)
        text:SetText(label)
        local get, set = StyleField(key, field)
        local sw = UI.ColorSwatch(panel, label, get, set, default)
        sw:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, panel.y)
        panel.widgets[#panel.widgets + 1] = sw
        panel.y = panel.y - 26
    end
    -- a labelled listbox for a style field
    local function DropRow(panel, key, field, label, items, fallback)
        local text = ns.Text(panel, 12)
        text:SetPoint("TOPLEFT", 0, panel.y - 4)
        text:SetText(label)
        local get, set = StyleField(key, field)
        local dd = UI.Dropdown(panel, items, function() return get() or fallback end, set, 190)
        dd:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, panel.y)
        panel.widgets[#panel.widgets + 1] = dd
        panel.y = panel.y - 28
        return dd
    end
    -- a sound: on/off, then the sound picker (sound + volume). Picking a sound switches it on.
    -- whenItems (optional): a listbox right of the switch that says where the sound may play (field soundWhen)
    local function SoundBlock(panel, key, label, tip, whenItems, whenFallback)
        local onGet, onSet = StyleField(key, "soundOn")
        local row = UI.CheckRow(panel, label, function() return onGet() and true or false end,
            function(v) onSet(v and true or false) end, whenItems and (INS_W - 196) or INS_W)
        UI.Tooltip(row, { label, tip })
        if whenItems then
            local whenGet, whenSet = StyleField(key, "soundWhen")
            local dd = UI.Dropdown(panel, whenItems, function() return whenGet() or whenFallback end, whenSet, 190)
            dd:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, panel.y)
            panel.widgets[#panel.widgets + 1] = dd
        end
        Put(panel, row, 24)
        local nameGet, nameSet = StyleField(key, "sound")
        local volGet, volSet = StyleField(key, "soundVolume")
        local picker = UI.SoundPicker(panel, function() return nameGet(), volGet() end, function(name, vol)
            local picked = name ~= nameGet()
            nameSet(name)
            volSet(vol)
            if picked and not onGet() then
                onSet(true)
                row:Refresh()
            end
        end, INS_W)
        return Put(panel, picker, UI.SOUND_PICKER_H + 4)
    end
    -- text format with presets, size, alignment, on/off
    local function TextBlock(panel, key, field, sample)
        Section(panel, L["TEXT"])
        local box = UI.LineEdit(panel, 13, 60)
        box:SetSize(INS_W - 92, 24)
        Put(panel, box, 0)
        local preview = UI.Hint(panel, "", INS_W)
        local function RefreshPreview()
            preview:SetText(L["Preview:"] .. " " .. ns.FillValueText(ns.Char().text[field] or "{cur}", sample[1], sample[2])
                .. "   " .. ns.Code("{cur} {max} {pct} {deficit}"))
        end
        local function Apply(fmt)
            ns.Char().text[field] = fmt
            RefreshPreview()
            local def = HUD.byKey[key]
            if def.shown then def:Update() end   -- no game event tells the bar
        end
        box:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local v = self:GetText()
            Apply((v ~= "") and v or "{cur}")
        end)
        UI.Tooltip(box, function()
            return { L["Text format"],
                ns.Code("{cur}") .. "  " .. L["current value"],
                ns.Code("{max}") .. "  " .. L["maximum"],
                ns.Code("{pct}") .. "  " .. L["percent, rounded"],
                ns.Code("{deficit}") .. "  " .. L["missing to maximum"],
                L["Any other text stays as typed, e.g. \"HP {cur}\". If the game hides the values in combat, the text falls back to what it still allows."] }
        end)
        local presets
        presets = UI.Button(panel, 86, L["Presets"], function()
            local items = {}
            for _, fmt in ipairs(PRESETS) do
                items[#items + 1] = { label = ns.FillValueText(fmt, sample[1], sample[2]), desc = fmt,
                    checked = ns.Char().text[field] == fmt,
                    fn = function()
                        box:SetText(fmt)
                        Apply(fmt)
                    end }
            end
            UI.OpenMenu(presets, items)
        end, 24)
        presets:SetPoint("LEFT", box, "RIGHT", 6, 0)
        panel.y = panel.y - 28
        Put(panel, preview, 20)
        Slider(panel, key, "textSize", L["Text size"], 8, 20, "%d pt")
        local get, set = StyleField(key, "textAlign")
        local align = UI.Segmented(panel, {
            { "LEFT", L["Left"] }, { "CENTER", L["Center"] }, { "RIGHT", L["Right"] },
        }, function() return get() or "CENTER" end, set, 192)
        Put(panel, align, 0)
        local showGet, showSet = StyleField(key, "showText")
        local show = UI.CheckRow(panel, L["Show text"], function() return showGet() ~= false end,
            function(v) showSet(v and true or false) end, INS_W - 206)
        show:SetPoint("LEFT", align, "RIGHT", 14, 0)
        panel.widgets[#panel.widgets + 1] = show
        panel.y = panel.y - 26
        panel.widgets[#panel.widgets + 1] = { Refresh = function()
            if not box:HasFocus() then box:SetText(ns.Char().text[field] or "{cur}") end
            RefreshPreview()
        end }
    end

    -- frame
    do
        local panel = Panel("frame", L["Frame"], L["Size, spacing, background and edge. Position: HUD › Position & visibility."])
        Put(panel, UI.ValueSlider(panel, L["Width"], 160, 340, 2,
            function() return HUD:FrameGet("width") end,
            function(v) if HUD:FrameGet("width") ~= v then HUD:SetFrame("width", v) end end, INS_W, "%d px"), 38)
        Put(panel, UI.ValueSlider(panel, L["Spacing between parts"], 0, 12, 1,
            function() return HUD:FrameGet("gap") end,
            function(v) if HUD:FrameGet("gap") ~= v then HUD:SetFrame("gap", v) end end, INS_W, "%d px"), 38)
        Section(panel, L["BACKGROUND"])
        local bg = Put(panel, UI.CheckRow(panel, L["Background behind the frame"],
            function() return HUD:FrameGet("backdrop") end,
            function(v) HUD:SetFrame("backdrop", v and true or false) end, INS_W - 58), 0)
        local bgSwatch = UI.ColorSwatch(panel, L["Background color"],
            function() return HUD:FrameGet("backdropColor") end,
            function(c)
                HUD:SetFrame("backdropColor", c)
                if c and not HUD:FrameGet("backdrop") then HUD:SetFrame("backdrop", true) bg:Refresh() end
            end, function() return T.hudBackdrop end)
        bgSwatch:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, panel.y + 1)
        panel.widgets[#panel.widgets + 1] = bgSwatch
        panel.y = panel.y - 26
        Put(panel, UI.ValueSlider(panel, L["Opacity"], 10, 100, 5,
            function() return math.floor(HUD:FrameGet("backdropAlpha") * 100 + 0.5) end,
            function(v) HUD:SetFrame("backdropAlpha", v / 100) end, INS_W, "%d%%"), 38)
        Section(panel, L["EDGE"])
        Put(panel, UI.CheckRow(panel, L["Colored edge on every part"],
            function() return HUD:AllEdges() end,
            function(v) HUD:SetAllEdges(v) end, INS_W - 58), 0)
        local edgeSwatch = UI.ColorSwatch(panel, L["Edge color"],
            function() return HUD:FrameGet("edgeColor") end,
            function(c) HUD:SetFrame("edgeColor", c) end, function() return T.accent end)
        edgeSwatch:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, panel.y + 1)
        panel.widgets[#panel.widgets + 1] = edgeSwatch
        panel.y = panel.y - 26
        Put(panel, UI.Hint(panel, L["A 1 px line around each bar, point, cooldown icon and tile. Switch it per part in the part's settings; this switch turns all on or off."], INS_W), 44)
        panel.y = panel.y - 10
        Put(panel, UI.Hint(panel, L["Tip: the frame stays visible while this page is open, so you can watch every change."], INS_W), 30)
    end

    -- health
    do
        local panel = Panel("health", L["Health"])
        Slider(panel, "health", "height", L["Height"], 10, 36)
        EdgeCheck(panel, "health")
        ColorRow(panel, "health", L["Default"], function() return T.health end)
        TextBlock(panel, "health", "health", { 300, 471 })
        Section(panel, L["LOW HEALTH"])
        Check(panel, "health", "warn", L["Mark the warning zone and pulse below it"])
        Slider(panel, "health", "warnPct", L["Warning below"], 10, 60, "%d%%")
    end

    -- resource
    do
        local panel = Panel("power", L["Resource"], L["Mana, rage or energy: the bar follows your current resource."])
        Slider(panel, "power", "height", L["Height"], 10, 36)
        EdgeCheck(panel, "power")
        ColorRow(panel, "power", L["Resource color"], function()
            local _, token = UnitPowerType("player")
            return ns.PowerColor(token)
        end)
        TextBlock(panel, "power", "power", { 64, 100 })
        -- only for characters that have mana at all (a rogue never does)
        local mana = UnitPowerMax("player", Enum and Enum.PowerType and Enum.PowerType.Mana or 0)
        if ns.IsSecret(mana) or (mana or 0) > 0 then
            Section(panel, L["FIVE-SECOND RULE"])
            Check(panel, "power", "fiveSec", L["Show five-second rule"],
                L["A thin line along the bottom edge that empties in 5 seconds after a spell that costs mana. Mana only."])
            Slider(panel, "power", "fiveSecHeight", L["Line height"], 1, 8, "%d px")
            SwatchRow(panel, "power", "fiveSecColor", L["Color"], function() return T.hudText end)
        end
    end

    -- global cooldown
    do
        local panel = Panel("gcd", L["Global cooldown"], L["A thin bar that lights up while the global cooldown runs. Switch it off with the checkbox in the list."])
        Slider(panel, "gcd", "height", L["Height"], 1, 8)
        EdgeCheck(panel, "gcd")
        do
            local get, set = StyleField("gcd", "clear")
            local row = UI.CheckRow(panel, L["Transparent background"], function() return get() == true end,
                function(v) set(v and true or false) end, INS_W)
            UI.Tooltip(row, { L["Transparent background"], L["Only the lit part stays visible; the dark track behind it is hidden."] })
            Put(panel, row, 24)
        end
        SwatchRow(panel, "gcd", "color", L["Color"], function() return T.accent end)
    end

    -- swing timer
    do
        local panel = Panel("swing", L["Swing timer"], L["Thin bars that fill between your swings and shots. Switch it off with the checkbox in the list."])
        Slider(panel, "swing", "height", L["Height"], 2, 10)
        EdgeCheck(panel, "swing")
        do
            local get, set = StyleField("swing", "clear")
            local row = UI.CheckRow(panel, L["Transparent background"], function() return get() == true end,
                function(v) set(v and true or false) end, INS_W)
            UI.Tooltip(row, { L["Transparent background"], L["Only the filled part stays visible; the dark track behind it is hidden."] })
            Put(panel, row, 24)
        end
        Section(panel, L["BARS"])
        Check(panel, "swing", "main", L["Main hand"])
        Check(panel, "swing", "off", L["Off hand"],
            L["Shows with a weapon in the off hand, or once the game has reported an off-hand swing."])
        Check(panel, "swing", "ranged", L["Ranged"],
            L["Shows with a ranged weapon (bow, gun, crossbow, wand, thrown), or once the game has reported a ranged shot."])
        Section(panel, L["COLOR"])
        SwatchRow(panel, "swing", "colorMain", L["Main hand"], function() return ns.SwingDefaultColor("main") end)
        SwatchRow(panel, "swing", "colorOff", L["Off hand"], function() return ns.SwingDefaultColor("off") end)
        SwatchRow(panel, "swing", "colorRanged", L["Ranged"], function() return ns.SwingDefaultColor("ranged") end)
        Put(panel, UI.Hint(panel, L["A finished bar stays full while you fight with a target, and dims when the target is out of reach."], INS_W), 30)
    end

    -- combo points
    do
        local panel = Panel("combo", L["Combo points"])
        Slider(panel, "combo", "height", L["Height"], 6, 24)
        EdgeCheck(panel, "combo")
        DropRow(panel, "combo", "shape", L["Shape"], {
            { "bars", L["Bars"] }, { "circles", L["Circles"] }, { "diamonds", L["Diamonds"] },
        }, "bars")
        Put(panel, UI.Hint(panel, L["Circles and diamonds take the height as their size."], INS_W), 18)
        Section(panel, L["COLOR"])
        SwatchRow(panel, "combo", "color", L["Filled points"], function() return T.combo end)
        SwatchRow(panel, "combo", "maxColor", L["All points full"], function() return T.comboMax end)
        Section(panel, L["ALL POINTS FULL"])
        local fx = DropRow(panel, "combo", "maxEffect", L["Effect"], {
            { "glow",  L["Glow"],  L["halo breathes"] },
            { "pulse", L["Pulse"], L["points beat"] },
            { "wave",  L["Wave"],  L["light runs across"] },
            { "none",  L["None"],  L["color only"] },
        }, "glow")
        -- a sound when the points fill up
        SoundBlock(panel, "combo", L["Sound"],
            L["Plays once when all combo points are full (not while the game hides them)."])
        local baseRefresh = fx.Refresh
        function fx:Refresh()   -- 1.0 stored "glow off" instead of an effect
            local saved = ns.Char().style.parts.combo
            if saved and saved.maxEffect == nil and saved.glow == false then
                self.text:SetText(L["None"])
            else
                baseRefresh(self)
            end
        end
    end

    -- range
    do
        local panel = Panel("range", L["Range"], L["Distance to your target in bands of your class's abilities."])
        Slider(panel, "range", "height", L["Height"], 12, 28)
        Slider(panel, "range", "textSize", L["Text size"], 8, 16, "%d pt")
        EdgeCheck(panel, "range")
        -- how often the distance is checked (stored per character, not in the style)
        Section(panel, L["RANGE CHECKS"])
        local rateBtns = {}
        local function RefreshRates()
            local cur = ns.Char().range.interval or 0.2
            for i, b in ipairs(rateBtns) do
                local on = math.abs(ns.RANGE_RATES[i][1] - cur) < 1e-3
                b:SetAccent(on)
                b.text:SetTextColor(unpack(on and T.accent or T.text))
            end
        end
        local rateW = (INS_W - 4 * 4) / #ns.RANGE_RATES
        for i, r in ipairs(ns.RANGE_RATES) do
            local b = UI.Button(panel, rateW, r[2], function()
                ns.Char().range.interval = r[1]
                RefreshRates()
            end)
            b:SetPoint("TOPLEFT", (i - 1) * (rateW + 4), panel.y)
            rateBtns[i] = b
        end
        panel.y = panel.y - 26
        Put(panel, UI.Hint(panel, L["Checks per second. 10/s feels instant; fewer saves a little work."], INS_W), 30)
        panel.widgets[#panel.widgets + 1] = { Refresh = RefreshRates }
    end

    -- threat
    do
        local panel = Panel("threat", L["Threat"], L["Your threat on your current target."])
        Slider(panel, "threat", "height", L["Height"], 6, 28)
        EdgeCheck(panel, "threat")
        -- when the bar shows
        local whenGet, whenSet = StyleField("threat", "showWhen")
        local whenText = ns.Text(panel, 12)
        whenText:SetPoint("TOPLEFT", 0, panel.y - 4)
        whenText:SetText(L["Show"])
        local when = UI.Segmented(panel, {
            { "always", L["Always"] }, { "group", L["Only in group/raid"] },
        }, function() return whenGet() or "always" end, whenSet, 260)
        when:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, panel.y)
        panel.widgets[#panel.widgets + 1] = when
        panel.y = panel.y - 30
        ColorRow(panel, "threat", L["By threat"], function() return T.threatLow end)
        Section(panel, L["TEXT"])
        Slider(panel, "threat", "textSize", L["Text size"], 8, 16, "%d pt")
        Check(panel, "threat", "showText", L["Show text"])
        -- a sound when the threat percentage reaches the limit
        Section(panel, L["SOUND"])
        SoundBlock(panel, "threat", L["Sound at"],
            L["Plays once when your threat reaches the limit below. Only while the game shows the threat percentage; when it hides the value, nothing plays."],
            {
                { "always", L["Always"] }, { "group", L["Only in group/raid"] }, { "party", L["Only in a party"] },
                { "raid", L["Only in a raid"] }, { "instance", L["Only in a dungeon or raid instance"] },
            }, "group")
        local atGet, atSet = StyleField("threat", "soundAt")
        Put(panel, UI.ValueSlider(panel, L["Limit"], 10, 100, 5, function() return atGet() or 80 end, atSet, INS_W, "%d%%"), 38)
    end

    -- parts with a fixed look (def.fixedLook, e.g. a module's tiles): only the edge
    for _, def in ipairs(HUD.elements) do
        if def.fixedLook then
            local panel = Panel(def.key, def.label, def.fixedLook)
            EdgeCheck(panel, def.key)
        end
    end

    -- cooldown bars: one shared look
    do
        local panel = Panel("cooldowns", "", L["These settings apply to all cooldown bars."])
        Slider(panel, "cooldowns", "iconSize", L["Icon size"], 20, 40)
        EdgeCheck(panel, function() return selected end)
        Check(panel, "cooldowns", "numbers", L["Countdown numbers on the icons"])
        Check(panel, "cooldowns", "dimReady", L["Dim icons that are ready"],
            L["Only cooldowns that are running stand out."])
        Check(panel, "cooldowns", "desaturate", L["Grey out icons while on cooldown"],
            L["The icon stays grey until the ability is ready again, also in combat."])
        Check(panel, "cooldowns", "readyGlow", L["Highlight icons that are ready"],
            L["An outline in the accent color marks every ability that is ready."])
        Check(panel, "cooldowns", "tint", L["Tint icons by range and usability"],
            L["Red: target out of range. Blue: not enough resource. Grey: cannot be used right now."])
        Check(panel, "cooldowns", "castCount", L["Show the cast count on icons"],
            L["Shows how often the spell can be cast, for example with the reagents you carry."])
        panel.y = panel.y - 8
        local count = Put(panel, UI.Hint(panel, "", INS_W), 36)
        local open = UI.Button(panel, 180, L["Choose cooldowns ›"], function() App:Select("cooldowns") end)
        Put(panel, open, 26)
        panel.widgets[#panel.widgets + 1] = { Refresh = function()
            local bar = HUD.byKey[selected] and HUD.byKey[selected].cooldownBar
            panel.title:SetText(HUD.byKey[selected] and HUD.byKey[selected].label or "")
            if bar then
                count:SetText(L["On this bar: %d cooldowns, %d per row. More wrap into a new row; a second bar takes them instead."]:format(
                    ns.Cooldowns:BarCount(bar), ns.Cooldowns.PerBar()))
            end
        end }
    end

    local scrollBar = UI.ScrollBar(list, function(offset)
        if offset == scroll then return end
        scroll = offset
        layoutPage.Refresh()
    end)
    scrollBar:SetPoint("TOPRIGHT", -3, -ROW_H - 4)
    scrollBar:SetPoint("BOTTOMRIGHT", -3, 4)
    list:SetScript("OnMouseWheel", function(_, delta)
        scroll = scroll - delta
        layoutPage.Refresh()
    end)

    local resetPart = UI.Button(p, 150, L["Default look"], function()
        if HUD.byKey[selected] and HUD.byKey[selected].cooldownBar then
            HUD:ResetStyle("cooldowns")   -- the shared look, and this bar's own edge
        end
        HUD:ResetStyle(selected)
        layoutPage.Refresh()
        App.Status(L["Default look restored."])
    end)
    resetPart:SetPoint("BOTTOMRIGHT", 0, 0)

    local function PanelKey(key)
        local def = HUD.byKey[key]
        if def and def.cooldownBar then return "cooldowns" end
        return key
    end
    function Select(key)
        selected = key
        layoutPage.Refresh()
    end

    layoutPage.Refresh = function()
        HUD:SetPreview(true)
        local order = HUD:VisibleOrder()
        if selected ~= "frame" and not ns.IndexOf(order, selected) then selected = "frame" end
        local frameRow = Row(0)
        frameRow.key = "frame"
        frameRow.label:SetText(L["Frame"])
        frameRow.hint:SetText(("%d px"):format(HUD:FrameGet("width")))
        PaintRow(frameRow)
        -- the list scrolls: slot i shows part number scroll + i
        local maxScroll = math.max(0, #order - VIEW_ROWS)
        scroll = math.max(0, math.min(scroll, maxScroll))
        for i = 1, VIEW_ROWS do
            local key = order[scroll + i]
            local row = Row(i)
            if not key then
                row:Hide()
            else
                local def = HUD.byKey[key]
                row.key = key
                local hidden = HUD:IsHidden(key)
                local ok, why = HUD:IsAvailable(def)
                row.label:SetText(def.label)
                row.check:SetOn(not hidden)
                row.label:SetAlpha((hidden or not ok) and 0.45 or 1)
                row:SetAlpha(UI.dragKey == key and 0.4 or 1)   -- the slot of the part being dragged
                if not ok then
                    row.hint:SetText(why or L["not available"])
                elseif def.cooldownBar then
                    row.hint:SetText(tostring(ns.Cooldowns:BarCount(def.cooldownBar)))
                else
                    row.hint:SetText("")
                end
                -- cooldown bars carry a × (red after the first click)
                row.remove:SetShown(def.cooldownBar ~= nil)
                row.grip:ClearAllPoints()
                row.grip:SetPoint("RIGHT", def.cooldownBar and -22 or -2, 0)
                if def.cooldownBar then
                    local on = armed.bar == def.cooldownBar and GetTime() < armed.untilT
                    row.remove.text:SetText(on and ns.Colorize(ns.HEX.alert, "×") or "×")
                end
                PaintRow(row)
                row:Show()
            end
        end
        scrollBar:Update(#order, VIEW_ROWS, scroll)
        addBar:SetAlpha(ns.Cooldowns.BarTotal() >= ns.Cooldowns.BARS and 0.4 or 1)
        local show = PanelKey(selected)
        for key, panel in pairs(panels) do
            panel.sf:SetShown(key == show)
            if key ~= show then panel.sf.bar:Hide() end
            if key == show then
                panel.sf:SetContentHeight(-panel.y + 12)
                for _, w in ipairs(panel.widgets) do w:Refresh() end
            end
        end
        resetPart:SetShown(not (HUD.byKey[show] and HUD.byKey[show].fixedLook))
    end
    ns.On("HUD_STYLE_CHANGED", function()
        if p:IsShown() then layoutPage.Refresh() end
    end)
end


layoutPage = App:AddPage({
    key = "layout", section = "hud", label = L["Layout"], order = 20,
    Build = function(_, frame) BuildLayout(frame) end,
})
