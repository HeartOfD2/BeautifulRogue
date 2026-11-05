-- ---------------------------------------------------------------------------
-- Saved settings.
--   BeautifulRogueDB       account-wide: minimap button, templates, data of the
--                     modules that serve every character (e.g. their notes)
--   BeautifulRogueCharDB   per character: HUD, layout, cooldowns, texts,
--                     modules (each character has its own class)
-- Reset categories are registered here; the options' Reset tab lists them.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

-- Schema version, stored as `v` in both saved tables. Changing the layout of
-- saved data: raise DB_VERSION and add a step to MIGRATIONS[<old version>] that
-- turns that version into the next one (runs once per table, in order).
local DB_VERSION = 3

-- the sounds of the fixed list before the sound picker: old key -> SOUNDKIT name
local OLD_SOUNDS = {
    raid = "RAID_WARNING", ready = "READY_CHECK", boss = "RAID_BOSS_EMOTE_WARNING",
    bossTell = "UI_RAID_BOSS_WHISPER_WARNING", ping = "MAP_PING", tell = "TELL_MESSAGE",
    gm = "GM_CHAT_WARNING", alarm1 = "ALARM_CLOCK_WARNING_1", alarm2 = "ALARM_CLOCK_WARNING_2",
    alarm3 = "ALARM_CLOCK_WARNING_3", tick = "UI_BATTLEGROUND_COUNTDOWN_TIMER",
    go = "UI_BATTLEGROUND_COUNTDOWN_FINISHED", bg = "PVP_THROUGH_QUEUE", role = "LFG_ROLE_CHECK",
    reward = "LFG_REWARDS", trap = "UI_PET_BATTLES_TRAP_READY", quest = "IG_QUEST_LIST_COMPLETE",
    questAuto = "UI_AUTO_QUEST_COMPLETE", coins = "LOOT_WINDOW_COIN_SOUND", invite = "IG_PLAYER_INVITE",
    auction = "AUCTION_WINDOW_OPEN",
}

local MIGRATIONS = {
    -- [n] = function(db) ... end   upgrades data from n to n + 1
    char = {
        -- 1 -> 2: the number of cooldown bars is a setting now (there were always five;
        -- keep as many as hold a cooldown, at least one)
        [1] = function(db)
            local c = db.cooldowns
            if type(c) ~= "table" or c.bars ~= nil then return end
            local n = 1
            if type(c.bar) == "table" then
                for _, b in pairs(c.bar) do
                    if type(b) == "number" and b > n then n = b end
                end
            end
            c.bars = math.min(n, 20)
        end,
        -- 2 -> 3: sounds are stored by their SOUNDKIT name (sound picker); the old
        -- list keys of the combo and threat sounds become the names they played
        [2] = function(db)
            local parts = type(db.style) == "table" and db.style.parts
            if type(parts) ~= "table" then return end
            for _, key in ipairs({ "combo", "threat" }) do
                local p = parts[key]
                if type(p) == "table" and type(p.sound) == "string" and OLD_SOUNDS[p.sound] then
                    p.sound = OLD_SOUNDS[p.sound]
                end
            end
        end,
    },
    acct = {},
}

local function CharDefaults()
    return {
        v = DB_VERSION,
        hud = { locked = true, scale = 1, centerX = false, pos = nil, hide = "never", holdKey = "ALT" },
        layout = { order = nil, hidden = {} },
        style = { frame = {}, parts = {} },
        cooldowns = { order = nil, hidden = {}, shown = {}, bar = {}, bars = 1, custom = {} },
        text = { health = "{cur} ({pct}%)", power = "{cur}" },
        range = { interval = 0.2 },
        swing = { seen = {} },   -- swing bars (off hand, ranged) the game has reported for this character
        modules = {},
        ui = {},
    }
end

local function AcctDefaults()
    return {
        v = DB_VERSION,
        minimap = { angle = 200, hide = false },
    }
end

-- fill in what is missing, keep what the player set
local function Merge(saved, defaults)
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            saved[k] = ns.CopyTable(v)
        elseif type(v) == "table" and type(saved[k]) == "table" then
            Merge(saved[k], v)
        end
    end
    return saved
end

local function Migrate(db, steps)
    local v = tonumber(db.v) or 1
    while v < DB_VERSION do
        local step = steps[v]
        if step then step(db) end
        v = v + 1
    end
    db.v = DB_VERSION
end

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[DeepCopy(k)] = DeepCopy(x) end
    return out
end

-- The addon was called EverFrame up to 1.0. Its saved data is loaded by the small "EverFrame" folder in the package
-- (or by the old addon while it is still installed) and taken over once, when nothing of our own is saved yet.
local function TakeOverEverFrame()
    local took = false
    if type(BeautifulRogueDB) ~= "table" and type(EverFrameDB) == "table" then
        BeautifulRogueDB = DeepCopy(EverFrameDB)
        took = true
    end
    if type(BeautifulRogueCharDB) ~= "table" and type(EverFrameCharDB) == "table" then
        BeautifulRogueCharDB = DeepCopy(EverFrameCharDB)
        took = true
    end
    ns.tookOverEverFrame = took
end

