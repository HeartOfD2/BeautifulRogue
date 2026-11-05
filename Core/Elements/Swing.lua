-- ---------------------------------------------------------------------------
-- Swing timer: up to three thin bars (main hand, off hand, ranged) that fill
-- between two swings. The game's PLAYER_SWING event brings the finished swing
-- and the length of the next one (already corrected for haste); the bar is
-- pure time arithmetic on GetTime(), never on unit data. A secret payload
-- (not seen so far) is skipped: the bar stays dark, no error. A finished bar
-- waits full while you fight with a target, dimmed when the target is out of
-- range (C_SwingTimer, asked under pcall, plain true/false only). The
-- OnUpdate exists only while a bar is running, waiting or previewed.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T = ns.L, ns.T
local HUD = ns.HUD

local Types = Enum and Enum.PlayerSwingType
-- display order; `slot` = the inventory slot whose weapon the bar belongs to
local ROWS = {
    { key = "main",   kind = (Types and Types.MainHand) or 0, slot = 16, color = "colorMain" },
    { key = "off",    kind = (Types and Types.OffHand) or 1,  slot = 17, color = "colorOff" },
    { key = "ranged", kind = (Types and Types.Ranged) or 2,   slot = 18, color = "colorRanged" },
}
local BY_KIND = {}
for _, row in ipairs(ROWS) do BY_KIND[row.kind] = row end

local DEFAULT_COLOR = {
    main = function() return T.accent end,
    off = function() return T.mark end,
    ranged = function() return T.comboMax end,
}
ns.SwingDefaultColor = function(key) return DEFAULT_COLOR[key]() end

local ROW_GAP = 2          -- px between two bars
local POLL = 0.03          -- seconds between two redraws of a running bar
local RANGE_POLL = 0.25    -- seconds between two range checks of a waiting bar
local PREVIEW_FILL = 0.6   -- how full the bars look while the Layout page is open
local WEAPON_CLASS = 2

local swing = HUD:Register({
    key = "swing", order = 47, height = 5,
    label = L["Swing timer"],
    style = { height = 5, main = true, off = true, ranged = true, clear = false },
    Build = function(self, parent)
        local r = CreateFrame("Frame", nil, parent)
        self.bars, self.state = {}, {}
        for _, row in ipairs(ROWS) do
            local f = CreateFrame("Frame", nil, r)
            ns.Skin(f, T.hudTrack, T.hudLine)
            HUD:AddEdge(f, "swing")
            local fill = CreateFrame("StatusBar", nil, f)
            fill:SetStatusBarTexture(ns.WHITE)
            fill:SetAllPoints()
            fill:SetFrameLevel(f:GetFrameLevel() + 2)
            fill:SetMinMaxValues(0, 1)
            fill:SetValue(0)
            fill:Hide()
            f.fill = fill
            f:Hide()
            self.bars[row.key] = f
            self.state[row.key] = {}
        end
        self.region = r
    end,
})

-- bars the player has seen fire this character (an off-hand or ranged bar then belongs to the gear for good)
local function Seen()
    local s = ns.Char().swing
    return s and s.seen or {}
end

-- does this inventory slot hold a weapon? (a shield or a relic does not swing)
local function HoldsWeapon(slot)
    local id = GetInventoryItemID and GetInventoryItemID("player", slot)
    if not id then return false end
    if not (C_Item and C_Item.GetItemInfoInstant) then return true end   -- cannot tell: better too many bars than none
    local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, id)
    if not ok then return true end
    return classID == WEAPON_CLASS
end

