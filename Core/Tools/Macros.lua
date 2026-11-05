-- ---------------------------------------------------------------------------
-- Macros: what the rest of the addon uses to work with the player's WoW macros
-- (no interface): limits, name and text helpers, the registries for default
-- templates and header buttons, the macro groups, creating a macro and moving
-- it between the general and the character list. The Macro Manager page
-- is MacroManager.lua, its parts are MacroIcons / MacroTransfer / MacroActions.
--   ns.Macros.RegisterTemplates(group)  default templates of a module: { key,
--       title, IsActive(), list = { { name, desc, body } }, Fill(body) }
--   ns.Macros.RegisterAction(action)    header button: { label, width,
--       IsActive(), OnClick(button, mouseButton), Tooltip(button) }
-- The game blocks macro writes in combat, so every write is guarded.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L
local Groups = ns.Transfer.Groups

local Macros = { templates = {}, actions = {} }
ns.Macros = Macros

local NAME_MAX, BODY_MAX = 16, 255
local MAX_GENERAL = MAX_ACCOUNT_MACROS or 120
local MAX_CHAR = MAX_CHARACTER_MACROS or 18
local QUESTION_ICON = 134400   -- the question mark: WoW picks the icon from #showtooltip
Macros.NAME_MAX, Macros.BODY_MAX, Macros.QUESTION_ICON = NAME_MAX, BODY_MAX, QUESTION_ICON
Macros.MAX_CHAR = MAX_CHAR
Macros.IN_COMBAT = L["Macros can't be changed in combat."]

-- old icon APIs return bare names; textures need the full path
local function IconPath(v)
    if type(v) == "string" and not v:find("[/\\]") then return "Interface\\Icons\\" .. v end
    return v
end
Macros.IconPath = IconPath

-- character macros come after the general slots; the count differs between
-- client generations, so check it against a real macro when there is one
local function CharBase()
    local _, numChar = GetNumMacros()
    if (numChar or 0) > 0 and not GetMacroInfo(MAX_GENERAL + 1) then
        for _, base in ipairs({ 120, 36, 72, 54 }) do
            if GetMacroInfo(base + 1) then return base end
        end
    end
    return MAX_GENERAL
end
Macros.CharBase = CharBase

-- the client stores macro text with a trailing newline (and keeps stray
-- trailing spaces): compare what matters, not the bytes
function Macros.SameText(a, b)
    local function norm(s) return ((s or ""):gsub("\r\n", "\n"):gsub("[ \t]+\n", "\n"):gsub("%s+$", "")) end
    return norm(a) == norm(b)
end

-- macro names hold 16 letters at most
function Macros.ShortName(s)
    if not s then return nil end
    return ns.Utf8Sub(s, NAME_MAX)
end

-- every macro with this name, general and character: { index, ... }
function Macros.IndicesByName(name)
    local out = {}
    local numGeneral, numChar = GetNumMacros()
    local base = CharBase()
    local function scan(first, count)
        for i = first, first + (count or 0) - 1 do
            if GetMacroInfo(i) == name then out[#out + 1] = i end
        end
    end
    scan(1, numGeneral)
    scan(base + 1, numChar)
    return out
end

function Macros.RegisterTemplates(group) table.insert(Macros.templates, group) end
function Macros.RegisterAction(action) table.insert(Macros.actions, action) end

-- ---------------------------------------------------------------------------
-- Groups of the two lists (general: account-wide, character: per character)
-- ---------------------------------------------------------------------------
-- { names, collapsed, of = { [macro name] = group } }
function Macros.GroupStore(perChar)
    local owner = perChar and ns.Char() or ns.Acct()
    owner.macroGroups = owner.macroGroups or {}
    local g = owner.macroGroups
    g.names, g.collapsed, g.of = g.names or {}, g.collapsed or {}, g.of or {}
    return g
end

-- puts a macro into a group and creates the group if it isn't there yet
function Macros.SetGroup(name, perChar, group)
    local g = Macros.GroupStore(perChar)
    Groups.Ensure(g, group)
    g.of[name] = Groups.Stored(group)
end

-- ---------------------------------------------------------------------------
-- Creating a macro from outside (the templates page, modules)
-- ---------------------------------------------------------------------------
-- icon: nil = the question mark. Returns the new macro's index, or nil + reason
function Macros.Create(name, text, perChar, icon)
    if ns.InCombat() then return nil, Macros.IN_COMBAT end
    name = Macros.ShortName(ns.Trim(name))
    if name == "" then return nil, L["Enter a name first."] end
    local numGeneral, numChar = GetNumMacros()
    if (perChar and (numChar or 0) >= MAX_CHAR) or (not perChar and (numGeneral or 0) >= CharBase()) then
        return nil, L["This macro list is full."]
    end
    text = ns.Utf8Sub(text or "", BODY_MAX)
    local ok, idx = pcall(CreateMacro, name, icon or QUESTION_ICON, text, perChar)
    if not (ok and idx) and icon then ok, idx = pcall(CreateMacro, name, QUESTION_ICON, text, perChar) end
    if not (ok and idx) then return nil, L["Couldn't create the macro."] end
    return idx
end

-- ---------------------------------------------------------------------------
-- Moving a macro to the other list. The game has no call for it: the macro is
-- created there and deleted here. That takes it off the action bars, so it
-- goes back onto the same buttons afterwards.
-- ---------------------------------------------------------------------------
local MAX_ACTION_SLOT = 180

-- the action slots holding this macro: the id of a macro action isn't always
-- its index, but its action text is its name
local function SlotsOf(name)
    local slots = {}
    local textOf = (C_ActionBar and C_ActionBar.GetActionText) or GetActionText
    for slot = 1, MAX_ACTION_SLOT do
        local kind = GetActionInfo(slot)
        if not ns.IsSecret(kind) and kind == "macro" then
            local text = textOf(slot)
            if not ns.IsSecret(text) and text == name then slots[#slots + 1] = slot end
        end
    end
    return slots
end

-- GetMacroInfo may report the icon a macro shows right now. A "?" macro shows
-- its spell or item, and writing that into the copy would pin it: keep the "?"
local function SavedIcon(index, icon)
    local spell = GetMacroSpell and GetMacroSpell(index)
    if spell and ns.SpellIcon(spell) == icon then return QUESTION_ICON end
    if GetMacroItem then
        local _, link = GetMacroItem(index)
        if link and ns.ItemIcon(link) == icon then return QUESTION_ICON end
    end
    return icon
end

-- toChar: true = into the character list, false = into the general list.
-- The group goes along. Returns the new index and the number of action
-- buttons it went back onto, or nil + reason.
function Macros.Move(index, toChar)
    if ns.InCombat() then return nil, Macros.IN_COMBAT end
    local name, icon, body = GetMacroInfo(index)
    if not name then return nil, L["Couldn't create the macro."] end
    -- one name per list
    for _, idx in ipairs(Macros.IndicesByName(name)) do
        if idx ~= index then return nil, L["A macro named \"%s\" exists already."]:format(name) end
    end
    local slots = SlotsOf(name)
    local from = Macros.GroupStore(not toChar)
    local group = from.of[name]
    local text = (body or ""):gsub("\n$", "")
    local newIndex, why = Macros.Create(name, text, toChar, SavedIcon(index, icon))
    if not newIndex then return nil, why end
    -- the two lists have their own slots: neither index moved
    DeleteMacro(index)
    from.of[name] = nil
    Macros.SetGroup(name, toChar, group)
    for _, slot in ipairs(slots) do
        PickupMacro(newIndex)
        PlaceAction(slot)
        ClearCursor()
    end
    return newIndex, #slots
end

