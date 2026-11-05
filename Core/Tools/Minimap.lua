-- ---------------------------------------------------------------------------
-- Minimap button with the addon logo. Left-click opens the app window,
-- right-click the macros; Shift- or middle-click belongs to a module (the
-- notes), without one it acts like a left-click. Drag it around the minimap
-- edge; position and visibility are saved account-wide.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

local function DB() return ns.Acct().minimap end

local btn = CreateFrame("Button", "BeautifulRogueMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetSize(21, 21)
icon:SetPoint("TOPLEFT", 6, -5)
icon:SetTexture("Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\IconRound")

local ring = btn:CreateTexture(nil, "OVERLAY")
ring:SetSize(53, 53)
ring:SetPoint("TOPLEFT")
ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

-- the saved angle (degrees, 0 = east) on the minimap edge
local function UpdatePosition()
    local angle = math.rad(DB().angle or 200)
    local x, y = math.cos(angle), math.sin(angle)
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        -- out to the square's edge instead of the inscribed circle
        x = math.max(-1, math.min(1, x * 1.414))
        y = math.max(-1, math.min(1, y * 1.414))
    end
    local w = Minimap:GetWidth() / 2 + 5
    local h = Minimap:GetHeight() / 2 + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    DB().angle = math.deg(math.atan2(py / s - my, px / s - mx)) % 360
    UpdatePosition()
end

btn:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", OnDragUpdate)
    GameTooltip:Hide()
end)
btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
end)

-- pressed look: nudge the icon like Blizzard's own minimap buttons
btn:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 7, -6) end)
btn:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 6, -5) end)

-- Shift- / middle-click: def = { OnClick(), tooltip, hint, IsActive() }
-- (modules use M:MinimapClick); the first active one wins
local shiftClicks = {}
function ns.AddMinimapShiftClick(def) shiftClicks[#shiftClicks + 1] = def end
local function ShiftClick()
    for _, def in ipairs(shiftClicks) do
        if not def.IsActive or def.IsActive() then return def end
    end
end

function ns.MinimapClick(button)
    local shift = (button == "MiddleButton" or IsShiftKeyDown()) and ShiftClick()
    if button == "RightButton" then
        ns.App:Toggle("macros")
    elseif shift then
        shift.OnClick()
    else
        ns.App:Toggle()
    end
end

-- one line for the settings page: what each click does
function ns.MinimapHint()
    local parts = { L["Left-click: settings"] }
    local shift = ShiftClick()
    if shift and shift.hint then parts[#parts + 1] = shift.hint end
    parts[#parts + 1] = L["Right-click: macros"]
    return table.concat(parts, "  ·  ")
end

btn:SetScript("OnClick", function(_, button) ns.MinimapClick(button) end)

local function TooltipLines(tt)
    tt:AddLine("|cff" .. ns.HEX.accent .. ns.TITLE .. "|r")
    tt:AddLine(L["Left-click: settings and tools"], 0.8, 0.8, 0.8)
    local shift = ShiftClick()
    if shift and shift.tooltip then tt:AddLine(shift.tooltip, 0.8, 0.8, 0.8) end
    tt:AddLine(L["Right-click: macros"], 0.8, 0.8, 0.8)
end

btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    TooltipLines(GameTooltip)
    GameTooltip:AddLine(L["Drag: move around the minimap"], 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

function ns.IsMinimapButtonShown() return not DB().hide end

function ns.SetMinimapButtonShown(show)
    DB().hide = not show
    btn:SetShown(show and true or false)
    if not show then ns.Print(L["Minimap button hidden. /ef minimap brings it back."]) end
end

-- addon compartment (the addon list next to the minimap), where the client
-- has one: registered at login and only while the button is wanted, so the
-- switch covers both
local compartmentDone = false
local function RegisterCompartment()
    local cf = rawget(_G, "AddonCompartmentFrame")
    if compartmentDone or DB().hide or not (cf and cf.RegisterAddon) then return end
    compartmentDone = true
    pcall(cf.RegisterAddon, cf, {
        text = ns.TITLE,
        icon = "Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\Icon",
        notCheckable = true,
        registerForAnyClick = true,
        func = function(_, input) ns.MinimapClick(type(input) == "table" and input.buttonName or "LeftButton") end,
        funcOnEnter = function(frame)
            GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
            TooltipLines(GameTooltip)
            GameTooltip:Show()
        end,
        funcOnLeave = function() GameTooltip:Hide() end,
    })
end

btn:Hide()
-- other addons or the client may show minimap children again: stay hidden
btn:SetScript("OnShow", function(self) if DB().hide then self:Hide() end end)
local function Apply()
    UpdatePosition()
    btn:SetShown(not DB().hide)
    RegisterCompartment()
end
ns.On("LOGIN", Apply)

-- for /ef status: what is saved and what shows
function ns.MinimapState()
    return DB().hide and true or false, btn:IsShown() and true or false, compartmentDone
end
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() if ns.ready then C_Timer.After(1, Apply) end end)
ns.On("SETTINGS_RESET", function(keys) if keys.minimap then Apply() end end)
