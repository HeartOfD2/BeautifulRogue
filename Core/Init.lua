-- ---------------------------------------------------------------------------
-- BeautifulRogue: namespace, event dispatch, internal messages, chat output and
-- the login lifecycle. Every other file builds on what this one sets up.
-- (Modules: Core/Module.lua.)
-- ---------------------------------------------------------------------------
local ADDON, ns = ...

ns.ADDON = ADDON
ns.TITLE = "BeautifulRogue"
ns.LOCALE = GetLocale and GetLocale() or "enUS"

do
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = getMeta and getMeta(ADDON, "Version")
    -- the TOC carries the version (make_release.py --version sets it for a release)
    ns.VERSION = (type(v) == "string" and v ~= "" and not v:find("^@")) and v or "?"
end

-- Localization: English text is the key. Missing translations fall back to it.
ns.L = setmetatable({}, { __index = function(_, k) return k end })

-- ---------------------------------------------------------------------------
-- Errors inside one handler must not stop the others
-- ---------------------------------------------------------------------------
local function Report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) else print(err) end
end

local function SafeCall(fn, ...)
    local n = select("#", ...)
    local args = { ... }
    local ok, err = pcall(function() return fn(unpack(args, 1, n)) end)
    if not ok then Report(err) end
end
ns.SafeCall = SafeCall

-- ---------------------------------------------------------------------------
-- Game events: any number of subscribers per event, one shared frame
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventSubs = {}

function ns.RegisterEvent(event, fn)
    local list = eventSubs[event]
    if not list then
        -- unknown events (other client generations) are skipped quietly
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        list = {}
        eventSubs[event] = list
    end
    list[#list + 1] = fn
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventSubs[event]
    if not list then return end
    for i = 1, #list do SafeCall(list[i], event, ...) end
end)

-- unit events get a frame of their own so the game filters the unit for us
function ns.RegisterUnitEvent(event, unit, fn)
    local f = CreateFrame("Frame")
    if not pcall(f.RegisterUnitEvent, f, event, unit) then return false end
    f:SetScript("OnEvent", function(_, ev, ...) SafeCall(fn, ev, ...) end)
    return true
end

-- ---------------------------------------------------------------------------
-- Internal messages between the files (settings changed, reset, ...)
-- ---------------------------------------------------------------------------
local messageSubs = {}
function ns.On(message, fn)
    messageSubs[message] = messageSubs[message] or {}
    table.insert(messageSubs[message], fn)
end
function ns.Fire(message, ...)
    local list = messageSubs[message]
    if not list then return end
    for i = 1, #list do SafeCall(list[i], ...) end
end

-- ---------------------------------------------------------------------------
-- Chat output
-- ---------------------------------------------------------------------------
local PREFIX = "|cffffd140" .. ns.TITLE .. ":|r "
function ns.Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    print(PREFIX .. msg)
end

-- ---------------------------------------------------------------------------
-- Player info (class may only be final at PLAYER_LOGIN on some clients)
-- ---------------------------------------------------------------------------
local function ReadPlayer()
    local _, class = UnitClass("player")
    ns.playerClass = class
    if UnitRace then
        local _, race = UnitRace("player")
        ns.playerRace = race
    end
end
ReadPlayer()

-- ---------------------------------------------------------------------------
-- Lifecycle
--   ADDON_LOADED (ours)  saved variables exist   -> "DB_READY"
--   PLAYER_LOGIN         the world is about      -> "LOGIN", modules start
-- ---------------------------------------------------------------------------
ns.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON or ns.dbReady then return end
    ns.dbReady = true
    ns.InitDatabase()
    ns.Fire("DB_READY")
end)

-- The former name EverFrame: one chat line after the takeover of its settings, and a hint while the old addon (not
-- the small transfer folder "EverFrame" of the package, which says X-Transfer in its TOC) still runs.
function ns.NoticeFormerName()
    local A = C_AddOns
    local loaded = A and A.IsAddOnLoaded and A.IsAddOnLoaded("EverFrame")
    local transfer = A and A.GetAddOnMetadata and A.GetAddOnMetadata("EverFrame", "X-Transfer")
    if loaded and not transfer then
        ns.Print(ns.L["EverFrame is now BeautifulRogue. Please disable the old addon EverFrame and reload."])
    elseif ns.tookOverEverFrame then
        ns.Print(ns.L["EverFrame is now BeautifulRogue: your settings were taken over."])
    end
end

ns.RegisterEvent("PLAYER_LOGIN", function()
    if not ns.dbReady then   -- should not happen, but never run without settings
        ns.dbReady = true
        ns.InitDatabase()
        ns.Fire("DB_READY")
    end
    ReadPlayer()
    ns.NoticeFormerName()
    ns.ready = true
    ns.Fire("LOGIN")
    ns.RefreshModules()
end)
