<p align="center"><img src="docs/logo.png" width="220" alt="BeautifulRogue"></p>

<h1 align="center">BeautifulRogue</h1>

<p align="center"><b>Compact Combat Frame with Extras</b> for <b>World of Warcraft: Forever</b>: one frame for every class, plus macro tools and player notes.<br><sub>Formerly EverFrame (and Ultimate EverRogue before that).</sub></p>

<p align="center"><img src="docs/screenshots/in-game.png" width="720" alt="BeautifulRogue in the game: combat frame, sticky notes and a player note"></p>

Health, resource, combo points, threat, range and cooldowns in one movable frame, plus a macro manager with templates and player notes, all in one settings window. Class features come as modules; the **rogue module** adds a poison tracker with one-click apply, a Slice and Dice timer and weapon macros that keep themselves up to date. Small extras (cursor ring, damage number fonts, zoom, chat tools) are modules too, each with its own switch.

Works for every class and in every client language: spell and item names are always read from the game. Interface in English and German.

## Features

- **Combat frame:** health and resource bars with your own text (`{cur} / {max} ({pct}%)` ...), a five-second-rule line under the mana bar, a global cooldown bar, a threat bar with an optional sound, combo points (rogues, druids in Cat Form), range bands, up to twenty cooldown bars (one by default) with seven icons each: class abilities at their highest learned rank, spellbook finds, your own potions, bandages and trinkets. Icons can grey out on cooldown and tint by range or missing resource.
- **Swing timer:** up to three thin bars (main hand, off hand, ranged) that fill between two swings or shots.
- **Layout editor:** order (drag a row by its handle), visibility, height, colors, text, combo point shape and effect of every part; hide out of combat, *hold to show* with ALT, CTRL or SHIFT; background with color and opacity.
- **Sound picker:** wherever BeautifulRogue plays a sound you pick from every sound of the game, with search, a preview and a volume.
- **Macro manager:** general and character macros in groups, icon search with a category filter, spell search, a macro assistant, export and import.
- **Templates with placeholders:** `{s:1752}` becomes the spell in your language, `{w:W1}` / `{w:W2}` your weapons, `{g:t1}` / `{g:t2}` your trinkets, `{c:name}` a value of your own. *Refresh* rewrites every macro named like a template; when your gear changes, the macros follow.
- **Notes module** (on for every class, switch it off on the Modules page): a notebook with colored groups, notes per player with a popup when you target them, sticky notes on the screen with checkboxes and lists.
- **Rogue module:** poison tiles with time and charges, Slice and Dice timer, weapon swap macros, Backstab and Ambush with the dagger in front, Kick, Blind, Gouge and poison macros.
- **Extras (each with its own switch; the cursor ring starts off):** a **cursor ring** around the mouse pointer, **damage numbers** with your own font, size and duration, **fast camera zoom**, a button that **hides the chat**, and **copy chat** to select and copy chat text.
- **Look:** dark and light mode, teal, amber or blue accent, Fira Sans as the default font (Barlow, Inter, Source Code Pro and more to pick).

<p align="center">
<img src="docs/screenshots/combat-frame.png" width="400" alt="The combat frame">
<img src="docs/screenshots/macros.png" width="400" alt="Macro manager">
<img src="docs/screenshots/notes.png" width="400" alt="Sticky notes in the game">
<img src="docs/screenshots/player-notes.png" width="400" alt="Notes on players">
</p>

## Installation

Install it with the CurseForge app, or download a release and unpack it into the `Interface/AddOns` folder of your WoW: Forever installation. The release holds `BeautifulRogue`, `BeautifulRogue_IconData` (the icon list of the macro icon picker; keep both) and the small `EverFrame` folder that carries the settings of the former name over.

**Coming from EverFrame?** BeautifulRogue takes your settings over on its first start. The package holds a small `EverFrame` folder that only carries them over; you may delete it afterwards. Coming from Ultimate EverRogue: delete the old `UltimateEverRogue` folder, BeautifulRogue starts with fresh settings there.

In game, type `/brogue` to open the settings window (`/ef` and `/everframe` still work); `/brogue help` lists all commands.

## Feedback

Bugs and ideas are welcome as [issues](https://github.com/HeartOfD2/BeautifulRogue/issues). Please add your class, the client language and what `/ef status` shows.

## Deutsch

**BeautifulRogue** (bis 1.0 EverFrame, davor Ultimate EverRogue) ist eine kompakte Kampfanzeige für **WoW: Forever**: Leben, Ressource, Combo-Punkte, Bedrohung, Reichweite und Cooldowns in einem Rahmen, dazu ein Makro-Manager mit Vorlagen und Platzhaltern, Spielernotizen und Haftnotizen – alles in einem Einstellungsfenster. Das Schurken-Modul bringt eine Gift-Anzeige mit Auftragen per Klick, einen Zerhäckseln-Timer und Waffen-Makros, die sich selbst aktuell halten. Dazu kommen kleine Extras, jedes mit eigenem Schalter: Cursor-Ring, Schadenszahlen mit eigener Schrift, schneller Kamerazoom und Chat-Werkzeuge. Die Oberfläche gibt es auf Deutsch und Englisch; Zauber- und Itemnamen kommen immer aus dem Spiel. Im Spiel öffnet `/brogue` (oder weiter `/ef`) die Einstellungen. Wer von EverFrame kommt, behält seine Einstellungen: BeautifulRogue übernimmt sie beim ersten Start. Wer von Ultimate EverRogue kommt, löscht den alten Ordner `UltimateEverRogue`.

## License

[MIT](LICENSE) © HeartOfD2
