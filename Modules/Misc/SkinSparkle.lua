-- ---------------------------------------------------------------------------
-- Miscellaneous, tab Skinning: glints over the corpse the interact key would skin next.
-- The game's soft targeting picks that corpse ("softinteract"), and its cursor names the
-- action (Crosshair_Skin, Crosshair_UnableSkin): a corpse with loot left shows the loot
-- cursor, so it gets glints only once it is looted, and a corpse tagged by someone else none.
-- The glints hang on the corpse's nameplate. If the game gives it none, the cvar
-- SoftTargetNameplateInteract is opened for this corpse and put back afterwards. Nothing else
-- of soft targeting is changed: the game's interact key has to be on.
-- What the nameplate holds stays invisible (a corpse needs no 0% health bar): its children,
-- because an alpha on the nameplate itself does not hold in the client. That takes the game's
-- symbol with it, which EllesmereUI hides on attackable units anyway, so the same cursor
-- image is drawn here, above the glints.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L
local Misc = ns.Misc
local Skin = {}
Misc.SkinSparkle = Skin

Skin.DEFAULTS = { on = true }

local SOFT = "softinteract"
local GATE = "SoftTargetNameplateInteract"
local LOOT_SPARKLES = "ForeverLootSparkles"
local TEXTURE = "Interface\\AddOns\\BeautifulRogue\\Media\\Glint"
local SKINNING_LINE = 393    -- skill line
local SKINNING_SPELL = 8613  -- its name is the profession's name in the client's language
local POLL = 0.15            -- seconds; looting and walking raise no event of their own
local OFFSET_Y = -45         -- from the nameplate down to the corpse (pixels)
local SPREAD = 42            -- radius of the glints (pixels)
local GLINT_SIZE = 30
local GLINTS = 6
local BLEND = 6              -- speed of a change of state
local SYMBOL_SIZE = 32
local SYMBOL_Y = 45          -- above the glints (pixels)
local RAISE = 20             -- frame levels above the nameplate, in case it can't be hidden

-- r, g, b, alpha of the glints: can skin now, too far away, can't skin (skill too low)
local LOOKS = {
    ready  = { 1, 0.78, 0.38, 1 },
    far    = { 1, 0.78, 0.38, 0.5 },
    locked = { 0.6, 0.6, 0.6, 0.55 },
}

local sin, cos, sqrt, random, min, max, pi = math.sin, math.cos, math.sqrt, math.random, math.min, math.max, math.pi

function Skin.Get(key)
    local v = Misc.Store("skinSparkle")[key]
    if type(v) == "boolean" then return v end
    return Skin.DEFAULTS[key]
end

function Skin.Set(key, value)
    Misc.Store("skinSparkle")[key] = value
    Misc:Apply()
end

