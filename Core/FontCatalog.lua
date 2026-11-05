-- ---------------------------------------------------------------------------
-- Font catalog: every font BeautifulRogue ships (plus the game's Arial Narrow), with what
-- it can show and what it is good for.
--   coverage  "full" = German letters, Latin-1 and Latin Extended-A complete enough for
--             any text; "limited" = decorative sets with gaps (tools/font_coverage.py
--             measures this from the files and fails when the table below disagrees)
--   use       "text" = for reading, "display" = for big numbers and headlines
--   scripts   alphabets the font really has (Cyrillic: Fira Sans, Inter, Source Code Pro)
-- The global font choice (app, sticky notes, combat frame) offers only full + text
-- fonts; modules that draw a few big words (damage numbers) offer all of them.
-- Keys are stored in the database: never rename one. Licenses sit next to the files.
-- ---------------------------------------------------------------------------
local _, ns = ...

local DIR = "Interface\\AddOns\\BeautifulRogue\\Media\\Fonts\\"

-- file = nil means ns.FONT_DEFAULT (the game's Arial Narrow, set in Theme.lua)
ns.FONT_CATALOG = {
    { key = "barlow",     name = "Barlow Regular",  file = DIR .. "Barlow-Regular.ttf",     coverage = "full",    use = "text",
      scripts = { latin = true }, license = "OFL.txt" },
    { key = "barlowSemi", name = "Barlow SemiBold", file = DIR .. "Barlow-SemiBold.ttf",    coverage = "full",    use = "text",
      scripts = { latin = true }, license = "OFL.txt" },
    { key = "barlowBold", name = "Barlow Bold",     file = DIR .. "Barlow-Bold.ttf",        coverage = "full",    use = "text",
      scripts = { latin = true }, license = "OFL.txt" },
    { key = "arial",      name = "Arial Narrow",    file = nil,                              coverage = "full",    use = "text",
      scripts = { latin = true }, license = "game" },
    { key = "firaSans",     name = "Fira Sans",          file = DIR .. "FiraSans-Regular.ttf",       coverage = "full", use = "text",
      scripts = { latin = true, cyrillic = true }, license = "OFL-FiraSans.txt" },
    { key = "firaSansSemi", name = "Fira Sans SemiBold", file = DIR .. "FiraSans-SemiBold.ttf",      coverage = "full", use = "text",
      scripts = { latin = true, cyrillic = true }, license = "OFL-FiraSans.txt" },
    { key = "firaSansBold", name = "Fira Sans Bold",     file = DIR .. "FiraSans-Bold.ttf",          coverage = "full", use = "text",
      scripts = { latin = true, cyrillic = true }, license = "OFL-FiraSans.txt" },
    { key = "inter",        name = "Inter",              file = DIR .. "Inter_18pt-Regular.ttf",     coverage = "full", use = "text",
      scripts = { latin = true, cyrillic = true }, license = "OFL-Inter.txt" },
    { key = "interSemi",    name = "Inter SemiBold",     file = DIR .. "Inter_18pt-SemiBold.ttf",    coverage = "full", use = "text",
      scripts = { latin = true, cyrillic = true }, license = "OFL-Inter.txt" },
    { key = "interBold",    name = "Inter Bold",         file = DIR .. "Inter_18pt-Bold.ttf",        coverage = "full", use = "text",
      scripts = { latin = true, cyrillic = true }, license = "OFL-Inter.txt" },
    { key = "sourceCode",     name = "Source Code Pro",          file = DIR .. "SourceCodePro-Regular.ttf",  coverage = "full", use = "text",
      scripts = { latin = true, cyrillic = true }, license = "OFL-SourceCodePro.txt" },
    { key = "sourceCodeSemi", name = "Source Code Pro SemiBold", file = DIR .. "SourceCodePro-SemiBold.ttf", coverage = "full", use = "text",
      scripts = { latin = true, cyrillic = true }, license = "OFL-SourceCodePro.txt" },
    { key = "sourceCodeBold", name = "Source Code Pro Bold",     file = DIR .. "SourceCodePro-Bold.ttf",     coverage = "full", use = "text",
      scripts = { latin = true, cyrillic = true }, license = "OFL-SourceCodePro.txt" },
    { key = "bangers",    name = "Bangers",         file = DIR .. "Bangers-Regular.ttf",     coverage = "full",    use = "display",
      scripts = { latin = true }, license = "OFL-Bangers.txt" },
    { key = "bebasNeue",  name = "Bebas Neue",      file = DIR .. "BebasNeue-Regular.ttf",   coverage = "full",    use = "display",
      scripts = { latin = true }, license = "OFL-BebasNeue.txt" },
    { key = "chomsky",    name = "Chomsky",         file = DIR .. "Chomsky.otf",             coverage = "full",    use = "display",
      scripts = { latin = true }, license = "OFL-Chomsky.txt" },
    { key = "helpMe",     name = "Help Me",         file = DIR .. "HelpMe.ttf",              coverage = "limited", use = "display",
      scripts = { latin = true }, license = "OFL-HelpMe.txt" },
}

local byKey = {}
for _, f in ipairs(ns.FONT_CATALOG) do byKey[f.key] = f end

function ns.FontEntry(key) return byKey[key] end

-- the file of a catalog font (Arial Narrow: the default), nil for an unknown key
function ns.FontPath(key)
    local f = byKey[key]
    if not f then return nil end
    return f.file or ns.FONT_DEFAULT
end

-- may the font be the app-wide font? (full coverage and meant for text)
function ns.FontIsGlobal(key)
    local f = byKey[key]
    return f ~= nil and f.coverage == "full" and f.use == "text"
end

-- fonts to offer, in catalog order, as { key, name } pairs. filter "global" = full + text
-- only, nil/"all" = everything. A font the client cannot load is left out (never offered
-- and never an error); Arial Narrow is always there, it is the fallback itself.
function ns.FontsFor(filter)
    local list = {}
    for _, f in ipairs(ns.FONT_CATALOG) do
        if (filter ~= "global" or ns.FontIsGlobal(f.key)) and (not f.file or ns.FontUsable(f.file)) then
            list[#list + 1] = { f.key, f.name, font = f.file or ns.FONT_DEFAULT }
        end
    end
    return list
end
