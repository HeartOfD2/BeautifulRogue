-- ---------------------------------------------------------------------------
-- Rogue module: the options block on the Modules page and the reset category.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, UI = ns.L, ns.UI
local Rogue = ns.Rogue

function Rogue:BuildOptions(box, width)
    local rows = {}
    local function Row(label, field, y, tip)
        local r = UI.CheckRow(box, label,
            function() return Rogue:Settings()[field] ~= false end,
            function(v) Rogue:Settings()[field] = v and true or false end, width)
        r:SetPoint("TOPLEFT", 0, y)
        if tip then UI.Tooltip(r, { label, tip }) end
        rows[#rows + 1] = r
    end
    local STONES_W = 150
    width = width - STONES_W - 10
    Row(L["Warn when a poison runs low (5 minutes or 5 charges)"], "poisonWarn", 0)
    local stones = UI.Button(box, STONES_W, L["Sharpening stones"] .. "  ›", function()
        if Rogue:IsActive() then Rogue:OpenStones() end
    end, 20)
    stones:SetPoint("TOPLEFT", width + 10, 0)
    UI.Tooltip(stones, { L["Sharpening stones"], L["Stone button in the poison tiles, warning, ranking and own items."] })
    local riposte = UI.Button(box, STONES_W, Rogue:RiposteName() .. "  ›", function()
        if Rogue:IsActive() then Rogue:OpenRiposte() end
    end, 20)
    riposte:SetPoint("TOPLEFT", width + 10, -24)
    UI.Tooltip(riposte, function()
        return { L["Icon after a parry"], L["A blinking icon you can place anywhere while %s can be used after a parry, with a sound if you like."]:format(Rogue:RiposteName()) }
    end)
    function Rogue:RefreshOptions()
        for _, r in ipairs(rows) do
            r:Refresh()
            r:SetDisabled(not Rogue:IsActive())   -- the module is switched off
        end
        stones:SetAlpha(Rogue:IsActive() and 1 or 0.4)
        riposte:SetAlpha(Rogue:IsActive() and 1 or 0.4)
        riposte.text:SetText(Rogue:RiposteName() .. "  ›")   -- the name may load late
    end
    return 46
end

Rogue:Reset({ key = "poisons", group = "macros", order = 75, label = L["Poison choices"],
    desc = L["The poison picked for each hand goes back to \"best available\"."],
    reset = function()
        local s = ns.Char().modules.rogue
        if s then s.poison = {} end
    end })