function ns.InitDatabase()
    TakeOverEverFrame()
    if type(BeautifulRogueDB) ~= "table" then BeautifulRogueDB = {} end
    if type(BeautifulRogueCharDB) ~= "table" then BeautifulRogueCharDB = {} end
    Migrate(BeautifulRogueDB, MIGRATIONS.acct)
    Migrate(BeautifulRogueCharDB, MIGRATIONS.char)
    Merge(BeautifulRogueDB, AcctDefaults())
    Merge(BeautifulRogueCharDB, CharDefaults())
    -- early test builds had a single "hide out of combat" switch
    local h = BeautifulRogueCharDB.hud
    if h.hideOOC ~= nil then
        if h.hideOOC then h.hide = "combat" end
        h.hideOOC = nil
    end
end

-- before ADDON_LOADED (only during file load) the defaults stand in
local fallbackChar, fallbackAcct
function ns.Char()
    if type(BeautifulRogueCharDB) == "table" and ns.dbReady then return BeautifulRogueCharDB end
    fallbackChar = fallbackChar or CharDefaults()
    return fallbackChar
end
function ns.Acct()
    if type(BeautifulRogueDB) == "table" and ns.dbReady then return BeautifulRogueDB end
    fallbackAcct = fallbackAcct or AcctDefaults()
    return fallbackAcct
end

-- ---------------------------------------------------------------------------
-- Reset categories: { key, group, label, desc, order, accountWide, danger, reset() }
-- group is the section of the app window the setting belongs to (hud, macros, extras,
-- addon); the reset page lists them under the same headings.
-- ---------------------------------------------------------------------------
ns.resetCategories = {}

function ns.RegisterReset(def)
    table.insert(ns.resetCategories, def)
    table.sort(ns.resetCategories, function(a, b) return (a.order or 50) < (b.order or 50) end)
end

-- resets the given keys, then tells every part of the addon to re-read
function ns.ResetCategories(keys)
    local done = {}
    for _, def in ipairs(ns.resetCategories) do
        if keys[def.key] then
            def.reset()
            done[#done + 1] = def.label
        end
    end
    if #done > 0 then ns.Fire("SETTINGS_RESET", keys) end
    return done
end

do
    local D = CharDefaults()
    ns.RegisterReset({ key = "position", group = "hud", order = 10, label = L["Position and scale"],
        desc = L["Frame position, scale, lock and horizontal centering."],
        reset = function()
            local h = ns.Char().hud
            h.pos, h.scale, h.locked, h.centerX = nil, D.hud.scale, D.hud.locked, D.hud.centerX
        end })
    ns.RegisterReset({ key = "layout", group = "hud", order = 20, label = L["Layout"],
        desc = L["Order, visibility and look of the frame parts."],
        reset = function()
            ns.Char().layout = ns.CopyTable(D.layout)
            ns.Char().style = ns.CopyTable(D.style)
        end })
    ns.RegisterReset({ key = "cooldowns", group = "hud", order = 30, label = L["Cooldown bars"],
        desc = L["Which cooldowns show, their bar and order, and the number of bars. Your own entries stay."],
        reset = function()
            local c = ns.Char().cooldowns
            c.order, c.hidden, c.shown, c.bar, c.bars = nil, {}, {}, {}, D.cooldowns.bars
        end })
    ns.RegisterReset({ key = "customCooldowns", group = "hud", order = 31, label = L["Own cooldown entries"],
        desc = L["Removes the items and spells you added yourself."],
        reset = function() ns.Char().cooldowns.custom = {} end })
    ns.RegisterReset({ key = "texts", group = "hud", order = 40, label = L["Texts"],
        desc = L["Health and resource text formats."],
        reset = function() ns.Char().text = ns.CopyTable(D.text) end })
    ns.RegisterReset({ key = "visibility", group = "hud", order = 50, label = L["Visibility"],
        desc = L["When the frame hides and the hold-to-show key."],
        reset = function()
            local h = ns.Char().hud
            h.hide, h.holdKey = D.hud.hide, D.hud.holdKey
        end })
    ns.RegisterReset({ key = "range", group = "hud", order = 60, label = L["Range display"],
        desc = L["How often the range is checked."],
        reset = function() ns.Char().range = ns.CopyTable(D.range) end })
    ns.RegisterReset({ key = "modules", group = "addon", order = 70, label = L["Modules"],
        desc = L["Module on/off switches and module settings."],
        reset = function() ns.Char().modules = {} end })
    ns.RegisterReset({ key = "minimap", group = "addon", order = 80, label = L["Minimap button"], accountWide = true,
        desc = L["Position and visibility of the minimap button."],
        reset = function() ns.Acct().minimap = ns.CopyTable(AcctDefaults().minimap) end })
    ns.RegisterReset({ key = "appearance", group = "addon", order = 82, label = L["Appearance"], accountWide = true,
        desc = L["Dark mode, accent color and font go back to the defaults (the font after a reload)."],
        reset = function()
            local a = ns.Acct()
            a.theme, a.font = nil, nil
            ns.ApplyTheme()
        end })
    ns.RegisterReset({ key = "windows", group = "addon", order = 85, label = L["Window positions"], accountWide = true,
        desc = L["Position and size of the app window and the other BeautifulRogue windows."],
        -- modules put their own windows back on SETTINGS_RESET (keys.windows)
        reset = function() ns.Acct().app = nil end })
end

