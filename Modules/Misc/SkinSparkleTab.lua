-- ---------------------------------------------------------------------------
-- Miscellaneous, tab Skinning: the switch of the glints on skinnable corpses.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, UI = ns.L, ns.UI
local Misc = ns.Misc
local Skin = Misc.SkinSparkle

local W = 300

Misc.AddTab("skinning", L["Skinning"], function(frame)
    UI.Label(frame, L["SKINNABLE CORPSES"], 0, 0)
    local check = UI.CheckRow(frame, L["Sparkle on skinnable corpses"],
        function() return Skin.Get("on") end, function(v) Skin.Set("on", v) end, W)
    check:SetPoint("TOPLEFT", 0, -20)
    local hint = UI.Hint(frame, L["The looted corpse your interact key would skin next sparkles: golden when you can skin it, dim from afar, grey when your skill is too low. Only for characters with Skinning, not during combat."], 600)
    hint:SetPoint("TOPLEFT", 0, -50)
    local needs = UI.Hint(frame, L["Needs the game's Enable Interact Key setting. While the glints show, the corpse's nameplate stays hidden and only the skinning symbol is drawn above them."], 600)
    needs:SetPoint("TOPLEFT", 0, -104)

    function frame:Refresh()
        if check.Refresh then check:Refresh() end
    end
end, 40)