-- calls about other units can fail or answer with a secret value: both count as "no answer"
local function Read(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not ns.IsSecret(value) then return value end
    return nil
end

-- ---------------------------------------------------------------- the nameplate switch
-- The value to put back lies outside the misc table, which a reset of the module wipes, and
-- in the saved variables: a /reload on a corpse must not leave the switch open for good.
local function OpenGate()
    if InCombatLockdown() then return end
    local now = Read(GetCVar, GATE)
    if now == nil or now == "1" then return end
    local acct = ns.Acct()
    if acct.skinSparkleGate == nil then acct.skinSparkleGate = now end
    pcall(SetCVar, GATE, "1")
end

local function CloseGate()
    local acct = ns.Acct()
    local was = acct.skinSparkleGate
    if was == nil or InCombatLockdown() then return end
    acct.skinSparkleGate = nil
    if Read(GetCVar, GATE) ~= was then pcall(SetCVar, GATE, was) end
end

-- ForeverLootSparkles opens the same switch for nodes and corpses with loot and would not
-- notice it being closed under them: for those targets the switch waits for the next one.
local function LootSparklesWantsGate()
    if not (C_AddOns and Read(C_AddOns.IsAddOnLoaded, LOOT_SPARKLES)) then return false end
    if Read(UnitIsGameObject, SOFT) == true then return true end
    local guid = Read(UnitGUID, SOFT)
    return guid ~= nil and Read(CanLootUnit, guid) == true
end

-- ---------------------------------------------------------------- the target
local function HasProfession(name, ...)
    for i = 1, select("#", ...) do   -- GetProfessions leaves nil gaps for empty slots
        local index = select(i, ...)
        if index and Read(GetProfessionInfo, index) == name then return true end
    end
    return false
end

-- Asks both lists: the profession list reports other skill lines on Forever, so it goes by
-- name. Without an answer from either the character gets the benefit of the doubt.
function Skin.KnowsSkinning()
    local asked = false
    local name = ns.SpellName(SKINNING_SPELL)
    if name and GetProfessions and GetProfessionInfo then
        asked = true
        if HasProfession(name, GetProfessions()) then return true end
    end
    local lines = C_SkillInfo and Read(C_SkillInfo.GetNumSkillLines)
    if type(lines) == "number" and lines > 0 then
        asked = true
        for i = 1, lines do
            local info = Read(C_SkillInfo.GetSkillLineInfo, i)
            if type(info) == "table" and info.skillID == SKINNING_LINE then return true end
        end
    end
    return not asked
end

local probe   -- hidden, receives the target's cursor

local function CursorName(get)
    local value = get and Read(get, probe)
    return type(value) == "string" and value:lower() or ""
end

-- is the cursor the skinning one, and greyed out?
local function ReadCursor()
    if not probe then
        probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
    end
    if not Read(SetUnitCursorTexture, probe, SOFT, nil, true) then return false, false end
    local text = CursorName(probe.GetTexture) .. " " .. CursorName(probe.GetAtlas)
    return text:find("skin", 1, true) ~= nil, text:find("unable", 1, true) ~= nil
end

-- the look of the glints for the current target, nil if it gets none
local function TargetLook()
    if Read(UnitIsGameObject, SOFT) == true or Read(UnitIsDead, SOFT) ~= true then return nil end
    local skin, unable = ReadCursor()
    if not skin or not Skin.KnowsSkinning() then return nil end
    local inRange = Read(UnitIsInInteractRange, SOFT)
    if inRange == false then return LOOKS.far end
    if unable then return inRange == true and LOOKS.locked or LOOKS.far end
    return LOOKS.ready
end

local tokens = {}   -- nameplateN -> true

local function Usable(plate)
    return plate and not (plate.IsForbidden and plate:IsForbidden()) and plate or nil
end

local function FindPlate()
    if not C_NamePlate then return nil end
    local plate = Usable(Read(C_NamePlate.GetNamePlateForUnit, SOFT))
    if plate then return plate end
    for token in pairs(tokens) do
        if Read(UnitIsUnit, token, SOFT) == true then
            plate = Usable(Read(C_NamePlate.GetNamePlateForUnit, token))
            if plate then return plate end
        end
    end
    return nil
end

-- ---------------------------------------------------------------- the glints
local frame, anchor, glints, shown, symbol
local look = { 0, 0, 0, 0 }
local hidden = {}   -- child of the nameplate -> its alpha before

local function HideChild(child)
    if child == frame or (child.IsForbidden and child:IsForbidden()) then return end
    local alpha = Read(child.GetAlpha, child)
    if alpha == 0 then return end
    if hidden[child] == nil then hidden[child] = alpha or 1 end
    child:SetAlpha(0)
end

-- every frame: the plate's owner sets alpha again, and it adds children of its own
local function HidePlateContent()
    for i = 1, select("#", anchor:GetChildren()) do
        HideChild((select(i, anchor:GetChildren())))
    end
end

local function ShowPlateContent()
    for child, alpha in pairs(hidden) do child:SetAlpha(alpha) end
    wipe(hidden)
end

local function Spawn(glint)
    local angle, reach = random() * 2 * pi, sqrt(random())
    glint.x, glint.y = cos(angle) * reach * SPREAD, sin(angle) * reach * SPREAD * 0.7
    glint.life = 0.7 + 0.7 * random()
    glint.size = GLINT_SIZE * (0.6 + 0.6 * random())
    glint.turn, glint.spin = random() * pi, (random() - 0.5) * 1.5
    glint.age = -0.5 * random()   -- a short dark pause before it lights up
end

local function Animate(_, elapsed)
    elapsed = min(elapsed, 0.1)
    HidePlateContent()
    local blend = min(elapsed * BLEND, 1)
    for i = 1, 4 do look[i] = look[i] + (shown[i] - look[i]) * blend end
    for _, glint in ipairs(glints) do
        glint.age = glint.age + elapsed
        if glint.age >= glint.life then Spawn(glint) end
        local age = max(glint.age, 0)
        local shine = sin(pi * age / glint.life)
        local size = max(glint.size * (0.4 + 0.6 * shine), 1)
        glint.tex:SetPoint("CENTER", frame, "CENTER", glint.x, glint.y + 8 * age)
        glint.tex:SetSize(size, size)
        glint.tex:SetRotation(glint.turn + glint.spin * age)
        glint.tex:SetVertexColor(look[1], look[2], look[3], look[4] * shine)
    end
end

local function Build()
    frame = CreateFrame("Frame")
    frame:SetSize(1, 1)
    frame:Hide()
    glints = {}
    for i = 1, GLINTS do
        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(TEXTURE)
        tex:SetBlendMode("ADD")
        tex:SetVertexColor(1, 1, 1, 0)
        glints[i] = { tex = tex }
    end
    symbol = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    symbol:SetSize(SYMBOL_SIZE, SYMBOL_SIZE)
    symbol:SetPoint("CENTER", frame, "CENTER", 0, SYMBOL_Y)
    frame:SetScript("OnUpdate", Animate)
end

local function Detach()
    if not anchor then return end
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(nil)
    ShowPlateContent()
    anchor, shown = nil, nil
end

local function Attach(plate, wanted)
    if anchor ~= plate then
        Detach()
        if not frame then Build() end
        frame:SetParent(plate)
        local level = Read(plate.GetFrameLevel, plate)
        if type(level) == "number" then frame:SetFrameLevel(level + RAISE) end
        frame:SetPoint("CENTER", plate, "CENTER", 0, OFFSET_Y)
        frame:SetIgnoreParentAlpha(true)
        for i = 1, 4 do look[i] = wanted[i] end
        for _, glint in ipairs(glints) do Spawn(glint) end
        anchor = plate
        HidePlateContent()
        frame:Show()
    end
    if shown ~= wanted then Read(SetUnitCursorTexture, symbol, SOFT, nil, true) end   -- greyed out or not
    shown = wanted
end

function Skin.ShownLook()
    for name, value in pairs(LOOKS) do
        if value == shown then return name end
    end
    return nil
end

function Skin.Anchor() return anchor end

function Skin.Symbol() return symbol end

-- ---------------------------------------------------------------- keeping up
local active = false

local function Evaluate()
    if not active then return end
    if InCombatLockdown() then
        Detach()
        return
    end
    local wanted = TargetLook()
    if not wanted then
        Detach()
        if ns.Acct().skinSparkleGate ~= nil and not LootSparklesWantsGate() then CloseGate() end
        return
    end
    local plate = FindPlate()
    if plate then
        Attach(plate, wanted)
    else
        Detach()
        OpenGate()   -- the nameplate follows with NAME_PLATE_UNIT_ADDED
    end
end

local poller = CreateFrame("Frame")
poller:Hide()
local waited = 0
poller:SetScript("OnUpdate", function(_, elapsed)
    waited = waited + elapsed
    if waited >= POLL then
        waited = 0
        Evaluate()
    end
end)

Misc.OnApply(function()
    active = (Misc:Wanted() and Skin.Get("on")) and true or false
    poller:SetShown(active)
    if active then
        Evaluate()
    else
        Detach()
        CloseGate()
    end
end)

ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, token)
    if not ns.IsSecret(token) then tokens[token] = true end
    Evaluate()
end)

ns.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, token)
    if not ns.IsSecret(token) then tokens[token] = nil end
    Evaluate()
end)

ns.RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", function() Evaluate() end)

-- cvars can't change in combat, and an open switch would keep a health bar on every corpse
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    Detach()
    CloseGate()
end)

-- a switch left open by a /reload in combat
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if not active then CloseGate() end
end)

Misc:Status(function()
    return L["Miscellaneous: skinning sparkle %s"]:format(Skin.Get("on") and L["active"] or L["off"])
end)
