-- ---------------------------------------------------------------------------
-- Notes: a notebook (colored groups holding notes) plus player notes (several
-- per player, kept under Name-Realm). Targeting a player pops their notes up
-- in a small window you can move, resize and lock; players without notes get
-- a slim "+ Note" bar there instead. Every note has a title plus created and
-- updated times. Saved account-wide; unit data is screened for secret values.
-- Any note can also sit on the screen as a sticky note (Stickies.lua), and
-- notes travel as a text code (Export / Import).
--
-- The notes are the module `notes` (every class, on by default). Switched off,
-- the page, sticky notes, popup, commands, the minimap Shift-click and the
-- block on the General page go away; the saved notes stay (account-wide).
--
-- The module is split over several files that share only the public ns.Notes table: Notes.lua (module + data), NoteEditor.lua (editor),
-- NotesPopup.lua (target popup), NotesView.lua (tree + editor view), NotesPage.lua (the page), NotesTransfer.lua (export / import),
-- Stickies.lua, StickyDock.lua, StickySettings.lua (sticky notes), Options.lua (settings, commands, reset).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, T, HEX = ns.L, ns.T, ns.HEX
local IsBlank = ns.IsBlank

local Module = ns.NewModule("notes", {
    title = L["Notes"],
    desc = L["Notebook, player notes on target and sticky notes. Switched off, your notes stay saved."],
    classes = nil,          -- every class
    defaultEnabled = true,
})

-- group colors: the theme's tag palette (red, orange, amber, green, teal,
-- blue, violet, pink, gray, cyan), tuned per mode
local PALETTE = T.tags
-- dates follow the language of the addon's texts (the choice on the Appearance page), like the words around them
local DATE_LONG = ns.LOCALE == "deDE" and "%d.%m.%Y %H:%M" or "%Y-%m-%d %H:%M"
local DATE_SHORT = ns.LOCALE == "deDE" and "%d.%m." or "%m-%d"

local function Now() return time and time() or 0 end
local function Stamp(t, short)
    if not t or t == 0 or not date then return "" end
    return date(short and DATE_SHORT or DATE_LONG, t)
