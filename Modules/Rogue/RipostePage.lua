-- ---------------------------------------------------------------------------
-- Window "Riposte" (rogue module): the Riposte icon on or off, blinking, size,
-- sound and position. While the window is open the icon shows as a preview
-- and can be dragged; closing the window locks it again.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, HEX, UI = ns.L, ns.HEX, ns.UI
local Rogue = ns.Rogue

local WIN_W, WIN_H = 340, 404
local COL_W = WIN_W - 28

local Render

-- texts with the spell's name: set on every Render, the client may load the
-- name only after the window was built
local HINT = "The icon shows while you can use %s after a parry, and hides when you use it or the chance is gone. While this window is open it shows all the time: drag it with the left mouse button."
local SHOW, SHOW_TIP = "Show the %s icon", "Shows the icon while %s can be used. Off: no icon and no sound."

local function BuildPage(p)
    local hint = UI.Hint(p, "", COL_W)
    hint:SetPoint("TOPLEFT", 0, 0)

    local checks = {}
    local function Check(label, field, tip)
        local c = UI.CheckRow(p, label,
            function() return Rogue:RiposteGet(field) and true or false end,
            function(v) Rogue:SetRiposte(field, v and true or false) end, COL_W)
        UI.Tooltip(c, { label, tip })
        checks[#checks + 1] = c
        return c
    end
    local onCheck = Check("", "on", "")
    UI.Tooltip(onCheck, function()
        local name = Rogue:RiposteName()
        return { L[SHOW]:format(name), L[SHOW_TIP]:format(name) }
    end)
    onCheck:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
    local blinkCheck = Check(L["Blink"], "blink", L["The icon blinks while it shows; off: it stays still."])
    blinkCheck:SetPoint("TOPLEFT", onCheck, "BOTTOMLEFT", 0, -4)

    local size = UI.ValueSlider(p, L["Size"], Rogue.RIPOSTE_SIZE_MIN, Rogue.RIPOSTE_SIZE_MAX, 4,
        function() return Rogue:RiposteGet("size") end,
        function(v) Rogue:SetRiposte("size", v) end, COL_W, "%d px")
    size:SetPoint("TOPLEFT", blinkCheck, "BOTTOMLEFT", 0, -12)

    local soundCheck = Check(L["Play a sound"], "soundOn", L["Plays the sound below when the icon appears (at most once a second)."])
    soundCheck:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, -12)
    -- picking a sound switches it on (as everywhere in BeautifulRogue)
    local picker = UI.SoundPicker(p, function() return Rogue:RiposteGet("sound"), Rogue:RiposteGet("soundVolume") end,
        function(name, vol)
            local s = Rogue:RiposteSettings()
            if name ~= Rogue:RiposteGet("sound") then s.soundOn = true end
            s.sound, s.soundVolume = name, vol
            soundCheck:Refresh()
        end, COL_W)
    picker:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -6)

    local reset = UI.Button(p, COL_W, L["Reset position"], function()
        Rogue:ResetRipostePosition()
    end, 22)
    reset:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 0, -14)
    UI.Tooltip(reset, { L["Reset position"], L["Puts the icon back above the middle of the screen."] })

    local status = ns.Text(p, 11)
    status:SetWidth(COL_W)
    status:SetJustifyH("LEFT")
    status:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -10)
    p.riposteStatus = status

    Render = function()
        if not p:IsVisible() then return end
        local name = Rogue:RiposteName()
        hint:SetText(L[HINT]:format(name))
        onCheck.label:SetText(L[SHOW]:format(name))
        if p.win then p.win.title:SetText(name) end
        for _, c in ipairs(checks) do c:Refresh() end
        size:Refresh()
        picker:Refresh()
        if Rogue:RiposteKnown() then
            status:SetText("")
        else
            status:SetText(ns.Colorize(HEX.alert, L["You have not learned %s yet: the icon only shows here."]:format(Rogue:RiposteName())))
        end
    end
end

-- its own window, built on first use; opened from the Modules page and /brogue riposte
local win
function Rogue:OpenRiposte()
    if not win then
        win = UI.Window("BeautifulRogueRiposteWindow", WIN_W, WIN_H, Rogue:RiposteName(), { strata = "FULLSCREEN" })
        win:SetPoint("CENTER", 300, 0)   -- beside the icon's default place, not over it
        local body = CreateFrame("Frame", nil, win)
        body:SetPoint("TOPLEFT", 14, -40)
        body:SetSize(WIN_W - 28, WIN_H - 54)
        win.body = body
        body.win = win
        BuildPage(body)
        win:SetScript("OnShow", function()
            Rogue:SetRipostePreview(true)
            Render()
        end)
        win:SetScript("OnHide", function()
            UI.CloseSoundPicker()
            Rogue:SetRipostePreview(false)
        end)
    end
    win:Show()
    Rogue:SetRipostePreview(true)
    Render()
    return win
end
function Rogue:RiposteShown() return win ~= nil and win:IsShown() end

Rogue:Command({ "riposte" }, function() Rogue:OpenRiposte() end,
    L["rogue: open the settings of the icon after a parry (show, blink, size, sound, position)"])

Rogue:Event("SPELLS_CHANGED", function() if Render and Rogue:RiposteShown() then Render() end end)
-- the module switched off: no preview left on the screen
ns.On("MODULES_CHANGED", function()
    if win and win:IsShown() and not Rogue:IsActive() then win:Hide() end
end)

Rogue:Reset({ key = "riposte", group = "hud", order = 65, label = L["Icon after a parry"],
    desc = L["Shown, blinking, size, sound and position of the icon go back to the defaults."],
    reset = function()
        local s = ns.Char().modules.rogue
        if s then s.riposte = nil end
        if Rogue.ApplyRiposte then Rogue.ApplyRiposte() end
        if Render and Rogue:RiposteShown() then Render() end
    end })
