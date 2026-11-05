-- ---------------------------------------------------------------------------
-- Settings page: Cooldowns. Which ones, which bar, which order; add your own.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, UI, App = ns.L, ns.T, ns.UI, ns.App

local cooldownsPage   -- set at the end of the file; filled in while building
local ROW_H = 26

local function BuildCooldowns(p)
    local CD = ns.Cooldowns
    local LIST_ROW_H, ROWS = 24, 11
    UI.Label(p, L["COOLDOWN"], 26, 0)
    local barLabel = UI.Label(p, L["BAR"], App.CONTENT_W - 107, 0)
    barLabel:SetWidth(98)
    barLabel:SetJustifyH("CENTER")
    local orderLabel = UI.Label(p, L["ORDER"], 0, 0)
    orderLabel:ClearAllPoints()
    orderLabel:SetPoint("TOPRIGHT", 0, 0)
    orderLabel:SetJustifyH("RIGHT")
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", 0, -18)
    list:SetSize(App.CONTENT_W, LIST_ROW_H * ROWS)
    list:EnableMouseWheel(true)
    local rows, entries, scroll, counts = {}, {}, 0, {}

    local function Render()
        entries, counts = CD:List()
        barLabel:SetShown(CD.BarTotal() > 1)
        local maxScroll = math.max(0, #entries - ROWS)
        scroll = math.max(0, math.min(scroll, maxScroll))
        for i, row in ipairs(rows) do
            local e = entries[scroll + i]
            row.entry = e
            if e then
                local available = CD:IsAvailable(e)
                local hidden = CD:IsHidden(e.key)
                CD:RefreshIcon(e)
                row.icon:SetTexture(e.frame.icon:GetTexture())
                row.icon:SetDesaturated(hidden or not available)
                local name = CD:EntryName(e)
                local tag
                if e.kind == "racial" then tag = L["racial"]
                elseif e.kind == "special" then tag = L["module"]
                elseif e.kind == "book" then tag = L["spellbook"]
                elseif e.kind == "custom" then tag = e.itemID and L["item"] or L["spell"] end
                if tag then name = name .. "  " .. ns.Muted(tag) end
                if not available then name = name .. "  " .. ns.Muted(L["not learned"]) end
                row.label:SetText(name)
                row.label:SetAlpha(hidden and 0.45 or 1)
                row.check:SetOn(not hidden)
                row.remove:SetShown(e.kind == "custom")
                row.bg:SetColorTexture(T.hover[1], T.hover[2], T.hover[3], (e.bar % 2 == 0) and T.hover[4] or 0)
                row.barBtn.text:SetText(L["Bar %d"]:format(e.bar))
                row.barBtn:SetShown(CD.BarTotal() > 1)   -- with one bar there is nothing to choose
                local lifted = UI.dragKey == e.key   -- the slot of the row being dragged
                if lifted then
                    row.bg:SetColorTexture(T.accentSoft[1], T.accentSoft[2], T.accentSoft[3], T.accentSoft[4] or 1)
                end
                row:SetAlpha(lifted and 0.4 or 1)
                row:Show()
            else
                row:Hide()
            end
        end
    end

    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, list)
        row:SetSize(App.CONTENT_W, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.check = UI.Check(row)
        row.check:SetPoint("LEFT", 4, 0)
        row.check:SetScript("OnClick", function()
            CD:SetHidden(row.entry.key, not CD:IsHidden(row.entry.key))
            Render()
        end)
        row.iconEdge = row:CreateTexture(nil, "ARTWORK")
        row.iconEdge:SetSize(20, 20)
        row.iconEdge:SetPoint("LEFT", 26, 0)
        ns.Color(row.iconEdge, T.line)
        row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("CENTER", row.iconEdge)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.label = ns.Text(row, 12)
        row.label:SetPoint("LEFT", 52, 0)
        row.label:SetPoint("RIGHT", -118, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.remove = UI.Button(row, 18, "×", function()
            local e = row.entry
            if not (e and e.kind == "custom") then return end
            local name = CD:EntryName(e)
            CD:RemoveCustom(e.key)
            Render()
            App.Status(L["Removed %s."]:format(name))
        end, 18)
        row.remove:SetPoint("RIGHT", -92, 0)
        UI.Tooltip(row.remove, { L["Remove"] })
        -- the bar of this cooldown: a list of the character's bars (up to 20)
        row.barBtn = UI.Button(row, 56, "", function(self)
            local items = {}
            for b = 1, CD.BarTotal() do
                local n = counts[b] or 0
                items[#items + 1] = { label = L["Bar %d"]:format(b) .. "  " .. ns.Muted(("%d/%d"):format(n, CD.PerBar())),
                    checked = b == row.entry.bar,
                    fn = function()
                        local ok, why = CD:SetBar(row.entry.key, b)
                        if not ok and why then App.Status(why, true) end
                        Render()
                    end }
            end
            UI.OpenMenu(self, items)
        end, 18)
        row.barBtn:SetPoint("RIGHT", -30, 0)
        -- drag the grip up or down; an entry only changes places within its own bar
        row.grip = UI.DragHandle(row, {
            key = function() return row.entry and row.entry.key end,
            indexOf = function(key)
                for n, e in ipairs(entries) do
                    if e.key == key then return n end
                end
            end,
            targetAt = function()
                local top = list:GetTop()
                if not top then return end
                local slot = math.floor((top - UI.CursorY(list)) / LIST_ROW_H) + 1
                return math.min(#entries, scroll + math.max(1, math.min(ROWS, slot)))
            end,
            -- one step in the list: entries the list does not show (not learned) may sit in between, so go on until it shows
            move = function(key, dir)
                local function Shown()
                    for n, e in ipairs(entries) do
                        if e.key == key then return n end
                    end
                end
                local before = Shown()
                for _ = 1, 60 do
                    local at = ns.IndexOf(CD:Order(), key)
                    CD:Move(key, dir)
                    Render()
                    if Shown() ~= before or ns.IndexOf(CD:Order(), key) == at then break end
                end
            end,
            edge = function()
                local top = list:GetTop()
                local now = GetTime()
                if not top or now < (list.scrollAt or 0) then return end
                local y, before = UI.CursorY(list), scroll
                if y > top then scroll = scroll - 1 elseif y < top - ROWS * LIST_ROW_H then scroll = scroll + 1 end
                if scroll ~= before then
                    list.scrollAt = now + 0.12
                    Render()
                end
            end,
            start = function() Render() end,
            done = function() Render() end,
            ghost = function(key)
                for _, e in ipairs(entries) do
                    if e.key == key then return CD:EntryName(e), e.frame.icon:GetTexture() end
                end
            end,
        })
        row.grip:SetPoint("RIGHT", -4, 0)
        rows[i] = row
    end
    list:SetScript("OnMouseWheel", function(_, delta)
        scroll = scroll - delta
        Render()
    end)

    -- add your own: drag in, shift-click a link, or type a name or ID
    local addY = -18 - ROWS * ROW_H - 10
    UI.Label(p, L["ADD AN ITEM OR SPELL  (potions, bandages, trinkets ...)"], 0, addY)
    local box = UI.LineEdit(p, 13)
    box:SetPoint("TOPLEFT", 0, addY - 16)
    box:SetSize(App.CONTENT_W - 76, 24)
    UI.Placeholder(box, L["Drag it here, shift-click its link, or type its name or ID"])
    local function Add(text)
        local kind, id = CD:Parse(text or box:GetText())
        if not kind then App.Status(id, true) return end
        local e, why = CD:AddCustom(kind, id)
        if not e then App.Status(why, true) return end
        box:SetText("")
        box:ClearFocus()
        scroll = 1e6   -- new entries land at the end
        Render()
        App.Status(L["Added %s to bar %d."]:format(CD:EntryName(e), CD:Bar(e.key)))
    end
    local function AddFromCursor()
        if not GetCursorInfo then return end
        local kind, a, _, c = GetCursorInfo()
        if kind == "item" and a then
            ClearCursor()
            Add("item:" .. a)
        elseif kind == "spell" and (c or a) then
            ClearCursor()
            Add("spell:" .. (c or a))
        end
    end
    box:SetScript("OnReceiveDrag", AddFromCursor)
    box:SetScript("OnMouseDown", function() if GetCursorInfo and GetCursorInfo() then AddFromCursor() end end)
    box:SetScript("OnEnterPressed", function() Add() end)
    -- shift-clicking an item while the box has focus drops its link in here
    if hooksecurefunc and ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if box:HasFocus() and type(link) == "string" then box:Insert(link) end
        end)
    end
    local addBtn = UI.Button(p, 70, L["Add"], function() Add() end, 24)
    addBtn:SetPoint("LEFT", box, "RIGHT", 6, 0)
    addBtn:SetAccent(true)

    local hint = UI.Hint(p, "", App.CONTENT_W)
    hint:SetPoint("BOTTOMLEFT", 0, 0)

    cooldownsPage.Refresh = function()
        if CD.BarTotal() == 0 then
            hint:SetText(L["There is no cooldown bar. Add one under HUD › Layout."])
        else
            hint:SetText(L["%d icons fit in a row. Abilities found in your spellbook are listed, but not shown on a bar until you tick them."]:format(CD.PerBar()))
        end
        Render()
    end
end


cooldownsPage = App:AddPage({
    key = "cooldowns", section = "hud", label = L["Cooldowns"], order = 30,
    Build = function(_, frame) BuildCooldowns(frame) end,
})