end
local function Hex(c) return ("ff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
local function Untitled(n) return (n.title and n.title ~= "") and n.title or L["(untitled)"] end

-- ---------------------------------------------------------------- storage
local NOTES_VERSION = 2

local function Migrate(d)
    -- a single notepad (older format) becomes the first note of a "General" group
    if not d.groups then
        d.groups = { { name = L["General"], color = 3, seq = 0, notes = {} } }
        if not IsBlank(d.pad) then
            local g = d.groups[1]
            g.seq = 1
            g.notes[1] = { title = L["Notepad"], text = d.pad, created = Now(), updated = Now(), titled = true }
        end
    end
    d.pad = nil
    -- one text per player (older format) -> that player's first note
    for key, p in pairs(d.players) do
        if not p.notes then
            p.notes = {}
            if not IsBlank(p.text) then
                p.notes[1] = { title = L["Note %d"]:format(1), text = p.text, created = p.t or Now(), updated = p.t or Now() }
            end
            p.seq, p.text, p.t = #p.notes, nil, nil
        end
        if #p.notes == 0 then d.players[key] = nil end
    end
    d.v = NOTES_VERSION
end

local function DB()
    local acct = ns.Acct()
    local d = acct.notes
    if type(d) ~= "table" then
        d = {}
        acct.notes = d
    end
    d.players = d.players or {}
    if d.v ~= NOTES_VERSION then Migrate(d) end
    return d
end

local function NewNote(container)
    container.seq = (container.seq or #container.notes) + 1
    local n = { title = L["Note %d"]:format(container.seq), text = "", created = Now(), updated = Now() }
    table.insert(container.notes, n)
    return n
end

local function RemoveNote(container, note)
    local i = ns.IndexOf(container.notes, note)
    if i then table.remove(container.notes, i) end
    return i
end

local function IsSticky(note) return note and note.sticky and note.sticky.open and true or false end

-- a fresh note nobody wrote into (no text, default title) goes away again
-- (unless it sits on the screen as a sticky note)
local function Discard(container, note)
    if container and note and IsBlank(note.text) and not note.titled and not IsSticky(note)
            and ns.IndexOf(container.notes, note) then
        RemoveNote(container, note)
        return true
    end
end

local function Touch(note) note.updated = Now() end

local function Latest(container)
    local best
    for _, n in ipairs(container.notes) do
        if not best or (n.updated or 0) >= (best.updated or 0) then best = n end
    end
    return best
end

-- ---------------------------------------------------------------- players
local function MyRealm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if not r or r == "" then r = ((GetRealmName and GetRealmName()) or ""):gsub("[%s%-]", "") end
    return r
end

-- class colors; darker in light mode so white and yellow names stay readable
local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return "ff" .. HEX.value end
    if T.mode == "light" then return Hex({ c.r * 0.62, c.g * 0.62, c.b * 0.62 }) end
    return c.colorStr or Hex({ c.r, c.g, c.b })
end

local function DisplayName(p, short)
    local n = p.name or "?"
    if not short and p.realm and p.realm ~= MyRealm() then n = n .. "-" .. p.realm end
    return "|c" .. ClassHex(p.class) .. n .. "|r"
end

-- current target as a note key ("Name-Realm") + info; players only
local function TargetKey()
    if not UnitExists("target") then return end
    local isPlayer = UnitIsPlayer("target")
    if ns.IsSecret(isPlayer) or not isPlayer then return end
    local name, realm = UnitName("target")
    if ns.IsSecret(name) or ns.IsSecret(realm) or not name then return end
    if not realm or realm == "" then realm = MyRealm() end
    local _, class = UnitClass("target")
    if ns.IsSecret(class) then class = nil end
    return name .. "-" .. realm, { name = name, realm = realm, class = class }
end

local function Player(key) return key and DB().players[key] end

local function EnsurePlayer(key, info)
    local players = DB().players
    local p = players[key]
    if not p then
        p = { notes = {}, seq = 0 }
        players[key] = p
    end
    if info then
        p.name, p.realm = info.name, info.realm
        p.class = info.class or p.class
    end
    p.name = p.name or key:match("^(.-)%-") or key
    p.realm = p.realm or key:match("%-(.+)$")
    return p
end

local function DropPlayerIfEmpty(key)
    local p = Player(key)
    if p and #p.notes == 0 then DB().players[key] = nil end
end

local function KeyOf(p)
    for k, v in pairs(DB().players) do if v == p then return k end end
end

-- views register here and redraw when another view changed the data
local listeners = {}
local function Changed(source)
    for _, fn in ipairs(listeners) do fn(source) end
end

-- ---------------------------------------------------------------------------
-- For the sticky notes and the export: where a note lives, its color, name
-- ---------------------------------------------------------------------------
local Notes = { DB = DB, Untitled = Untitled, Touch = Touch, Stamp = Stamp, Changed = Changed, module = Module }
ns.Notes = Notes
-- the data model, used by the other Notes files and the sticky notes
Notes.PALETTE = PALETTE
Notes.Now, Notes.Hex, Notes.IsSticky, Notes.Discard = Now, Hex, IsSticky, Discard
Notes.NewNote, Notes.RemoveNote, Notes.Latest = NewNote, RemoveNote, Latest
Notes.DisplayName, Notes.TargetKey, Notes.Player, Notes.EnsurePlayer = DisplayName, TargetKey, Player, EnsurePlayer
Notes.DropPlayerIfEmpty, Notes.KeyOf = DropPlayerIfEmpty, KeyOf
function Notes.OnChange(fn) listeners[#listeners + 1] = fn end

-- ---------------------------------------------------------------------------
-- In combat the sticky notes and the target popup can step aside, each with
-- its own switch (DB().hideInCombat); the HUD's "hold to show" key brings
-- them back while held, if wanted (DB().holdShowsNotes). Each sits on its
-- own layer frame, so hiding keeps every note's own shown state. With the
-- module off, every layer stays hidden.
-- ---------------------------------------------------------------------------
local layers = {}
function Notes.Layer(key)
    local f = CreateFrame("Frame", "BeautifulRogueNotesLayer_" .. key, UIParent)
    f:SetAllPoints(UIParent)
    layers[key] = f
    if Notes.UpdateLayers then Notes.UpdateLayers() end
    return f
end
function Notes.HideInCombat(key)
    local d = DB()
    d.hideInCombat = d.hideInCombat or {}
    return d.hideInCombat[key] and true or false
end
function Notes.SetHideInCombat(key, on)
    local d = DB()
    d.hideInCombat = d.hideInCombat or {}
    d.hideInCombat[key] = on and true or nil
    Notes.UpdateLayers()
end
function Notes.HoldShows() return DB().holdShowsNotes and true or false end

-- Layers follow the combat events. Only the hold-to-show key has no event, so
-- it is polled while it can matter: in combat, and only if the player wants it.
local layerDriver = CreateFrame("Frame")
local pollElapsed = 0
-- The events set their own flag: InCombatLockdown() can still say "no" while
-- PLAYER_REGEN_DISABLED runs, which left the notes shown during the whole fight.
local combatEvent = false
local function InFight() return combatEvent or ns.InCombat() end
local function ApplyLayers()
    local active = Module:IsActive()
    local inCombat = InFight()
    local held = inCombat and DB().holdShowsNotes and ns.HUD:IsHoldKeyDown()
    for key, layer in pairs(layers) do
        local show = active and (not (inCombat and Notes.HideInCombat(key)) or held) or false
        if layer:IsShown() ~= show then layer:SetShown(show) end
    end
end
local function PollHeldKey(_, elapsed)
    pollElapsed = pollElapsed + elapsed
    if pollElapsed < 0.05 then return end
    pollElapsed = 0
    ApplyLayers()
end
local function UpdateLayers()
    if not ns.ready then return end
    ApplyLayers()
    local poll = Module:IsActive() and InFight() and DB().holdShowsNotes
    layerDriver:SetScript("OnUpdate", poll and PollHeldKey or nil)
end
Notes.UpdateLayers = UpdateLayers
function Notes.SetHoldShows(on)
    DB().holdShowsNotes = on and true or nil
    UpdateLayers()
end
-- the "hold to show" switch; it sits on the player tab and the sticky note tab and is the same setting
function Notes.HoldShowsRow(parent, width)
    local row = ns.UI.CheckRow(parent, L["Holding the key shows them too"], Notes.HoldShows,
        function(v) Notes.SetHoldShows(v) end, width)
    ns.UI.Tooltip(row, { L["Holding the key shows them too"],
        L["The key of \"Hold to show\" (HUD › Position & visibility) brings hidden notes back while you hold it."] })
    return row
end
Module:Event("PLAYER_REGEN_DISABLED", function() combatEvent = true UpdateLayers() end)
Module:Event("PLAYER_REGEN_ENABLED", function() combatEvent = false UpdateLayers() end)
ns.On("LOGIN", function() combatEvent = ns.InCombat() UpdateLayers() end)

-- switched on or off (Modules page, reset): layers follow, the popup looks at
-- the current target again
function Module:OnActiveChanged(active)
    combatEvent = ns.InCombat()   -- (the events don't reach a module that is off)
    UpdateLayers()
    if active and Notes.RefreshPopup then Notes.RefreshPopup() end
end

-- fn(note, kind, container, key): kind "g" = notebook group, "p" = player
function Notes.ForEach(fn)
    for _, g in ipairs(DB().groups) do
        for _, n in ipairs(g.notes) do fn(n, "g", g) end
    end
    for key, p in pairs(DB().players) do
        for _, n in ipairs(p.notes) do fn(n, "p", p, key) end
    end
end

function Notes.Owner(note)
    for _, g in ipairs(DB().groups) do
        if ns.IndexOf(g.notes, note) then return "g", g end
    end
    for key, p in pairs(DB().players) do
        if ns.IndexOf(p.notes, note) then return "p", p, key end
    end
end

function Notes.Color(kind, container)
    if kind == "g" then return PALETTE[container.color] or PALETTE[3] end
    local c = container and container.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[container.class]
    return c and { c.r, c.g, c.b } or { 0.62, 0.65, 0.70 }
end

-- the group name or the player's name, plain text
function Notes.OwnerName(kind, container)
    if kind == "g" then return (container.name ~= "") and container.name or L["(group)"] end
    return container.name or "?"
end

-- drop empty leftovers from earlier sessions
ns.On("LOGIN", function()
    local d = DB()
    for key, p in pairs(d.players) do
        for i = #p.notes, 1, -1 do
            local n = p.notes[i]
            if IsBlank(n.text) and not n.titled and not IsSticky(n) then table.remove(p.notes, i) end
        end
        if #p.notes == 0 then d.players[key] = nil end
    end
end)

-- ---------------------------------------------------------------------------
-- Export / import as one line of text: "EFN1:" + Base64; one record per note
-- with kind ("g" = notebook group, "p" = player), its group name or
-- Name-Realm, group color or class, title, text, created and updated time
-- ---------------------------------------------------------------------------
local CODE_PREFIX, CODE_FIELDS = "EFN1:", 7

function Notes.Encode(list)
    local records = {}
    for i, n in ipairs(list) do
        records[i] = { n.kind, n.owner, n.extra, n.title, n.text, n.created, n.updated }
    end
    return ns.EncodeRecords(CODE_PREFIX, records, CODE_FIELDS)
end

-- list of { kind, owner, extra, title, text, created, updated }, or nil + reason
function Notes.Decode(text)
    local records, why = ns.DecodeRecords(text, CODE_PREFIX, CODE_FIELDS)
    if not records then return nil, why end
    local list = {}
    for i, f in ipairs(records) do
        if (f[1] ~= "g" and f[1] ~= "p") or ns.Trim(f[2]) == "" then return nil, "data" end
        list[i] = { kind = f[1], owner = f[2], extra = f[3] ~= "" and f[3] or nil, title = f[4],
                    text = f[5], created = tonumber(f[6]), updated = tonumber(f[7]) }
    end
    return list
end
