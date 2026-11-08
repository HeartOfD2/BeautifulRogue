-- ---------------------------------------------------------------------------
-- Poison tracker: one tile per hand with time left and charges. The button in
-- each tile applies the poison (left-click) or opens the poison choice
-- (right-click). A second, smaller button on the right of the tile does the
-- same for sharpening stones (Stones.lua): this client keeps a poison (imbue)
-- and a stone (temporary enchant) on a weapon at once. Time and charges come
-- from the weapon enchant list, else from GetWeaponEnchantInfo; the weapon
-- tooltip only tells which poison it is (matched by the localized item names).
-- A tile turns red and blinks when a poison runs low or is missing in combat;
-- the stone button's outline does the same for its stone.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local HUD, UI, Rogue = ns.HUD, ns.UI, ns.Rogue

local TILE_H = 22
local BTN = TILE_H - 6
local LOW_MINUTES, LOW_CHARGES = 5, 5
local HAND_LABEL = { MH = L["MH"], OH = L["OH"] }
local HAND_NAME = { MH = L["Main hand"], OH = L["Off hand"] }
local PREFIXES = { "", "*", "alt-", "ctrl-", "shift-" }

-- ---------------------------------------------------------------------------
-- Reading the weapons
-- ---------------------------------------------------------------------------
local function TooltipLines(slot)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
        if ok and data and data.lines then
            for _, line in ipairs(data.lines) do
                local text = line.leftText
                if not ns.IsSecret(text) and type(text) == "string" then lines[#lines + 1] = ns.StripColors(text) end
            end
        end
    end
    return lines
end

-- which poison is on the weapon: the line naming one of our poisons
local function IdentifyPoison(lines)
    for _, text in ipairs(lines) do
        for _, p in ipairs(Rogue.POISONS) do
            local name = Rogue:PoisonName(p.key)
            if name ~= p.key and text:find(name, 1, true) then return p.key, text end
        end
    end
end

-- minutes from a "(<number> <unit>)" group; hours first: German "Std." would
-- otherwise read as seconds ("Sek.")
local function Minutes(n, unit)
    local u = ns.Fold(unit)
    if u:find("^std") or u:find("^h") or u:find("^ч") or u:find("^시") or u:find("^小") then return n * 60 end
    if u:find("^s") or u:find("^с") or u:find("^초") or u:find("^秒") then return math.ceil(n / 60) end
    if u:find("^m") or u:find("^м") or u:find("^분") or u:find("^分") then return n end
end

-- fallback for clients without GetWeaponEnchantInfo: time and charges from
-- the poison's tooltip line, e.g. "Instant Poison VI (28 min) (45 Charges)"
local function ParseLine(text)
    local mins, charges
    for num, rest in text:gmatch("%((%d+)%s*([^%)]*)%)") do
        local n = tonumber(num)
        if not mins then
            local unit = rest:match("^(%S+)")
            mins = unit and Minutes(n, unit)
        elseif not charges then
            charges = n
        end
    end
    return mins, charges
end

-- poison per enchant ID, learned from the tooltip once: later reads skip the
-- tooltip scan as long as the same enchant sits on the weapon
local keyByEnchant = {}

-- the old single-enchant API, all hands at once: { MH = {has, ms, charges, id}, OH = ... } or nil
local function ReadLegacy()
    if not GetWeaponEnchantInfo then return nil end   -- lint:ignore (fallback without the enchant list)
    local ok, hasMH, mhExp, mhCh, mhID, hasOH, ohExp, ohCh, ohID = pcall(GetWeaponEnchantInfo)   -- lint:ignore (same fallback)
    if ok and not (ns.IsSecret(hasMH) or ns.IsSecret(mhExp) or ns.IsSecret(hasOH) or ns.IsSecret(ohExp)
            or ns.IsSecret(mhCh) or ns.IsSecret(ohCh) or ns.IsSecret(mhID) or ns.IsSecret(ohID)) then
        return { MH = { hasMH, mhExp, mhCh, mhID }, OH = { hasOH, ohExp, ohCh, ohID } }
    end
end

-- the stone from the weapon tooltip, for hands the enchant list can't read: a
-- line with a time in brackets that names no poison. No readable line at all
-- (secret in combat) keeps what was read last.
local function StoneFromTooltip(hand, slot)
    local lines = TooltipLines(slot)
    if #lines == 0 then return end
    for _, text in ipairs(lines) do
        if not IdentifyPoison({ text }) then
            local mins = ParseLine(text)
            if mins then
                Rogue:SetStoneRead(hand, { ms = mins * 60000 })
                return
            end
        end
    end
    Rogue:SetStoneRead(hand, nil)
end

-- per hand: { active, mins, charges, key } or nil when no weapon. The enchant
-- list keeps poison (imbue) and stone (temporary) apart; the old API reports
-- one enchant per weapon and is only asked for hands the list can't read.
local function ReadHands()
    local out, enchant = {}, {}
    local listed, legacy = 0, nil
    for hand in pairs(Rogue.HANDS) do
        local ok, imbue, temp = Rogue:ReadEnchantList(hand)
        if ok then
            enchant[hand] = { imbue ~= nil, imbue and imbue.ms, imbue and imbue.charges, imbue and imbue.id }
            Rogue:SetStoneRead(hand, temp)
            listed = listed + 1
        else
            legacy = legacy or ReadLegacy() or false
            enchant[hand] = legacy and legacy[hand] or nil
            if GetInventoryItemID("player", Rogue.HANDS[hand]) then StoneFromTooltip(hand, Rogue.HANDS[hand]) end
        end
    end
    Rogue.readMode = listed == 2 and L["weapon enchant list"]
        or (enchant.MH or enchant.OH) and L["weapon enchant info"] or L["tooltip text"]
    for hand, slot in pairs(Rogue.HANDS) do
        if GetInventoryItemID("player", slot) then
            local e = enchant[hand]
            local id = e and e[1] and e[4]
            local key, line = id and keyByEnchant[id], nil
            -- an empty weapon needs no tooltip scan
            if not key and not (e and not e[1]) then
                key, line = IdentifyPoison(TooltipLines(slot))
                if id and key then keyByEnchant[id] = key end
            end
            local h = { key = key }
            if e then
                if e[1] then
                    h.active = true
                    h.mins = math.max(0, math.ceil((e[2] or 0) / 60000))
                    h.charges = (e[3] and e[3] > 0) and e[3] or nil
                end
            elseif line then
                h.mins, h.charges = ParseLine(line)
                h.active = h.mins ~= nil
            end
            if h.active and key then Rogue.lastSeen[hand] = key end
            out[hand] = h
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Element
-- ---------------------------------------------------------------------------
local el = Rogue:Element({
    key = "poisons", order = 50, label = L["Poison tracker"], secure = true,
    fixedLook = L["The poison tiles have a fixed look. Show, hide and move them in the list."],
})
Rogue.poisonElement = el

local function MakeTile(hand)
    local c = CreateFrame("Frame", nil, HUD.frame)
    c:SetSize((HUD.WIDTH - HUD.GAP) / 2, TILE_H)
    ns.Skin(c, T.hudPanel, T.hudLine)
    HUD:AddEdge(c, "poisons")
    c.label = ns.HudText(c, 11)
    c.label:SetPoint("LEFT", TILE_H + 1, 0)
    c.label:SetTextColor(unpack(T.hudMuted))
    c.label:SetText(HAND_LABEL[hand])
    c.value = ns.HudText(c, 12)
    c.value:SetPoint("RIGHT", -6, 0)
    c.value:SetJustifyH("RIGHT")
    c:Hide()
    return c
end

local OpenChoice, OpenStoneChoice

-- a secure button over a tile: left-click runs its macro, right-click calls onRight
local function MakeSecure(name, tile, icon, onRight, onEnter)
    local b = CreateFrame("Button", name, HUD.frame, "SecureActionButtonTemplate")
    b:SetSize(BTN, BTN)
    b:SetFrameLevel(tile:GetFrameLevel() + 2)
    b:RegisterForClicks("AnyDown")   -- this client only runs secure actions on press
    ns.Skin(b, T.hudTrack, T.hudLine)
    HUD:AddEdge(b, "poisons")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetTexture(icon)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.2)
    -- PostClick is the secure-safe hook for the right-click choice
    b:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and down ~= false then onRight(self) end
    end)
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

