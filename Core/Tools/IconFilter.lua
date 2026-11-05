-- ---------------------------------------------------------------------------
-- Macro Manager: icon names and categories for the icon picker.
-- The data (public domain) lives in the load-on-demand addon
-- BeautifulRogue_IconData and is only loaded when the picker opens. Categories are
-- bit fields in the per-icon "tags" list: every icon owns `stride` consecutive
-- 32-bit numbers, category N is bit (N % 32) of number (N // 32) + 1.
-- No UI here; MacroIcons.lua drives it.
-- ---------------------------------------------------------------------------
local _, ns = ...
local IconFilter = {}
ns.IconFilter = IconFilter

local ADDON = "BeautifulRogue_IconData"
local FIELD_WIDTH = 32
local FILE_ID_LIMIT = 0x04000000   -- bigger IDs are atlases, not texture files
local STEP = 3000                  -- icons checked per frame

local data, count, stride = nil, 0, 1
local loadFailed = false

function IconFilter.Load()
    if data then return true end
    if loadFailed then return false end
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn -- lint:ignore
    if load then pcall(load, ADDON) end
    local d = _G.BeautifulRogueIconData
    if type(d) ~= "table" or type(d.id) ~= "table" or type(d.name) ~= "table"
        or type(d.tags) ~= "table" or type(d.categories) ~= "table" then
        loadFailed = true
        return false
    end
    local n = 0
    for _ in pairs(d.categories) do n = n + 1 end
    data, count, stride = d, #d.id, math.max(1, math.ceil(n / FIELD_WIDTH))
    return true
end

function IconFilter.Available() return data ~= nil end

-- index of a file ID in the (sorted) ID list
local function IndexOf(id)
    local ids, lo, hi = data.id, 1, count
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local v = ids[mid]
        if v == id then return mid end
        if v < id then lo = mid + 1 else hi = mid - 1 end
    end
end

function IconFilter.NameOf(id)
    if not data then return nil end
    local i = IndexOf(id)
    return i and data.name[i] or nil
end

-- Categories of one menu group (IconFilter.groupOf[key]) add up: sword OR dagger.
-- Different groups narrow each other down: Abilities AND Rogue shows the rogue abilities.
IconFilter.groupOf = {}

-- selected = { [categoryKey] = true } -> list of groups, each a list of { field offset, divisor }
local function Tests(selected)
    local byGroup, groups = {}, {}
    if data and selected then
        for key in pairs(selected) do
            local cat = data.categories[key]
            if cat then
                local gid = IconFilter.groupOf[key] or key
                local g = byGroup[gid]
                if not g then g = {} byGroup[gid] = g groups[#groups + 1] = g end
                g[#g + 1] = { math.floor(cat / FIELD_WIDTH) + 1, 2 ^ (cat % FIELD_WIDTH) }
            end
        end
    end
    return groups
end

local function Passes(groups, index)
    if #groups == 0 then return true end
    local base = (index - 1) * stride
    local tags = data.tags
    for _, tests in ipairs(groups) do
        local any = false
        for _, t in ipairs(tests) do
            if math.floor((tags[base + t[1]] or 0) / t[2]) % 2 == 1 then any = true break end
        end
        if not any then return false end
    end
    return true
end

-- true/false: does this icon fit the selected categories (see above)? nil: unknown icon
function IconFilter.InCategories(id, selected)
    if not data then return nil end
    local i = IndexOf(id)
    if not i then return nil end
    return Passes(Tests(selected), i)
end

-- lowercase, blanks and dashes become "_" (names look like "inv_sword_01")
function IconFilter.Normalize(text)
    return (ns.Fold(ns.Trim(text or "")):gsub("[%s%-]+", "_"))
end

-- Searches in portions over several frames. opts = { query = <normalized>, selected = { key = true },
-- onUpdate = function(list, done, progress) }. A new Start cancels the running search.
local runner = CreateFrame("Frame")
runner:Hide()
local job

local function Step()
    local j = job
    local last = math.min(count, j.pos + STEP - 1)
    local ids, names = data.id, data.name
    for i = j.pos, last do
        local id = ids[i]
        if id < FILE_ID_LIMIT and Passes(j.tests, i) then
            if j.query == "" then
                j.rest[#j.rest + 1] = id
            elseif j.digits then
                if tostring(id):find(j.query, 1, true) then j.rest[#j.rest + 1] = id end
            else
                local pos = names[i]:find(j.query, 1, true)
                if pos == 1 then j.first[#j.first + 1] = id
                elseif pos then j.rest[#j.rest + 1] = id end
            end
        end
    end
    j.pos = last + 1
end

runner:SetScript("OnUpdate", function(self)
    if not job then self:Hide() return end
    Step()
    local j = job
    local done = j.pos > count
    local list = {}
    for _, v in ipairs(j.first) do list[#list + 1] = v end
    for _, v in ipairs(j.rest) do list[#list + 1] = v end
    if done then job = nil self:Hide() end
    j.onUpdate(list, done, math.min(1, (j.pos - 1) / count))
end)

function IconFilter.Start(opts)
    if not data then return false end
    job = {
        query = opts.query or "", tests = Tests(opts.selected), onUpdate = opts.onUpdate,
        digits = (opts.query or ""):match("^%d+$") ~= nil, pos = 1, first = {}, rest = {},
    }
    runner:Show()
    return true
end

function IconFilter.Cancel()
    job = nil
    runner:Hide()
end
