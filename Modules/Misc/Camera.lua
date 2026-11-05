-- ---------------------------------------------------------------------------
-- Miscellaneous, tab Camera: fast zoom. While the switch is on, CameraZoomIn/Out are
-- replaced: the mouse wheel moves a target distance, the step grows while the wheel keeps
-- turning, and the camera follows along the chosen curve within the chosen zoom time (it is
-- moved with MoveViewIn/OutStart). Off: the originals are put back. Nothing is touched before.
-- The wheel need not call these globals; the zoom keys are overridden as well (see below).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L
local Misc = ns.Misc
local Camera = {}
Misc.Camera = Camera

Camera.DEFAULTS = { on = true, base = 1.5, accel = 0.8, speed = 0.8, curve = "direct" }
Camera.RANGES = {   -- { min, max, slider step }
    base   = { 0.25, 5, 0.25 },    -- yards per wheel notch
    accel  = { 0, 2, 0.1 },        -- extra step per notch while the wheel keeps turning
    speed  = { 0, 1, 0.05 },       -- slow (1 s for the whole way) .. fast (0.05 s)
}
local STREAK_GAP = 0.3       -- seconds without a notch end a fast turn
local MAX_FACTOR = 10        -- the step never grows beyond this multiple of the base step
local DEFAULT_SPEED = 20   -- the game's own cameraZoomSpeed; the zoom is nearly stuck when something leaves it low
local ZOOM_PER_FACTOR = 15   -- largest distance at cameraDistanceMaxZoomFactor 1 (39 at 2.6)

Camera.CURVE_NAMES = { soft = true, direct = true }

function Camera.Get(key)
    local d = Camera.DEFAULTS[key]
    local v = Misc.Store("camera")[key]
    if type(d) == "number" then
        if type(v) ~= "number" or v ~= v then return d end
        local r = Camera.RANGES[key]
        return math.max(r[1], math.min(r[2], v))
    end
    if type(d) == "string" then return type(v) == "string" and Camera.CURVE_NAMES[v] and v or d end
    if type(v) == "boolean" then return v end   -- (false must stay false when the default is true)
    return d
end

function Camera.Set(key, value)
    Misc.Store("camera")[key] = value
    Misc:Apply()
end

function Camera.ResetValues()
    local s = Misc.Store("camera")
    s.base, s.accel, s.speed, s.curve = nil, nil, nil, nil
end

-- ---------------------------------------------------------------- the replacement
-- The wheel only moves our target. Every notch starts a new motion from the current camera
-- distance to the target; each frame the camera speed (MoveViewIn/OutStart, a fraction of
-- cameraZoomSpeed) is set so the camera follows the chosen curve, like the reactive zoom of
-- Max Camera Distance. The speed setting is the longest time the whole way may take.
local origIn, origOut, ourIn, ourOut
local driver
local target, t0, from, change, duration, lastDir = 0, 0, 0, 0, 0, 0
local lastNotch, streak = -10, 0
local moving = false

local function MaxDistance()
    local f = tonumber(GetCVar("cameraDistanceMaxZoomFactor")) or 1
    return ZOOM_PER_FACTOR * f
end

-- seconds the camera may need for the whole way: speed 0 = 1 s, speed 1 = 0.05 s
local function ZoomTime() return 1 - Camera.Get("speed") * 0.95 end

-- position at time t of a motion of length d from b by c (the curves of the reactive zoom)
local CURVES = {
    soft   = function(t, b, c, d) return c * t / d + b end,                    -- linear
    direct = function(t, b, c, d) t = t / d return -c * t * (t - 2) + b end,   -- out quad
}

local function StopMove()
    lastDir = 0
    if type(MoveViewOutStart) ~= "function" then return end
    pcall(MoveViewOutStart, 0)
    pcall(MoveViewInStart, 0)
    pcall(MoveViewInStop)
    pcall(MoveViewOutStop)
end

local function Stop()
    moving = false
    StopMove()
    if driver then driver:Hide() end
end

local function Finish()
    local rest = target - GetCameraZoom()
    Stop()
    if math.abs(rest) > 0.05 then   -- missed the target: the client's own zoom closes the gap
        if rest < 0 then pcall(origIn, -rest) else pcall(origOut, rest) end
    end
end

local function Step(_, dt)
    local now = GetTime()
    local zoom = GetCameraZoom()
    local t = now - t0
    if t >= duration or (change > 0 and zoom >= target) or (change < 0 and zoom <= target) then
        Finish()
        return
    end
    dt = math.max(dt, 1 / 120)
    local ahead = CURVES[Camera.Get("curve")] or CURVES.soft
    local speed = (ahead(math.min(t + dt, duration), from, change, duration) - zoom) / dt
    local zs = tonumber(GetCVar("cameraZoomSpeed")) or 20
    if zs <= 0 then zs = 20 end
    local dir = speed > 0 and 1 or speed < 0 and -1 or 0
    if dir ~= lastDir then StopMove() end
    lastDir = dir
    if dir > 0 then MoveViewOutStart(speed / zs) elseif dir < 0 then MoveViewInStart(-speed / zs) end
