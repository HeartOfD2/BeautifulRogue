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
    Row(L["Warn when a poison runs low (5 minutes or 5 charges)"], "poisonWarn", 0)

    -- each feature has a checkbox in front of its button; off = nothing of it runs (see Rogue.lua)
    local BTN_W, CHECK_W = 150, 96
    local function FeatureRow(key, y, tip)
        local r = UI.CheckRow(box, L["Enabled"],
            function() return Rogue:Settings()[Rogue.features[key].setting] ~= false end,
            function(v)
                Rogue:SetFeature(key, v)
                Rogue:RefreshOptions()   -- the button beside it greys out or not
            end, CHECK_W)
        r:SetPoint("TOPLEFT", 0, y)
        UI.Tooltip(r, tip)
        rows[#rows + 1] = r
        return r
    end
    FeatureRow("stones", -24, { L["Sharpening stones"],
        L["Off: no stone button in the poison tiles, no warning, no ranking, and nothing is read for the stones."] })
    local stones = UI.Button(box, BTN_W, L["Sharpening stones"] .. "  ›", function()
        if Rogue:StonesOn() then Rogue:OpenStones() end
    end, 20)
    stones:SetPoint("TOPLEFT", CHECK_W + 8, -24)
    UI.Tooltip(stones, { L["Sharpening stones"], L["Stone button in the poison tiles, warning, ranking and own items."] })
    FeatureRow("riposte", -48, function()
        return { Rogue:RiposteName(), L["Off: no icon, no sound, and the fight is not followed for it."] }
    end)
    local riposte = UI.Button(box, BTN_W, Rogue:RiposteName() .. "  ›", function()
        if Rogue:RiposteOn() then Rogue:OpenRiposte() end
    end, 20)
    riposte:SetPoint("TOPLEFT", CHECK_W + 8, -48)
    UI.Tooltip(riposte, function()
        return { L["Icon after a parry"], L["A blinking icon you can place anywhere while %s can be used after a parry, with a sound if you like."]:format(Rogue:RiposteName()) }
    end)
    function Rogue:RefreshOptions()
        for _, r in ipairs(rows) do
            r:Refresh()
            r:SetDisabled(not Rogue:IsActive())   -- the module is switched off
        end
        stones:SetAlpha(Rogue:StonesOn() and 1 or 0.4)      -- greyed out while switched off
        riposte:SetAlpha(Rogue:RiposteOn() and 1 or 0.4)
        riposte.text:SetText(Rogue:RiposteName() .. "  ›")   -- the name may load late
    end
    return 70
end

Rogue:Reset({ key = "poisons", group = "macros", order = 75, label = L["Poison choices"],
    desc = L["The poison picked for each hand goes back to \"best available\"."],
    reset = function()
        local s = ns.Char().modules.rogue
        if s then s.poison = {} end
    end })
