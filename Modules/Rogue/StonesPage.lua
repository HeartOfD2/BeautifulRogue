-- ---------------------------------------------------------------------------
-- Window "Sharpening stones" (rogue module): the stone button on or
-- off, its warning, the ranking (drag to reorder) and the player's own items.
-- The button in each poison tile applies the first stone of the ranking that
-- is in the bags, fits the weapon and can be used at this level.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX, UI = ns.L, ns.T, ns.HEX, ns.UI
local Rogue = ns.Rogue

local LIST_W, ROW = 360, 20
local COL_X, COL_W = 380, 212
local KIND_LABEL = { sharp = L["sharp"], blunt = L["blunt"], any = L["any weapon"] }
local HAND_SHORT = { MH = L["MH"], OH = L["OH"] }

local Render

local function BuildPage(p)
    local maxRows = #Rogue.STONES + Rogue.MAX_CUSTOM_STONES

    -- ---- ranking
    UI.Label(p, L["RANKING"], 0, 0)
    local list = CreateFrame("Frame", nil, p)
    list:SetPoint("TOPLEFT", 0, -18)
    list:SetSize(LIST_W, maxRows * ROW)
    local rows = {}
    for i = 1, maxRows do
        local r = CreateFrame("Frame", nil, list)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        r:SetSize(LIST_W, ROW)
        r.hl = r:CreateTexture(nil, "BACKGROUND")   -- marks the entry being dragged
        r.hl:SetAllPoints()
        ns.Color(r.hl, T.accentSoft)
        r.hl:Hide()
        r.num = ns.Text(r, 11)
        r.num:SetPoint("LEFT", 4, 0)
        ns.Color(r.num, T.muted)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 24, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = ns.Text(r, 12)
        r.name:SetPoint("LEFT", 46, 0)
        r.name:SetPoint("RIGHT", -140, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.kind = ns.Text(r, 10)
        r.kind:SetPoint("RIGHT", -96, 0)
        r.kind:SetJustifyH("RIGHT")
        ns.Color(r.kind, T.muted)
        r.count = ns.Text(r, 11)
        r.count:SetPoint("RIGHT", -52, 0)
        r.count:SetJustifyH("RIGHT")
        r.grip = UI.DragHandle(r, {
            key = function() return r.id end,
            indexOf = function(id) return ns.IndexOf(Rogue:StoneOrder(), id) end,
            targetAt = function()
                local top = list:GetTop()
                if not top then return end
                local slot = math.floor((top - UI.CursorY(list)) / ROW) + 1
                return math.max(1, math.min(#Rogue:StoneOrder(), slot))
            end,
            move = function(id, dir) Rogue:MoveStone(id, dir) end,
            start = function() Render() end,
            done = function() Render() end,
            ghost = function(id) return Rogue:StoneName(id), ns.ItemIcon(id) or Rogue.STONE_ICON end,
        })
        r.grip:SetPoint("RIGHT", -26, 0)
        r.del = UI.Button(r, 16, "×", function() if r.id then Rogue:RemoveCustomStone(r.id) end end, 16)
        r.del:SetPoint("RIGHT", -6, 0)
        UI.Tooltip(r.del, { L["Remove"], L["Takes this own item out of the list."] })
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) else GameTooltip:AddLine(Rogue:StoneName(self.id)) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
    end

    -- ---- settings
    local hint = UI.Hint(p, L["The small button on the right of each poison tile applies the first stone of this list that is in your bags, fits the weapon and that you can use at your level. Drag the grip to change the order; right-click the button to pick a stone for one hand."], COL_W)
    hint:SetPoint("TOPLEFT", COL_X, 0)

    local checks = {}
    local function Check(label, field, tip, after)
        local c = UI.CheckRow(p, label,
            function() return Rogue:StoneSettings()[field] ~= false end,
            function(v)
                Rogue:StoneSettings()[field] = v and true or false
                if after then after() end
                ns.Fire("ROGUE_STONE_CHOICE")
            end, COL_W)
        UI.Tooltip(c, { label, tip })
        checks[#checks + 1] = c
        return c
    end
    local btnCheck = Check(L["Stone button in the poison tiles"], "button",
        L["Without it the poison tiles look as before; the ranking stays."],
        function() ns.Fire("ROGUE_STONE_BUTTON") end)
    btnCheck:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
    local warnCheck = Check(L["Warn when a stone runs out"], "warn",
        L["Red outline under 5 minutes, blinking when the stone is missing in combat. Only while a fitting stone is in your bags."])
    warnCheck:SetPoint("TOPLEFT", btnCheck, "BOTTOMLEFT", 0, -4)

    -- ---- own items
    local own = UI.Label(p, L["OWN ITEMS"], COL_X, 0)
    own:ClearAllPoints()
    own:SetPoint("TOPLEFT", warnCheck, "BOTTOMLEFT", 0, -16)
    local edit = UI.LineEdit(p, 12, 60)
    edit:SetSize(COL_W, 22)
    edit:SetPoint("TOPLEFT", own, "BOTTOMLEFT", 0, -6)
    UI.Placeholder(edit, L["Item ID or item link"])
    -- an item dropped from the bags fills in its ID
    edit:SetScript("OnReceiveDrag", function(self)
        if not GetCursorInfo then return end
        local what, id = GetCursorInfo()
        if what == "item" and type(id) == "number" then
            self:SetText(tostring(id))
            if ClearCursor then ClearCursor() end
        end
    end)
    local kind = "any"
    local kinds = {}
    for _, k in ipairs(Rogue.STONE_KINDS) do kinds[#kinds + 1] = { k, KIND_LABEL[k] } end
    local seg = UI.Segmented(p, kinds, function() return kind end, function(v) kind = v end, COL_W)
    seg:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -6)
    local status = ns.Text(p, 11)
    status:SetWidth(COL_W)
    status:SetJustifyH("LEFT")
    local function Say(msg, alert) status:SetText(ns.Colorize(alert and HEX.alert or HEX.muted, msg)) end

    local function Add()
        local text = edit:GetText() or ""
        local id = tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
        if not id or id <= 0 then
            Say(L["Enter an item ID (a number) or an item link."], true)
            return
        end
        local result = Rogue:AddCustomStone(id, kind)
        if result == "already" then
            Say(L["This item is already in the list."], true)
        elseif result == "full" then
            Say(L["At most %d own items."]:format(Rogue.MAX_CUSTOM_STONES), true)
        else
            edit:SetText("")
            edit:ClearFocus()
            Say(L["Added: %s"]:format(Rogue:StoneName(id)))
        end
    end
    edit:SetScript("OnEnterPressed", Add)
    local addBtn = UI.Button(p, COL_W, L["Add"], Add, 22)
    addBtn:SetPoint("TOPLEFT", seg, "BOTTOMLEFT", 0, -6)
    addBtn:SetAccent(true)
    UI.Tooltip(addBtn, { L["Add"], L["Adds the item to the end of the ranking, for the weapons chosen above. Oils and new stones work the same way."] })
    p.stoneEdit, p.stoneAdd = edit, addBtn
    status:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -6)

    local defaults = UI.Button(p, COL_W, L["Default order"], function() Rogue:DefaultStoneOrder() end, 22)
    defaults:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -14)
    UI.Tooltip(defaults, { L["Default order"], L["Puts the built-in stones back in their order; own items follow them."] })

    Render = function()
        if not p:IsVisible() then return end
        local order = Rogue:StoneOrder()
        local used = {}
        for hand in pairs(Rogue.HANDS) do
            local id = Rogue:StoneFor(hand)
            if id then used[id] = (used[id] and (used[id] .. "/") or "") .. HAND_SHORT[hand] end
        end
        for i, r in ipairs(rows) do
            local id = order[i]
            r.id = id
            if id then
                local n = ns.ItemCount(id)
                r.num:SetText(i)
                r.icon:SetTexture(ns.ItemIcon(id) or Rogue.STONE_ICON)
                r.icon:SetDesaturated(n == 0)
                r.name:SetText(Rogue:StoneName(id) .. (used[id] and ("  " .. ns.Code(used[id])) or ""))
                ns.Color(r.name, n > 0 and T.text or T.muted)
                r.kind:SetText(KIND_LABEL[Rogue:StoneKind(id)] or "")
                r.count:SetText(n > 0 and tostring(n) or ns.Muted("–"))
                r.del:SetShown(Rogue:IsCustomStone(id))
                r.hl:SetShown(UI.dragKey ~= nil and UI.dragKey == id)
                r:Show()
            else
                r:Hide()
            end
        end
        for _, c in ipairs(checks) do c:Refresh() end
    end
end

-- its own window (a page would make the navigation scroll at the default size),
-- built on first use; opened from the stone choice and the Modules page
local WIN_W, WIN_H = 616, 470
local win
function Rogue:OpenStones()
    if not self:StonesOn() then
        ns.Print(L["%s is switched off. Switch it on under Modules."]:format(L["Sharpening stones"]))
        return
    end
    if not win then
        win = UI.Window("BeautifulRogueStones", WIN_W, WIN_H, L["Sharpening stones"], { strata = "FULLSCREEN" })
        win:SetPoint("CENTER")
        local body = CreateFrame("Frame", nil, win)
        body:SetPoint("TOPLEFT", 14, -40)
        body:SetSize(WIN_W - 28, WIN_H - 54)
        win.body = body
        BuildPage(body)
        win:SetScript("OnShow", function() Render() end)
    end
    win:Show()
    Render()
    return win
end
function Rogue:StonesShown() return win ~= nil and win:IsShown() end

Rogue:Command({ "stones" }, function() Rogue:OpenStones() end,
    L["rogue: open the sharpening stones (stone button, ranking, own items)"])

local function RenderIfOpen()
    if Render and Rogue:StonesShown() then Render() end
end
-- these only matter while the stones are on (their events are registered then, see Rogue.lua)
local Stones = Rogue.featureStones
Stones:On("ROGUE_STONE_CHOICE", RenderIfOpen)
for _, ev in ipairs({ "BAG_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
    Stones:Event(ev, RenderIfOpen)
end
-- switched off: no window left on the screen
Stones:OnChange(function(on)
    if not on and win and win:IsShown() then win:Hide() end
end)

Rogue:Reset({ key = "stones", group = "macros", order = 76, label = L["Sharpening stones"],
    desc = L["Ranking, own items and the stone picked for each hand go back to the defaults; the stone button shows again."],
    reset = function()
        local s = ns.Char().modules.rogue
        if s then s.stones = nil end
        ns.Fire("ROGUE_STONE_CHOICE")
        ns.Fire("ROGUE_STONE_BUTTON")
    end })
