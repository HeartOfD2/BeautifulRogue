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
--
-- Cost: nothing is asked of the game once a second. The weapons are read when
-- something changed (equipment, weapon enchant and inventory events; in combat
-- also every few seconds, as charges drop with every hit), the bags when they
-- changed, and the time left is a point in time (GetTime()) that counts down
-- here. The once-a-second pass only paints what really changed.
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

-- one tooltip line in a HUD color (the game's tooltip stays dark in every mode)
local function TipLine(text, c, wrap) GameTooltip:AddLine(text, c[1], c[2], c[3], wrap) end

-- ---------------------------------------------------------------------------
-- Reading the weapons
-- ---------------------------------------------------------------------------
local HAND_LIST = { "MH", "OH" }   -- never built in a loop: nothing is allocated per frame
local FLUSH_GAP = 0.08      -- seconds between two passes at most (events come in bursts)
local COMBAT_READ = 3       -- seconds: in combat the weapons are read this often (charges drop with each hit)

-- the lines of one weapon tooltip, in a table that is reused (use it before the next call)
local lineBuf = {}
local function TooltipLines(slot)
    wipe(lineBuf)
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
        if ok and data and data.lines then
            for _, line in ipairs(data.lines) do
                local text = line.leftText
                if not ns.IsSecret(text) and type(text) == "string" then lineBuf[#lineBuf + 1] = ns.StripColors(text) end
            end
        end
    end
    return lineBuf
end

-- which poison a line names. The longest name wins, so a name inside another
-- one ("Numbing" in "Mind-numbing") can't take its place in any client language.
local function PoisonOfText(text)
    local bestKey, bestLen
    for _, p in ipairs(Rogue.POISONS) do
        local name = Rogue:PoisonName(p.key)
        if name ~= p.key and (not bestLen or #name > bestLen) and text:find(name, 1, true) then
            bestKey, bestLen = p.key, #name
        end
    end
    return bestKey
end

-- which poison is on the weapon: the first line naming one of our poisons
local function IdentifyPoison(lines)
    for _, text in ipairs(lines) do
        local key = PoisonOfText(text)
        if key then return key, text end
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

-- poison per enchant ID, learned from the tooltip once: later readings skip the
-- tooltip scan as long as the same enchant sits on the weapon. An enchant whose
-- tooltip named no poison is not scanned again before the names were read afresh.
local keyByEnchant, failedAt = {}, {}

-- the old single-enchant API, all hands at once: { MH = {has, ms, charges, id}, OH = ... } or nil
-- (the same two tables every time)
local legacyBuf = { MH = {}, OH = {} }
local function ReadLegacy()
    if not GetWeaponEnchantInfo then return nil end   -- lint:ignore (fallback without the enchant list)
    local ok, hasMH, mhExp, mhCh, mhID, hasOH, ohExp, ohCh, ohID = pcall(GetWeaponEnchantInfo)   -- lint:ignore (same fallback)
    if ok and not (ns.IsSecret(hasMH) or ns.IsSecret(mhExp) or ns.IsSecret(hasOH) or ns.IsSecret(ohExp)
            or ns.IsSecret(mhCh) or ns.IsSecret(ohCh) or ns.IsSecret(mhID) or ns.IsSecret(ohID)) then
        local mh, oh = legacyBuf.MH, legacyBuf.OH
        mh[1], mh[2], mh[3], mh[4] = hasMH, mhExp, mhCh, mhID
        oh[1], oh[2], oh[3], oh[4] = hasOH, ohExp, ohCh, ohID
        return legacyBuf
    end
end

-- the stone from the weapon tooltip, for hands the enchant list can't read: a
-- line with a time in brackets that names no poison. No readable line at all
-- (secret in combat) keeps what was read last.
local function StoneFromTooltip(hand, slot)
    -- without every poison name a poison line can't be told from a stone line:
    -- keep the last reading until the names have loaded (GET_ITEM_INFO_RECEIVED)
    if not Rogue:PoisonNamesReady() then return end
    local lines = TooltipLines(slot)
    if #lines == 0 then return end
    for _, text in ipairs(lines) do
        if not PoisonOfText(text) then
            local mins = ParseLine(text)
            if mins then
                Rogue:SetStoneRead(hand, mins * 60000)
                return
            end
        end
    end
    Rogue:SetStoneRead(hand, nil)
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
-- right-click, which then applied the item while the choice opened. Written
-- only when the item changed (b.applyID): a write is a call into the secure code.
local function SetApply(b, itemID, slot)
    if b.applyID == itemID and b.applySlot == slot then return end
    b.applyID, b.applySlot = itemID, slot
    local macro = itemID and ("/use item:%d\n/use %d"):format(itemID, slot) or nil
    for _, prefix in ipairs(PREFIXES) do
        b:SetAttribute(prefix .. "type1", macro and "macro" or nil)
        b:SetAttribute(prefix .. "macrotext1", macro)
    end
end

-- icon, grey and dim of a button, set only when they differ from the last time
local function SetLook(b, tex, grey, alpha)
    if b.lookTex ~= tex then
        b.lookTex = tex
        b.icon:SetTexture(tex)
    end
    if b.lookGrey ~= grey then
        b.lookGrey = grey
        b.icon:SetDesaturated(grey)
    end
    if b.lookAlpha ~= alpha then
        b.lookAlpha = alpha
        b.icon:SetAlpha(alpha)
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

-- ---------------------------------------------------------------------------
-- State. Four kinds of work, each with a flag; events only set the flags and
-- the frame's next pass does the work once (events come in bursts):
--   dirtyRead   the weapons: poison and stone per hand (read[hand])
--   dirtyItems  what the bags, the level and the choices say: which poison and
--               which stone each hand gets (pItem, sItem)
--   dirtyApply  the apply macros and icons of the buttons (not in combat)
--   dirtyDraw   the texts and colors
-- ---------------------------------------------------------------------------
el.read = { MH = {}, OH = {} }     -- weapon, active, key, expires (GetTime()), charges
el.alert, el.stoneAlert = {}, {}
el.pKey, el.pItem, el.sItem, el.sMissing = {}, {}, {}, {}
el.elapsed, el.clock, el.animGap, el.lastFlush, el.lastRead = 0, 0, 0, 0, 0
el.perf = {}

-- timing and garbage of one piece of work, for /brogue status
local function Timed(name, fn, ...)
    if not debugprofilestop then return fn(...) end
    local t0, k0 = debugprofilestop(), collectgarbage("count")
    fn(...)
    local ms, kb = debugprofilestop() - t0, collectgarbage("count") - k0
    local p = el.perf[name]
    if not p then
        p = { n = 0, ms = 0, max = 0, kb = 0 }
        el.perf[name] = p
    end
    p.n, p.ms, p.kb = p.n + 1, p.ms + ms, p.kb + math.max(0, kb)
    if ms > p.max then p.max = ms end
end

function el:Mark(read, items, draw)
    if read then self.dirtyRead = true end
    if items then self.dirtyItems = true end
    if draw then self.dirtyDraw = true end
end
function el:MarkAll() self.dirtyRead, self.dirtyItems, self.dirtyDraw = true, true, true end

-- built on first use: secure buttons protect the HUD in combat, which only
-- rogues need (a druid's frame must stay free to change in combat)
function el:Ensure()
    if self.tiles or ns.InCombat() then return self.tiles ~= nil end
    self.tiles = { MH = MakeTile("MH"), OH = MakeTile("OH") }
    self.buttons = { MH = MakeButton("MH", self.tiles.MH), OH = MakeButton("OH", self.tiles.OH) }
    self.stones = { MH = MakeStoneButton("MH", self.tiles.MH), OH = MakeStoneButton("OH", self.tiles.OH) }
    self:MarkAll()
    return true
end

function el:Place(y)
    if not self:Ensure() then return 0 end
    local w = (HUD.WIDTH - HUD.GAP) / 2
    local stone = Rogue:StoneButtonOn()
    self.stoneOn = stone
    for i, hand in ipairs(HAND_LIST) do
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
        s:SetAlpha(stone and 1 or 0)   -- gone at once, even if hiding the button waits for the end of a fight
    end
    self:Invalidate()
    self:MarkAll()
    return TILE_H
end

function el:HideAll()
    if not self.tiles then return end
    for _, hand in ipairs(HAND_LIST) do
        self.tiles[hand]:Hide()
        self.buttons[hand]:Hide()
        self.stones[hand]:Hide()
    end
end

-- the weapons: poison (time as a point in time, charges, which one) and, while
-- the stones are on, the stone
function el:Read()
    local now = GetTime()
    self.lastRead = now
    local stones = Rogue:StonesOn()
    local listed, anyInfo, legacy = 0, false, nil
    local unidentified = false
    for _, hand in ipairs(HAND_LIST) do
        local slot = Rogue.HANDS[hand]
        local r = self.read[hand]
        r.weapon = GetInventoryItemID("player", slot) ~= nil
        -- the enchant list keeps poison (imbue) and stone (temporary) apart; the
        -- old API reports one enchant per weapon and is only asked for hands the list can't read
        local ok, iMs, iCharges, iID, tMs = Rogue:ReadEnchantList(hand)
        local known, has, ms, charges, id = false, false, nil, nil, nil
        if ok then
            known, has, ms, charges, id = true, iMs ~= nil, iMs, iCharges, iID
            listed = listed + 1
            if stones then Rogue:SetStoneRead(hand, tMs) end
        else
            if legacy == nil then legacy = ReadLegacy() or false end
            local e = legacy and legacy[hand]
            if e then known, has, ms, charges, id = true, e[1], e[2], e[3], e[4] end
            if stones and r.weapon then StoneFromTooltip(hand, slot) end
        end
        if known then anyInfo = true end
        local key, line
        if r.weapon then
            if has and id then key = keyByEnchant[id] end
            -- an empty weapon needs no tooltip scan, nor one already tried with these names
            if not key and not (known and not has) and not (id and failedAt[id] == Rogue:NameRev()) then
                local lines = TooltipLines(slot)
                if #lines > 0 then
                    key, line = IdentifyPoison(lines)
                    if id then
                        if key then keyByEnchant[id] = key else failedAt[id] = Rogue:NameRev() end
                    end
                end
            end
        end
        r.key, r.active, r.expires, r.charges = key, false, nil, nil
        if r.weapon then
            if known then
                if has then
                    r.active = true
                    r.expires = now + (ms or 0) / 1000
                    r.charges = (charges and charges > 0) and charges or nil
                end
            elseif line then
                local mins, ch = ParseLine(line)
                if mins then r.active, r.expires, r.charges = true, now + mins * 60, ch end
            end
            if r.active and key and Rogue.lastSeen[hand] ~= key then
                Rogue.lastSeen[hand] = key
                self.dirtyItems = true   -- the poison a hand gets follows what was last seen on it
            end
            if r.active and not key then unidentified = true end
        end
    end
    self.unidentified = unidentified
    Rogue.readMode = listed == 2 and L["weapon enchant list"]
        or anyInfo and L["weapon enchant info"] or L["tooltip text"]
end

-- which poison and which stone each hand gets (what the bags, the level and the choices say)
function el:Resolve()
    local stones = Rogue:StonesOn()
    for _, hand in ipairs(HAND_LIST) do
        local key = Rogue:EffectiveKey(hand)
        self.pKey[hand] = key
        self.pItem[hand] = select(2, Rogue:FindPoison(key))
        if stones then
            self.sItem[hand], self.sMissing[hand] = Rogue:StoneFor(hand)
        else
            self.sItem[hand], self.sMissing[hand] = nil, nil
        end
    end
    self.dirtyApply = true
end

-- the apply macros and icons of the buttons (secure attributes: out of combat only)
function el:Apply()
    for _, hand in ipairs(HAND_LIST) do
        local slot = Rogue.HANDS[hand]
        local b = self.buttons[hand]
        local id = self.pItem[hand]
        SetApply(b, id, slot)
        if id then
            SetLook(b, ns.ItemIcon(id) or Rogue.POISON_ICON, false, 1)
        else
            SetLook(b, Rogue:PoisonIcon(self.pKey[hand]), true, 0.45)
        end
        SetApply(self.stones[hand], self.sItem[hand], slot)
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

-- forget what was painted (a new theme, a new layout): the next pass paints everything
function el:Invalidate()
    if not self.tiles then return end
    for _, hand in ipairs(HAND_LIST) do
        local t, s = self.tiles[hand], self.stones[hand]
        t.dState = nil
        s.dAlert, s.dId, s.dHas, s.dStone = nil, nil, nil, nil
    end
    self.dirtyDraw = true
end

-- stone buttons: icon of the stone they apply, dimmed while none is on the
-- weapon, grey without one in the bags; outline red when it runs low, blinking
-- when it is missing in combat (both only with a fitting stone in the bags)
local function DrawStone(self, hand, inCombat)
    local s, r = self.stones[hand], self.read[hand]
    local alert = false
    if self.stoneOn and r.weapon then
        local warn = Rogue:StoneWarnOn()   -- the stones have their own switch for the warning
        local id = self.sItem[hand]
        local left = Rogue:StoneLeft(hand)
        local has = left ~= nil
        if warn and id then
            if left and left <= LOW_MINUTES * 60 then
                alert = "low"
            elseif not left and inCombat then
                alert = "missing"
            end
        end
        if s.dId ~= id or s.dHas ~= has or s.dStone ~= true then
            s.dId, s.dHas, s.dStone = id, has, true
            s.icon:SetTexture(id and ns.ItemIcon(id) or Rogue.STONE_ICON)
            s.icon:SetDesaturated(id == nil)
            s.icon:SetAlpha(has and 1 or (id and 0.6 or 0.4))
        end
    else
        s.dStone = false
    end
    self.stoneAlert[hand] = alert
    if s.dAlert ~= alert then
        s.dAlert = alert
        if alert ~= "missing" then ns.SetEdgeColor(s, alert and T.hudAlert or nil) end
    end
    return alert
end

-- tile texts: "28m · 45" (minutes · charges), red when low, "missing" in combat.
-- Only what differs from the last painting is touched.
function el:Draw()
    local inCombat = UnitAffectingCombat("player") and true or false
    local warn = Rogue:Settings().poisonWarn ~= false
    local noPoison = UnitLevel("player") < 20   -- poisons come at level 20 (stones work from level 1)
    local now = GetTime()
    local animating = false
    for _, hand in ipairs(HAND_LIST) do
        local r, tile = self.read[hand], self.tiles[hand]
        local state, mins, low = 0, 0, false   -- state: 0 idle, 1 poison on the weapon, 2 missing
        if not noPoison then
            if r.active then
                local left = r.expires - now
                if left > 0 then
                    state, mins = 1, Rogue:Minutes(left)
                    low = warn and (mins <= LOW_MINUTES or (r.charges ~= nil and r.charges <= LOW_CHARGES)) or false
                else
                    r.active = false      -- ran out: the game confirms with its next reading
                    self.dirtyRead = true
                end
            end
            if state == 0 and r.weapon and inCombat and warn then state = 2 end
        end
        local charges = r.charges or 0
        if tile.dState ~= state or tile.dMins ~= mins or tile.dCharges ~= charges or tile.dLow ~= low
                or tile.dStoneOn ~= self.stoneOn then
            tile.dState, tile.dMins, tile.dCharges, tile.dLow, tile.dStoneOn = state, mins, charges, low, self.stoneOn
            local text
            if state == 1 then
                local hex = low and HEX.hudAlert or HEX.hudValue
                text = ns.Colorize(hex, ("%dm"):format(mins))
                if r.charges then text = text .. ns.Colorize(HEX.hudMuted, " · ") .. ns.Colorize(hex, r.charges) end
            elseif state == 2 then
                text = ns.Colorize(HEX.hudAlert, L["missing"])
            else
                text = ns.Colorize(HEX.hudMuted, "—")
            end
            tile.value:SetText(text)
            FitLabel(tile, self.stoneOn)
            ns.SetEdgeColor(tile, (low or state == 2) and T.hudAlert or nil)
            tile.value:SetAlpha(1)
        end
        local alert = (state == 2 and "missing") or (low and "low") or false
        self.alert[hand] = alert
        if DrawStone(self, hand, inCombat) or alert then animating = true end
    end
    self.animating = animating
end

-- the pieces of work whose flag is set, in this order
function el:Flush()
    if not self.tiles then return end
    if self.dirtyRead then
        self.dirtyRead = false
        Timed("read", self.Read, self)
        self.dirtyDraw = true
    end
    if self.dirtyItems then
        self.dirtyItems = false
        Timed("items", self.Resolve, self)
        self.dirtyDraw = true
    end
    if self.dirtyApply and not ns.InCombat() then
        self.dirtyApply = false
        Timed("apply", self.Apply, self)
    end
    if self.dirtyDraw then
        self.dirtyDraw = false
        Timed("draw", self.Draw, self)
    end
end

-- everything at once (settings, layout, tests)
function el:Update()
    if not self.tiles then return end
    self:MarkAll()
    self:Flush()
end

-- warnings: a low poison breathes softly, a missing one blinks hard. Numbers only.
function el:Animate(elapsed)
    self.clock = self.clock + elapsed
    self.animGap = self.animGap + elapsed
    if self.animGap < 0.05 then return end   -- 20 steps a second are smooth enough
    self.animGap = 0
    local breathe = 0.4 + 0.6 * (0.5 + 0.5 * math.cos(self.clock * 3))
    local blinkOn = math.floor(self.clock * 4) % 2 == 0
    for _, hand in ipairs(HAND_LIST) do
        local a, value = self.alert[hand], self.tiles[hand].value
        if a == "missing" then
            value:SetAlpha(blinkOn and 1 or 0.15)
        elseif a == "low" then
            value:SetAlpha(breathe)
        end
        if self.stoneAlert[hand] == "missing" then
            ns.SetEdgeColor(self.stones[hand], blinkOn and T.hudAlert or nil)
        end
    end
end

-- once a second: the countdown and the combat state change what is painted;
-- in combat the weapons are read now and then (charges drop with each hit)
function el:Tick()
    if UnitAffectingCombat("player") and GetTime() - self.lastRead >= COMBAT_READ then self.dirtyRead = true end
    self.dirtyDraw = true
end

function el:OnUpdate(elapsed)
    if self.dirtyRead or self.dirtyItems or self.dirtyDraw then
        local now = GetTime()
        if now - self.lastFlush >= FLUSH_GAP then
            self.lastFlush = now
            self:Flush()
        end
    end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= 1 then
        self.elapsed = 0
        self:Tick()
    end
    if self.animating then self:Animate(elapsed) end
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
    TipLine(("%s: %s"):format(HAND_NAME[hand], ns.EquippedName(slot) or "—"), T.hudText)
    local key = Rogue:EffectiveKey(hand)
    local name = Rogue:FindPoison(key)
    if name then
        TipLine(L["Applies: %s"]:format(name), T.hudText)
    else
        TipLine(L["No matching poison in your bags (%s)."]:format(Rogue:PoisonName(key)), T.hudAlert, true)
    end
    local h = self.read[hand]
    if h.active and h.expires then
        local mins = Rogue:Minutes(h.expires - GetTime())
        local now = L["On the weapon: %s, %d min"]:format(h.key and Rogue:PoisonName(h.key) or L["a poison"], mins)
        if h.charges then now = now .. ", " .. L["%d charges"]:format(h.charges) end
        TipLine(now, T.hudGood)
    end
    TipLine(L["Left-click: apply  ·  Right-click: choose poison"], T.hudMuted)
    GameTooltip:Show()
end

function el:ShowStoneTooltip(owner, hand)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local slot = Rogue.HANDS[hand]
    TipLine(("%s: %s"):format(HAND_NAME[hand], ns.EquippedName(slot) or "—"), T.hudText)
    local id, missingPick = Rogue:StoneFor(hand)
    if id then
        TipLine(L["Applies: %s"]:format(Rogue:StoneName(id)), T.hudText)
    elseif missingPick then
        TipLine(L["No %s in your bags."]:format(Rogue:StoneName(missingPick)), T.hudAlert, true)
    else
        TipLine(L["No fitting sharpening stone in your bags."], T.hudAlert, true)
    end
    local left, known = Rogue:StoneLeft(hand)
    if left then
        TipLine(L["Stone on the weapon: %d min"]:format(Rogue:Minutes(left)), T.hudGood)
    elseif known then
        TipLine(L["No stone on the weapon."], T.hudMuted)
    else
        TipLine(L["The stone on the weapon can't be read right now."], T.hudMuted, true)
    end
    TipLine(L["Left-click: apply  ·  Right-click: choose stone"], T.hudMuted)
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
        local desc
        if not Rogue:FindPoison(p.key) then
            -- only ranks above the character's level in the bags: say from when
            local need = Rogue:FindPoison(p.key, true) and Rogue:PoisonLevelNeeded(p.key)
            desc = need and L["from level %d"]:format(need) or L["none in bags"]
        end
        items[#items + 1] = {
            label = Rogue:PoisonName(p.key), icon = Rogue:PoisonIcon(p.key), checked = current == p.key,
            desc = desc,
            fn = function() Rogue:SetChoice(hand, p.key) end,
        }
    end
    items[#items + 1] = {
        label = L["Best available"], icon = Rogue.POISON_ICON, checked = current == nil, divider = true,
        desc = L["highest rank"],
        fn = function() Rogue:SetChoice(hand, nil) end,
    }
    -- with the stone button hidden this is the way back to its settings
    if Rogue:StonesOn() and not Rogue:StoneButtonOn() then
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

-- ---------------------------------------------------------------------------
-- Events: they only set the flags (the frame does the work once per burst)
-- ---------------------------------------------------------------------------
-- a choice of the player is answered at once
Rogue:On("ROGUE_POISON_CHOICE", function()
    el:Mark(false, true)
    el:Flush()
end)
Rogue:On("ROGUE_STONE_CHOICE", function()
    el:Mark(false, true)
    el:Flush()
end)
-- the stone button switched on or off (or the stones as a whole): the tiles are laid out anew
Rogue:On("ROGUE_STONE_BUTTON", function()
    HUD:ApplyLayout()
    if el.shown then el:Update() end
end)
-- the stones switched on or off as a whole (Rogue.lua): same relayout, and nothing stays known about them
Rogue.featureStones:OnChange(function(on)
    if not on then Rogue:ClearStoneState() end
    -- invisible at once, even when hiding the secure button has to wait for the end of a fight
    if el.stones then
        for _, hand in ipairs(HAND_LIST) do el.stones[hand]:SetAlpha(on and 1 or 0) end
    end
    ns.Fire("ROGUE_STONE_BUTTON")
end)

-- the bags, the equipment and the level: which poison and stone each hand gets
for _, ev in ipairs({ "BAG_UPDATE", "PLAYER_LEVEL_UP" }) do
    Rogue:Event(ev, function()
        if not el.shown then return end
        el.dirtyItems = true
        if el.unidentified then el.dirtyRead = true end   -- the names may be there now
    end)
end
Rogue:Event("GET_ITEM_INFO_RECEIVED", function(_, id)
    -- item data comes for any item of any addon: only a poison or stone of ours matters
    if not el.shown or type(id) ~= "number" then return end
    if Rogue:PoisonKeyOfItem(id) or Rogue:IsStoneItem(id) then
        el.dirtyItems = true
        el.dirtyRead = true
    end
end)
Rogue:Event("PLAYER_EQUIPMENT_CHANGED", function()
    if el.shown then el:Mark(true, true) end
end)
-- weapon enchants: the names of the last two exist in this client (EllesmereUI uses them);
-- a client without one skips it quietly. UNIT_INVENTORY_CHANGED also covers temporary enchants.
for _, ev in ipairs({ "WEAPON_ENCHANT_CHANGED", "WEAPON_SLOT_CHANGED" }) do
    Rogue:Event(ev, function() if el.shown then el.dirtyRead = true end end)
end
Rogue:UnitEvent("UNIT_INVENTORY_CHANGED", "player", function() if el.shown then el.dirtyRead = true end end)
-- combat starts and ends: other values readable, other warnings; the buttons wait for the end of a fight
Rogue:Event("PLAYER_REGEN_DISABLED", function() if el.shown then el:Mark(true, false, true) end end)
Rogue:Event("PLAYER_REGEN_ENABLED", function()
    if el.shown then
        el.dirtyApply = true
        el:Mark(true, false, true)
    end
end)
ns.On("THEME_CHANGED", function() el:Invalidate() end)

Rogue:Status(function()
    local line = L["Poisons read from: %s"]:format(Rogue.readMode or "—")
    -- the cost of the tiles since login (not translated): how often, ms per time, the most, garbage per time
    local parts = {}
    for _, name in ipairs({ "read", "items", "apply", "draw" }) do
        local p = el.perf[name]
        if p then
            parts[#parts + 1] = ("%s %dx %.2f ms (max %.2f) %.1f KB"):format(name, p.n, p.ms / p.n, p.max, p.kb / p.n)
        end
    end
    if #parts > 0 then line = line .. "  ·  [" .. table.concat(parts, ", ") .. "]" end
    return line
end)