-- the apply macro (secure attributes: out of combat only). Modified clicks
-- don't fall back to the plain attributes on this client, so every variant is
-- set explicitly. Only button 1: an unsuffixed "type" would also answer the
-- right-click, which then applied the item while the choice opened.
local function SetApply(b, itemID, slot)
    local macro = itemID and ("/use item:%d\n/use %d"):format(itemID, slot) or nil
    for _, prefix in ipairs(PREFIXES) do
        b:SetAttribute(prefix .. "type1", macro and "macro" or nil)
        b:SetAttribute(prefix .. "macrotext1", macro)
    end
end

local function MakeButton(hand, tile)
    return MakeSecure("BeautifulRoguePoison" .. hand, tile, Rogue.POISON_ICON,
        function(self) OpenChoice(self, hand) end,
        function(self) el:ShowTooltip(self, hand) end)
end

local function MakeStoneButton(hand, tile)
    return MakeSecure("BeautifulRogueStone" .. hand, tile, Rogue.STONE_ICON,
        function(self) OpenStoneChoice(self, hand) end,
        function(self) el:ShowStoneTooltip(self, hand) end)
end

-- built on first use: secure buttons protect the HUD in combat, which only
-- rogues need (a druid's frame must stay free to change in combat)
function el:Ensure()
    if self.tiles or ns.InCombat() then return self.tiles ~= nil end
    self.tiles = { MH = MakeTile("MH"), OH = MakeTile("OH") }
    self.buttons = { MH = MakeButton("MH", self.tiles.MH), OH = MakeButton("OH", self.tiles.OH) }
    self.stones = { MH = MakeStoneButton("MH", self.tiles.MH), OH = MakeStoneButton("OH", self.tiles.OH) }
    return true
end
el.hands, el.alert, el.stoneAlert = {}, {}, {}
el.elapsed, el.clock = 0, 0

function el:Place(y)
    if not self:Ensure() then return 0 end
    local w = (HUD.WIDTH - HUD.GAP) / 2
    local stone = Rogue:StoneButtonOn()
    self.stoneOn = stone
    for i, hand in ipairs({ "MH", "OH" }) do
        local x = (i - 1) * (w + HUD.GAP)
        local tile = self.tiles[hand]
        tile:SetWidth(w)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", HUD.frame, "TOPLEFT", x, y)
        tile.value:ClearAllPoints()
        tile.value:SetPoint("RIGHT", stone and -(BTN + 9) or -6, 0)
        tile.label:SetShown(true)
        tile:Show()
        -- the secure buttons hang from the HUD itself, not from the tiles
        local b, s = self.buttons[hand], self.stones[hand]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", HUD.frame, "TOPLEFT", x + 3, y - 3)
        b:Show()
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", HUD.frame, "TOPLEFT", x + w - BTN - 3, y - 3)
        s:SetShown(stone)
    end
    return TILE_H
end

function el:HideAll()
    if not self.tiles then return end
    for _, hand in ipairs({ "MH", "OH" }) do
        self.tiles[hand]:Hide()
        self.buttons[hand]:Hide()
        self.stones[hand]:Hide()
    end
end

-- the apply macros of the buttons (secure attributes: out of combat only)
function el:UpdateButtons()
    if ns.InCombat() or not self.tiles then return end
    for hand, slot in pairs(Rogue.HANDS) do
        local b = self.buttons[hand]
        local key = Rogue:EffectiveKey(hand)
        local _, id = Rogue:FindPoison(key)
        SetApply(b, id, slot)
        if id then
            b.icon:SetTexture(ns.ItemIcon(id) or Rogue.POISON_ICON)
            b.icon:SetDesaturated(false)
            b.icon:SetAlpha(1)
        else
            b.icon:SetTexture(Rogue:PoisonIcon(key))
            b.icon:SetDesaturated(true)
            b.icon:SetAlpha(0.45)
        end
        SetApply(self.stones[hand], (Rogue:StoneFor(hand)), slot)
    end
end

-- the hand label (MH/OH) gives way when the stone button leaves too little room
local function FitLabel(tile, stone)
    if not stone then
        tile.label:SetShown(true)
        return
    end
    local room = (tile:GetWidth() or 0) - (TILE_H + 1) - (BTN + 9) - 4
    tile.label:SetShown((tile.label:GetStringWidth() or 0) + 4 + (tile.value:GetStringWidth() or 0) <= room)
end

-- stone buttons: icon of the stone they apply, dimmed while none is on the
-- weapon, grey without one in the bags; outline red when it runs low, blinking
-- when it is missing in combat (both only with a fitting stone in the bags)
function el:UpdateStones(inCombat)
    local warn = Rogue:StoneWarnOn()
    for _, hand in ipairs({ "MH", "OH" }) do
        local s = self.stones[hand]
        local alert = false
        if self.stoneOn and GetInventoryItemID("player", Rogue.HANDS[hand]) then
            local id = Rogue:StoneFor(hand)
            local left = Rogue:StoneLeft(hand)
            s.icon:SetTexture(id and ns.ItemIcon(id) or Rogue.STONE_ICON)
            s.icon:SetDesaturated(id == nil)
            s.icon:SetAlpha(left and 1 or (id and 0.6 or 0.4))
            if warn and id then
                if left and left <= LOW_MINUTES * 60 then
                    alert = "low"
                elseif not left and inCombat then
                    alert = "missing"
                end
            end
        end
        self.stoneAlert[hand] = alert
        if alert ~= "missing" then ns.SetEdgeColor(s, alert and T.hudAlert or nil) end
    end
end

-- tile texts: "28m · 45" (minutes · charges), red when low, "missing" in combat
function el:Update()
    if not self.tiles then return end
    if UnitLevel("player") < 20 then
        for _, hand in ipairs({ "MH", "OH" }) do
            self.alert[hand] = false
            self.tiles[hand].value:SetText(ns.Colorize(HEX.hudMuted, "—"))
            ns.SetEdgeColor(self.tiles[hand])
            FitLabel(self.tiles[hand], self.stoneOn)
        end
        pcall(ReadHands)   -- stones work from level 1
        self:UpdateStones(UnitAffectingCombat("player"))
        self:UpdateButtons()
        return
    end
    local ok, hands = pcall(ReadHands)
    self.hands = ok and hands or {}
    local inCombat = UnitAffectingCombat("player")
    local warn = Rogue:Settings().poisonWarn ~= false
    for _, hand in ipairs({ "MH", "OH" }) do
        local h, tile = self.hands[hand], self.tiles[hand]
        local text, alert
        if h and h.active then
            local low = warn and ((h.mins or 99) <= LOW_MINUTES or (h.charges ~= nil and h.charges <= LOW_CHARGES))
            local hex = low and HEX.hudAlert or HEX.hudValue
            text = ns.Colorize(hex, ("%dm"):format(h.mins or 0))
            if h.charges then text = text .. ns.Colorize(HEX.hudMuted, " · ") .. ns.Colorize(hex, h.charges) end
            alert = low and "low" or false
        elseif h and inCombat and warn then
            text, alert = ns.Colorize(HEX.hudAlert, L["missing"]), "missing"
        else
            text, alert = ns.Colorize(HEX.hudMuted, "—"), false
        end
        tile.value:SetText(text)
        FitLabel(tile, self.stoneOn)
        self.alert[hand] = alert
        ns.SetEdgeColor(tile, alert and T.hudAlert or nil)
    end
    self:UpdateStones(inCombat)
    self:UpdateButtons()
end

function el:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= 1 then
        self.elapsed = 0
        self:Update()
    end
    -- warnings: a low poison breathes softly, a missing one blinks hard
    self.clock = self.clock + elapsed
    local breathe = 0.4 + 0.6 * (0.5 + 0.5 * math.cos(self.clock * 3))
    local blinkOn = math.floor(self.clock * 4) % 2 == 0
    for _, hand in ipairs({ "MH", "OH" }) do
        local a, value = self.alert[hand], self.tiles[hand].value
        if a == "missing" then
            value:SetAlpha(blinkOn and 1 or 0.15)
        elseif a == "low" then
            value:SetAlpha(breathe)
        else
            value:SetAlpha(1)
        end
        if self.stoneAlert[hand] == "missing" then
            ns.SetEdgeColor(self.stones[hand], blinkOn and T.hudAlert or nil)
        end
    end
end

function el:Refresh()
    if not self:IsAvailable() then return end
    Rogue:RefreshPoisonNames()
    self:Ensure()
    self:Update()
end

function el:ShowTooltip(owner, hand)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local slot = Rogue.HANDS[hand]
    GameTooltip:AddLine(("%s: %s"):format(HAND_NAME[hand], ns.EquippedName(slot) or "—"), 1, 1, 1)
    local key = Rogue:EffectiveKey(hand)
    local name = Rogue:FindPoison(key)
    if name then
        GameTooltip:AddLine(L["Applies: %s"]:format(name), 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine(L["No matching poison in your bags (%s)."]:format(Rogue:PoisonName(key)), 1, 0.4, 0.4, true)
    end
    local h = self.hands[hand]
    if h and h.active then
        local now = L["On the weapon: %s, %d min"]:format(h.key and Rogue:PoisonName(h.key) or L["a poison"], h.mins or 0)
        if h.charges then now = now .. ", " .. L["%d charges"]:format(h.charges) end
        GameTooltip:AddLine(now, 0.45, 0.85, 0.55)
    end
    GameTooltip:AddLine(L["Left-click: apply  ·  Right-click: choose poison"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function el:ShowStoneTooltip(owner, hand)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local slot = Rogue.HANDS[hand]
    GameTooltip:AddLine(("%s: %s"):format(HAND_NAME[hand], ns.EquippedName(slot) or "—"), 1, 1, 1)
    local id, missingPick = Rogue:StoneFor(hand)
    if id then
        GameTooltip:AddLine(L["Applies: %s"]:format(Rogue:StoneName(id)), 0.8, 0.8, 0.8)
    elseif missingPick then
        GameTooltip:AddLine(L["No %s in your bags."]:format(Rogue:StoneName(missingPick)), 1, 0.4, 0.4, true)
    else
        GameTooltip:AddLine(L["No fitting sharpening stone in your bags."], 1, 0.4, 0.4, true)
    end
    local left, known = Rogue:StoneLeft(hand)
    if left then
        GameTooltip:AddLine(L["Stone on the weapon: %d min"]:format(math.ceil(left / 60)), 0.45, 0.85, 0.55)
    elseif known then
        GameTooltip:AddLine(L["No stone on the weapon."], 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(L["The stone on the weapon can't be read right now."], 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(L["Left-click: apply  ·  Right-click: choose stone"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Poison choice (right-click)
-- ---------------------------------------------------------------------------
OpenChoice = function(anchor, hand)
    if ns.InCombat() then
        ns.Print(L["Poisons can't be chosen during combat."])
        return
    end
    local current = Rogue:Choice(hand)
    local items = { { label = hand == "MH" and L["Main hand: choose poison"] or L["Off hand: choose poison"], isTitle = true } }
    for _, p in ipairs(Rogue.POISONS) do
        local have = Rogue:FindPoison(p.key) ~= nil
        items[#items + 1] = {
            label = Rogue:PoisonName(p.key), icon = Rogue:PoisonIcon(p.key), checked = current == p.key,
            desc = not have and L["none in bags"] or nil,
            fn = function() Rogue:SetChoice(hand, p.key) end,
        }
    end
    items[#items + 1] = {
        label = L["Best available"], icon = Rogue.POISON_ICON, checked = current == nil, divider = true,
        desc = L["highest rank"],
        fn = function() Rogue:SetChoice(hand, nil) end,
    }
    -- with the stone button hidden this is the way back to its settings
    if not Rogue:StoneButtonOn() then
        items[#items + 1] = {
            label = L["Sharpening stones…"], icon = Rogue.STONE_ICON, divider = true,
            desc = L["stone button off"],
            fn = function() Rogue:OpenStones() end,
        }
    end
    UI.OpenMenu(anchor, items, { point = "TOPLEFT", relPoint = "BOTTOMRIGHT", x = 2, y = -4, width = 320 })
end

-- stone choice: the stones of the ranking that fit this weapon
OpenStoneChoice = function(anchor, hand)
    if ns.InCombat() then
        ns.Print(L["Stones can't be chosen during combat."])
        return
    end
    local current = Rogue:StonePick(hand)
    local items = { { label = hand == "MH" and L["Main hand: choose stone"] or L["Off hand: choose stone"], isTitle = true } }
    for _, id in ipairs(Rogue:StoneOrder()) do
        if Rogue:StoneFits(id, hand) or id == current then
            local n = ns.ItemCount(id)
            items[#items + 1] = {
                label = Rogue:StoneName(id), icon = ns.ItemIcon(id) or Rogue.STONE_ICON, checked = current == id,
                desc = n > 0 and tostring(n) or L["none in bags"],
                fn = function() Rogue:SetStonePick(hand, id) end,
            }
        end
    end
    items[#items + 1] = {
        label = L["Best by ranking"], icon = Rogue.STONE_ICON, checked = current == nil, divider = true,
        desc = L["first one in the bags"],
        fn = function() Rogue:SetStonePick(hand, nil) end,
    }
    items[#items + 1] = {
        label = L["Edit ranking…"], icon = Rogue.STONE_ICON,
        fn = function() Rogue:OpenStones() end,
    }
    UI.OpenMenu(anchor, items, { point = "TOPLEFT", relPoint = "BOTTOMRIGHT", x = 2, y = -4, width = 320 })
end

Rogue:On("ROGUE_POISON_CHOICE", function() el:UpdateButtons() end)
Rogue:On("ROGUE_STONE_CHOICE", function() if el.shown then el:Update() end end)
-- the stone button switched on or off: the tiles are laid out anew
Rogue:On("ROGUE_STONE_BUTTON", function()
    HUD:ApplyLayout()
    if el.shown then el:Update() end
end)
for _, ev in ipairs({ "BAG_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
    Rogue:Event(ev, function() if el.shown then el:Update() end end)
end
Rogue:UnitEvent("UNIT_INVENTORY_CHANGED", "player", function() if el.shown then el:Update() end end)
Rogue:Event("PLAYER_REGEN_ENABLED", function() if el.shown then el:UpdateButtons() end end)

Rogue:Status(function()
    return L["Poisons read from: %s"]:format(Rogue.readMode or "—")
end)