end

-- one wheel notch (or a macro call): dir -1 = closer, +1 = further away
local function Notch(dir, increments)
    if not driver then return end
    local now = GetTime()
    local zoom = GetCameraZoom()
    if not moving then target = zoom end
    if now - lastNotch > STREAK_GAP then streak = 0 end
    lastNotch = now
    local factor = math.min(1 + Camera.Get("accel") * streak, MAX_FACTOR)
    streak = streak + 1
    local step = Camera.Get("base") * factor * (tonumber(increments) or 1)
    target = math.max(0, math.min(math.max(MaxDistance(), zoom), target + dir * step))
    from, change, t0 = zoom, target - zoom, now
    local zs = tonumber(GetCVar("cameraZoomSpeed")) or 20
    if zs <= 0 then zs = 20 end
    duration = math.min(ZoomTime(), math.abs(change) / zs)
    if type(MoveViewOutStart) ~= "function" or duration < 1 / 60 then
        -- too short to follow a curve (or no camera movement functions): one step of the client
        Stop()
        if change < 0 then pcall(origIn, -change) elseif change > 0 then pcall(origOut, change) end
        return
    end
    moving = true
    driver:Show()
end

-- The wheel does not go through the Lua globals on this client, so the
-- keys bound to the zoom actions are also overridden to click two buttons that call Notch.
-- Override bindings cannot change in combat: then it is done when combat ends.
local binder, btnIn, btnOut, bindPending
local lastClick = -1

local function Click(dir)
    return function(_, _, down)
        local now = GetTime()
        if down == false and now == lastClick then return end   -- press and release of one notch
        lastClick = now
        Notch(dir, 1)
    end
end

local function BindWheel()
    if type(SetOverrideBindingClick) ~= "function" or type(GetBindingKey) ~= "function" then return end
    if not binder then
        binder = CreateFrame("Frame")
        binder:SetScript("OnEvent", function()
            binder:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if bindPending then bindPending = false; Misc:Apply() end
        end)
        btnIn = CreateFrame("Button", "BeautifulRogueZoomIn", UIParent)
        btnOut = CreateFrame("Button", "BeautifulRogueZoomOut", UIParent)
        for dir, b in pairs({ [-1] = btnIn, [1] = btnOut }) do
            b:RegisterForClicks("AnyDown", "AnyUp")
            b:SetScript("OnClick", Click(dir))
        end
    end
    if InCombatLockdown() then
        bindPending = true
        binder:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    ClearOverrideBindings(binder)
    for action, name in pairs({ CAMERAZOOMIN = "BeautifulRogueZoomIn", CAMERAZOOMOUT = "BeautifulRogueZoomOut" }) do
        for _, key in ipairs({ GetBindingKey(action) }) do
            SetOverrideBindingClick(binder, true, key, name, "LeftButton")
        end
    end
end

local function UnbindWheel()
    bindPending = false
    if binder and not InCombatLockdown() then ClearOverrideBindings(binder) end
    if binder and InCombatLockdown() then
        bindPending = true
        binder:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function Install()
    if ourIn then return end
    local zin, zout = rawget(_G, "CameraZoomIn"), rawget(_G, "CameraZoomOut")
    if type(zin) ~= "function" or type(zout) ~= "function" or type(GetCameraZoom) ~= "function" then return end
    origIn, origOut = zin, zout
    driver = driver or CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", Step)
    ourIn = function(increments) Notch(-1, increments) end
    ourOut = function(increments) Notch(1, increments) end
    _G.CameraZoomIn, _G.CameraZoomOut = ourIn, ourOut
end

local function Uninstall()
    if not ourIn then return end
    Stop()
    SetCVar("cameraZoomSpeed", DEFAULT_SPEED)
    -- another addon may have replaced them after us: then it keeps its version
    if rawget(_G, "CameraZoomIn") == ourIn then _G.CameraZoomIn = origIn end
    if rawget(_G, "CameraZoomOut") == ourOut then _G.CameraZoomOut = origOut end
    origIn, origOut, ourIn, ourOut = nil, nil, nil, nil
end

function Camera.IsInstalled() return ourIn ~= nil end

-- an earlier build set cameraZoomSpeed to 50 and kept the original in the saved variables:
-- put it back (once) so that nothing of it stays behind
local function RestoreSpeed()
    local st = Misc.Store("camera")
    if st.origSpeed ~= nil then
        SetCVar("cameraZoomSpeed", DEFAULT_SPEED)
        st.origSpeed = nil
    end
end

Misc.OnApply(function()
    local on = Misc:Wanted() and Camera.Get("on")
    if on then Install() BindWheel() else Uninstall() UnbindWheel() end
    RestoreSpeed()
end)

Misc:Reset({ key = "misc", group = "extras", order = 96, accountWide = true,
    label = L["Miscellaneous"],
    desc = L["All functions go back to their defaults."],
    reset = function() RestoreSpeed() ns.Acct().misc = nil end })

Misc:Status(function()
    return L["Miscellaneous: fast zoom %s"]:format(Camera.Get("on") and L["active"] or L["off"])
end)