-- the bars in use: switched on, and for off hand and ranged only with a weapon there (or once seen)
function swing:Rows()
    local out = {}
    for _, row in ipairs(ROWS) do
        if HUD:Get("swing", row.key) ~= false then
            if row.key == "main" or Seen()[row.key] or HoldsWeapon(row.slot) then
                out[#out + 1] = row
            end
        end
    end
    return out
end

local function Signature(rows)
    local keys = {}
    for _, row in ipairs(rows) do keys[#keys + 1] = row.key end
    return table.concat(keys, ",")
end

-- is the target within reach for this kind of swing? true / false, nil when it cannot be told
local function InRange(kind)
    if not (C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange) then return nil end
    local ok, v = pcall(C_SwingTimer.IsTargetWithinSwingRange, kind)
    if not ok or ns.IsSecret(v) or type(v) ~= "boolean" then return nil end
    return v
end

-- a finished swing waits for the next one only while you fight with a target
local function Waiting()
    return UnitAffectingCombat("player") and UnitExists("target")
end

-- redraws the shown bars; true while something still needs the OnUpdate
function swing:Update()
    local now, busy = GetTime(), false
    for _, row in ipairs(ROWS) do
        local f = self.bars[row.key]
        if f:IsShown() then
            local st, fill = self.state[row.key], f.fill
            if st.start then
                local p = (now - st.start) / st.dur
                if p < 1 then
                    fill:SetValue(p)
                    fill:SetAlpha(1)
                    fill:Show()
                    busy = true
                elseif Waiting() then
                    fill:SetValue(1)
                    fill:Show()
                    if not st.rangeAt or now - st.rangeAt >= RANGE_POLL then
                        st.rangeAt = now
                        st.inRange = InRange(row.kind)
                    end
                    fill:SetAlpha(st.inRange == false and 0.4 or 1)
                    busy = true
                else
                    st.start, st.dur, st.rangeAt, st.inRange = nil, nil, nil, nil
                    fill:Hide()
                end
            elseif HUD.preview then
                fill:SetValue(PREVIEW_FILL)
                fill:SetAlpha(1)
                fill:Show()
                busy = true
            else
                fill:Hide()
            end
        end
    end
    return busy
end

local function Tick(region, elapsed)
    region.acc = (region.acc or 0) + elapsed
    if region.acc < POLL then return end
    region.acc = 0
    if not swing:Update() then region:SetScript("OnUpdate", nil) end
end

-- starts the OnUpdate when a bar needs it
function swing:Kick()
    local r = self.region
    if not (self.shown and r) then return end
    if self:Update() then r:SetScript("OnUpdate", Tick) else r:SetScript("OnUpdate", nil) end
end

function swing:Place(y)
    local rows = self:Rows()
    self.signature = Signature(rows)
    local r = self.region
    if #rows == 0 then return 0 end
    local h = HUD:Get("swing", "height") or 5
    local total = #rows * h + (#rows - 1) * ROW_GAP
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", HUD.frame, "TOPLEFT", 0, y)
    r:SetPoint("TOPRIGHT", HUD.frame, "TOPRIGHT", 0, y)
    r:SetHeight(total)
    r:Show()
    local used = {}
    for i, row in ipairs(rows) do
        used[row.key] = true
        local f = self.bars[row.key]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -(i - 1) * (h + ROW_GAP))
        f:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -(i - 1) * (h + ROW_GAP))
        f:SetHeight(h)
        f:Show()
    end
    for _, row in ipairs(ROWS) do
        if not used[row.key] then
            self.bars[row.key]:Hide()
            self.bars[row.key].fill:Hide()
        end
    end
    self.shown = true   -- (the layout sets it right after Place; the OnUpdate needs it now)
    self:Kick()
    return total
end

swing.HideAll = function(self)
    if not self.region then return end
    self.region:SetScript("OnUpdate", nil)
    self.region:Hide()
end

function swing:ApplyStyle()
    local clear = HUD:Get("swing", "clear") == true
    local fillColor = clear and { 0, 0, 0, 0 } or T.hudTrack
    for _, row in ipairs(ROWS) do
        local f = self.bars[row.key]
        local c = HUD:Get("swing", row.color)
        if type(c) ~= "table" then c = DEFAULT_COLOR[row.key]() end
        f.fill:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
        -- optional see-through look: no track, no border, only the filled part shows
        f.skinFill = fillColor
        f.skinBg:SetColorTexture(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 1)
        for _, e in ipairs(f.edges) do e:SetShown(not clear) end
    end
end

-- the game reports a swing: this bar starts over with the length of the next one
ns.RegisterEvent("PLAYER_SWING", function(_, duration, kind)
    if ns.IsSecret(duration) or ns.IsSecret(kind) then return end
    if type(duration) ~= "number" or duration <= 0 then return end
    local row = BY_KIND[kind]
    if not row then return end
    local st = swing.state[row.key]
    st.start, st.dur, st.rangeAt, st.inRange = GetTime(), duration, nil, nil
    if row.key ~= "main" then
        local seen = ns.Char().swing
        if seen and seen.seen and not seen.seen[row.key] then
            seen.seen[row.key] = true   -- a bar the gear never announced: it belongs here from now on
            HUD:ApplyLayout()
            return
        end
    end
    swing:Kick()
end)

-- a weapon change can add or remove the off-hand and ranged bars
ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
    if not ns.ready or not swing.shown then return end
    if Signature(swing:Rows()) ~= swing.signature then HUD:ApplyLayout() end
end)

-- the Layout page opening or closing starts or ends the preview fill
ns.On("HUD_PREVIEW_CHANGED", function() swing:Kick() end)
