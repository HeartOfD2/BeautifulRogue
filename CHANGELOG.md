# Changelog

## 1.10.0 (2026-11-14)

- **Fix: the threat bar kept its name in the Layout list.** When it was hidden because you are not in a group, the long reason ("only shown in a group or raid") pushed the name out of the row. The reason is short now ("group only").
- **New rogue macro "Fin Riposte EF!" (enUS: "Sin Riposte EF!").** Like "Sinister EF!" (weapons into your hands, then Sinister Strike), but with Riposte first: it fires whenever it is ready, otherwise Sinister Strike goes off. Rogue macros page › "Create missing" makes it; existing macros stay as they are.
- **Swing timer: choose the fill direction per bar.** Layout › Swing timer: next to the main hand, off hand and ranged switch there is now a list "Left to right" (default) or "Right to left". Each bar has its own choice. Suggested by a player.
- **Swing timer: empty when you are not attacking.** A finished bar no longer waits full while auto attack (or Auto Shot / Shoot for the ranged bar) is switched off; it goes dark until you attack again. If the game cannot tell, the bars behave as before.

## 1.9.0 (2026-11-13)

- **Fix: the periodic stutter with the Rogue module.** The poison and sharpening-stone tiles asked the game for your bags, your weapons and their tooltips once a second, even when nothing changed. They now read on events (gear, bags, a weapon's enchant) instead, in combat every few seconds besides, and only write or redraw what actually changed.
- **Sharpening stones and the Riposte icon can be switched off.** Addon › Modules: each one gets its own "Enabled" checkbox in front of its button. Off, nothing of it runs — no button, no warning, no window, no reading, no icon, no sound — and switching it on brings it right back, no `/reload` needed.

## 1.8.1 (2026-11-12)

- **Riposte icon waits for the cooldown.** After you used Riposte, a new parry no longer shows the icon while the spell is still on cooldown; it appears (with the sound, if on) once 0.5 seconds of the cooldown are left.

## 1.8.0 (2026-11-10)

- **Language choice.** Addon › Appearance has a new box "Language": Automatic (the language of the game), English or Deutsch. It applies after a /reload, and the box offers the reload right away. Spell, item and zone names stay in the language of the game, as they come from it. The choice is kept by the small addon "BeautifulRogue Language" that comes with the package (it has to know the language before BeautifulRogue loads); leave it enabled in the addon list. `/brogue status` shows the language in use.

## 1.7.0 (2026-11-09)

- **Riposte icon.** A new icon shows, and blinks, while you can use Riposte after a parry; it hides as soon as you use it or the chance is gone, and only appears in combat once you know Riposte. "Riposte ›" on the Rogue box under Addon › Modules (or `/brogue riposte`) opens its settings: show it, blink, size, an optional sound with volume, and the position. While that window is open the icon shows and you can drag it anywhere. It is no button: clicks go through it.
- **Fix: a picked stone that no longer fits the weapon** (or your level) no longer blocks the stone button; it uses the ranking until the pick fits again.
- **Fix: right after logging in, a poison could show up as a stone** on clients where the stone is read from the weapon tooltip.
- **Fix: "Reset › Modules" could be undone** by a Damage numbers switch still saved on a character from before 1.6.0.

## 1.6.0 (2026-11-08)

- **Four more poison types.** The poison choice now also lists Sebacious, Numbing and Atrophic Poison and Occult Poison (both ranks), with names and icons from your client. The poison tiles recognize them on your weapons, and the poison macros and the {p:MH} / {p:OH} placeholders can use them.
- **Poisons above your level are skipped.** "Best available" and a picked type only use ranks you can apply at your level; if your bags hold only higher ranks, the choice says from which level.
- **Fix: switching off the Damage numbers module holds for all characters.** Its settings were always account-wide, but the switch was per character, so another character put the fonts back. When you switch it (or the numbers above the heads) off, the chat now reminds you that the game's font for those numbers returns after logging out and in; a /reload is not enough.

## 1.5.0 (2026-11-08)

- **Sharpening stones next to your poisons.** On this server a weapon holds a poison and a stone at once, so each poison tile now has a small stone button on its right: left-click applies a stone, right-click picks one for that hand. Its tooltip shows the time left; the outline turns red under 5 minutes and blinks when the stone is missing in combat (only while you carry a fitting one).
- **Your own stone ranking.** "Sharpening stones ›" on the Rogue box under Addon › Modules (or "Edit ranking…" in the stone choice) opens a window with all stones: drag to reorder; the button takes the first one in your bags that fits the weapon (sharpening stones for blades, weightstones for maces and fist weapons) and your level. Add your own items by ID or link, such as oils or new stones. The stone button can be switched off there; while it is off, right-click a poison button for "Sharpening stones…", or type `/brogue stones`.
- **Poison tiles read poison and stone apart.** A stone alone no longer shows up as a poison.

## 1.4.2 (2026-11-08)

- **Fix: right-clicking a poison button no longer applies the poison.** It only opens the poison choice, as intended; left-click applies.

## 1.4.1 (2026-11-08)

- **"New gear" can ask or act on its own.** Under Macros › Placeholders, "On new gear" is **Ask** (the window, as before), **Automatically** (W1 and W2 are picked for you, gear macros follow) or **Manually** (nothing happens until you pick W1/W2 and press Refresh; choosing it asks first, and the chat names macros that no longer fit your gear). "Don't ask again" in the window switches to Automatically; pick Ask there to get the question back.
- **Placeholders can be switched off.** Addon › Modules has a new Placeholders box (per character): **Deactivate gear placeholders** stops {w:…} and {g:…} from being filled in anywhere, templates included, and the "New gear" window is gone; **Deactivate own placeholders** does the same for {c:…}. With both, the Placeholders page disappears. {s:…} spell names always work.
- **"Prefer main hand" moved** to the Placeholders page as a W1/W2 choice (shown while the Rogue module runs); the page is laid out anew: weapons and trinkets, then one line of settings, then the buttons; the Rogue macros page shows your weapons as one line with a button to get there.

## 1.4.0 (2026-11-06)

- **Skinnable corpses sparkle.** New tab Skinning under Extras › Miscellaneous: the looted corpse your interact key would skin next sparkles, golden when you can skin it, dim from afar and grey when your skill is too low. The skinning symbol sits above the glints and the corpse's nameplate stays hidden meanwhile. On by default, only for characters with Skinning and not during combat. Needs the game's Enable Interact Key setting.

## 1.3.0 (2026-11-06)

- **Macro manager: drag a macro onto a group.** Drop it on a group header to sort it in; the group list box in the editor keeps working. Dragging onto an action bar stays as it was.

## 1.2.0 (2026-11-05)

- **Rogue macros: you choose where they go.** "Create missing" and creating a single macro now ask whether they become general or character macros; before, they always became general ones. `/ef defaults char` does the same from the chat.
- **Rogue macros get their own group.** New macros land in the group "Rogue" of the macro manager, which is created if it isn't there yet. Macros you already have join it once, unless you sorted them into a group of your own.
- **Macro manager: move a macro to the other list.** Right-click a macro for "Move to Character" or "Move to General". It keeps its text, icon and group and stays on your action bars.

## 1.1.0 (2026-11-05)

- **The icon list matches this game again.** The macro icon picker's data had been built from a Retail client: it offered about 2,500 icons World of Warcraft: Forever does not have (they showed as empty tiles) and was missing the ones Forever brought. It is now built from the Forever client, 30,550 icons.
- **Spells count as learned again.** Whether you know a spell was asked through two functions the game only keeps while its fallbacks for retired code are switched on. With them off nothing counted as learned, so the cooldown bars, the rank a bar picks, the range display, Slice and Dice and the dual-wield placeholder all went quiet. The spellbook is now asked directly.
- **New name: BeautifulRogue** (formerly EverFrame), with the rogue of the very first version back as its logo. Your settings are taken over on the first start; the package carries a small `EverFrame` folder for that, which you may delete afterwards. `/brogue` opens the window, `/ef` keeps working.
- **Reordering by dragging**: the up/down arrows in the Layout part list, the Cooldowns list and the macro assistant are gone. Every row has a drag handle (three lines): hold the left mouse button on it and move up or down. The row lifts off the list as a floating card with an accent edge and a soft shadow while its place stays as a dimmed slot; the Layout list scrolls when you reach its edge. Cooldown entries move within their own bar.
- **Swing timer**: up to three thin bars at the HUD (main hand, off hand, ranged) that fill between two swings or shots, driven by the game's swing event. Each bar can be switched off and has its own color; height, colored edge and a see-through background are shared (HUD › Layout › Swing timer; untick the part in the list to hide it). Off hand and ranged get their space only with a weapon in that slot (or once the game has reported such a swing). A finished bar stays full while you fight with a target and dims when the target is out of reach. The Layout page shows a sample while it is open.

## 1.0.0 (2026-10-13)

First stable release for World of Warcraft: Forever. EverFrame is now a complete combat frame for every class with macro tools, notes and a set of extras, and it is no longer a beta. Install both folders, `EverFrame` and `EverFrame_IconData`, in `Interface\AddOns`.

- **New defaults for 1.0** (for new and reset settings; what you saved stays): health bar 20 px high, `{cur} ({pct}%)` in green #37C971; energy bar #CDDD00; the global cooldown bar has a transparent background; combo point sound on ("GM chat warning"); threat sound on ("Raid warning", only in a party or raid); cursor ring in petrol; damage numbers (floating and scrolling text), fast camera zoom, hide chat and copy chat are on. All modules are on; the rogue module runs for rogues only.
- **Defaults checked for 1.0:** the threat sound plays only in a party or raid (new choice "Only in group/raid" in the list, which now sits right of "Sound at"), and the range display checks 5 times per second. Saved settings are not changed. The Reset page has a new entry, **Appearance** (dark or light mode, accent color, font), and "Select all" now brings every setting back to its default.

- New module **Miscellaneous** (every class, on by default; the camera zoom, hide chat and copy chat are on, each with its own switch) with a page under Extras and one tab per feature:
  - **Camera**: fast zoom. Turning the mouse wheel quickly covers far more distance, turning it slowly stays fine-grained. Base step, acceleration, zoom speed and a soft or direct curve; off restores the game's zoom.
  - **Hide chat**: a button shows and hides all chat windows with their tabs, input box and chat buttons; the state survives a reload. Pressing Enter or opening Edit Mode brings the chat back. Lock/unlock and drag the button, snap it into a corner, size, opacity, color, reset.
  - **Copy chat**: see below.

- **GCD bar**: a thin bar at the top of the frame that lights up while the global cooldown runs and drains with it. Height, color and a see-through background under HUD › Layout; untick it in the part list to hide it.

- **Cooldown bars**: each entry follows the **highest rank you have learned** and transformed spells (overrides), keeping its place and settings; optional **tint** by range (red), missing resource (blue) or not usable (grey), off by default; a **use count** on the icon where the game has one; potions show the shared potion cooldown; spells with **charges** show the number of charges.

- **Five-second rule**: while your resource is mana, a thin line below the mana bar runs down for 5 seconds after each spell that costs mana; its height is added to the bar. Switch, height and color under HUD › Layout › Resource (only shown for characters with mana).

- **Threat sound**: choose where it plays: always, only in a party, only in a raid, or only in a dungeon or raid instance. Threat and combo point sounds stay quiet when the target is dead.

- Damage numbers: a **font preview** beside each font list, and hovering a font in any font list shows a sample in that font. A **Reset to default** button turns both blocks back off.

- Layout settings: long German labels on the button rows and long descriptions under a heading no longer get cut off or cover the first setting.

- New module **Damage numbers** (every class, on by default, both blocks on): font, size, gravity and duration of the floating combat numbers, and a font for the scrolling combat text. A new font for the numbers shows after logging out and in.

- New fonts for the damage numbers: **Bangers**, **Bebas Neue**, **Chomsky** and **Help Me** (SIL Open Font License).

- New text fonts, also for EverFrame itself under Addon › Appearance: **Barlow Bold**, **Fira Sans**, **Inter** and **Source Code Pro** (each Regular, SemiBold and Bold; SIL Open Font License; with Cyrillic letters). **Fira Sans SemiBold is the new default** for EverFrame itself and for both damage number blocks. The font list under Addon › Appearance keeps the three text fonts with full German letters (Barlow Regular, Barlow SemiBold, Arial Narrow).

- Class packs: removed spell IDs the game does not know (no name): Wyvern Sting, Elemental Mastery, Fire Nova Totem and higher ranks of Tiger's Fury, Frenzied Regeneration, Multi-Shot and Deadly Poison. Add them as your own cooldown entry if you need them.

- Cursor ring: **Show** is "Off" by default; pick "Always" or "In combat" under HUD › Cursor.

- **Cooldown bars**: icons turn **grey while on cooldown** (on by default) and can carry an **accent outline while ready** (off by default); both under HUD › Layout › Cooldown bar. The game tells how much is left, also in combat; EverFrame only passes it on.

- **Copy chat** (Miscellaneous › Copy chat): a small icon on every chat window (any of the four corners, always or only on mouse over) opens its text in a window you can search, select and copy with Ctrl+C, in your font and size, with optional timestamps and the channel colors; player names keep their class color. Lines the game protects are skipped and counted.

- **Sound picker**: wherever EverFrame plays a sound (combo points full, threat at the limit) you now pick from **every sound of the game**: a list with search, groups by name and an arrow to listen, plus a **volume** (0–100 % of the master volume) for each sound. Sound names are shown readable ("Raid warning"). The combo point sound got its own volume; new defaults: combo points "GM chat warning", threat "Raid warning". Your earlier choice is kept.

- The data addon `EverFrame_IconData` shows the EverFrame icon in the addon list (no red question mark).

- **Menu rebuilt** by task: HUD (Position & visibility, Layout, Cooldowns, Cursor), Macros (Macro manager, Templates, Placeholders, Rogue macros), **Extras** (Notes, Damage numbers, Miscellaneous) and Addon (Modules, **Appearance**, Reset, About). Colors, font and the minimap button moved to the new Appearance page; the range check rate sits with the range display in Layout; the notes' "in combat" switches sit in the Players and Sticky notes tabs. The sidebar is more compact and scrolls when there are many pages, and the Reset page is grouped like the sidebar and scrolls too. Nothing you saved changes.

- **Cooldown bars**: you choose how many (0–20, one by default) under HUD › Layout: **+ Cooldown bar** adds one, the **×** at the end of a bar's row removes it (click twice). Bars are numbered, taking one away moves its cooldowns to the neighbour; the part list scrolls. On the Cooldowns page a button picks the bar of each cooldown.

- Threat bar: new option **Show**: always, or only in a group or raid (HUD › Layout › Threat bar).

- Threat bar: optional **sound** when your threat reaches a limit (10–100 %); pick the sound and the volume. It plays only while the game shows the threat percentage.

- Icon filter: categories of one group add up (sword or dagger), different groups narrow down (Abilities + Rogue = the rogue abilities).

- The version now shows at the bottom of the window ("Version 1.0.0").

- New HUD part **Threat bar** (every class): your threat on the current target. Shows the threat percentage when the game gives it (also while it hides the number), otherwise the threat state 0–3; colored by threat level, or class/own color. Layout: move, hide, height, edge, text.

- New module **Cursor** (for every class, on by default): a ring around the mouse pointer. Settings under HUD › Cursor: show off / always / in combat, hide in game menus, ring color, size 16–48 px. The ring pictures are used under the MIT license; the text is in `Media/Cursor/LICENSE.txt`.

- Macro icon picker: a Filter button narrows the icons by category (weapons, armor, classes, professions, magic ...), and the search also finds icon names and file IDs. The icon data is a second addon folder, `EverFrame_IconData`, that loads only when the picker opens; keep both folders in `Interface\AddOns`.

- Notes are a module now ("Notes" on the Modules page, on for every class): switched off, the notes page, sticky notes, the target popup, the Shift-click on the minimap button and the "Notes in combat" block go away; your notes stay saved and come back unchanged when you switch it on again. The switch is per character, the notes stay account-wide. Resetting "All notes" now keeps the "Notes in combat" switches.

- New **Macro assistant**: the Assistant button under the macro list builds a macro from spells or items (suggestions from your spellbook and bags while you type), a target (mouseover, focus, cursor, self, heal/harm ...), conditions (Shift/Ctrl/Alt, in combat, stealth, raid, channeling) and extras (`#showtooltip`, `/stopcasting`, `/cancelaura`, `/startattack`, `/petattack`, `/focus`). Several entries become one line each. A live preview counts the characters; save it as a new macro (not in combat) or as a template.

- New font: EverFrame now uses **Barlow Regular**; Barlow SemiBold and the old Arial Narrow can be picked under Addon › Appearance › Font. After a change EverFrame offers to reload the interface. Korean, Chinese and Russian letters keep the game's fonts.

- Reset › Modules switches the modules back on at once (no reload needed).

## 0.10.1 (Beta)

- One note editor everywhere: the notebook, the player popup and sticky notes all show checkboxes and lists, and a click on a box ticks it.
- Numbered lists: `1. text` (the numbers run on by themselves).
- Enter at the end of a list line starts the next one; Enter on an empty list line ends the list.
- The buttons under each note turn the current line into a checkbox, bullet or numbered item.

## 0.10.0 (Beta)

**Ultimate EverRogue is now EverFrame – Compact Combat Frame with Extras.** The addon works for every class; the rogue features stay as a module.

- New logo: the combat frame itself, in the addon list, on the minimap button and on the About page.
- New folder `EverFrame`: delete the old `UltimateEverRogue` folder. EverFrame starts with fresh settings (settings, notes and templates of Ultimate EverRogue are not taken over).
- Chat command `/ef` (or `/everframe`).
- Rogue macros end in "EF!" now ("W1 MH EF!", "Backstab EF!" ...). Create them again on the Rogue page and put them on your action bars; old macros ending in "UER" are left alone, you can delete them.
- Export codes start with `EF2:`, `EFM1:` and `EFN1:`. Codes from Ultimate EverRogue no longer import.
- Colored edge: a 1 px line around the bars, each combo point (any shape), the range display, each cooldown icon and the poison tiles. Switch it per part (each cooldown bar on its own) in the Layout tab; Frame holds the color and a switch for all parts.
- New in-game screenshots in the gallery.

## 0.9.0 (Beta)

First public release of Ultimate EverRogue for World of Warcraft: Forever.

### Combat frame
- Health, resource (mana, rage, energy) with your own text format, combo points for rogues and druids in Cat Form, range bands to your target.
- Up to five cooldown bars with seven icons each: the class package, abilities found in your spellbook, your own potions, bandages and trinkets.
- Combo points as bars, circles or diamonds; at full points they glow, pulse, run a light wave or only change color, optionally with a sound (21 to pick from).
- Hide the frame out of combat, without a target or in a vehicle; holding ALT, CTRL or SHIFT shows it.
- Layout editor: order and visibility of every part, height, bar colors with a color picker (class color included), text format, size and alignment, warning zone, icon size, frame width, spacing and a background with color and opacity.

### Settings and tools in one window
- Sidebar with HUD (General, Layout, Cooldowns, Notes), Macros (Placeholders, Player macros, Templates, Rogue) and Addon pages; dark and light mode, teal, amber or blue accent.
- Macro manager: general and character macros in groups, icon search by spell or item name, spell search that puts `{s:ID}` into the text, export and import as one line of text.
- Templates with placeholders: spells in your game language (`{s:ID}`, with rank `{s:ID:r}`), weapon roles `{w:W1}` / `{w:W2}`, trinkets `{g:t1}` / `{g:t2}`, values of your own `{c:name}`. **Refresh** (or `/uer update`) rewrites every macro named exactly like a template; other macros are never touched. Macros made from a template carry a colored frame.
- New weapons or trinkets: after combat a short question suggests W1 / W2, and the macros follow.

### Notes
- Notebook with colored groups, notes per player and a popup when you target a player with notes (movable, resizable, lockable).
- Sticky notes on the screen with checkboxes and lists; they dock to each other. Sticky notes and the popup can step aside in combat.
- Export and import of notes and templates as a text code.

### Rogue module
- Poison tiles with time and charges: apply with a click, choose the poison with a right-click, warnings when low or missing.
- Slice and Dice timer, read from the buff where the game allows it.
- Weapon macros: swap macros "W1 MH UER" / "W2 MH UER", Backstab and Ambush with the dagger in the main hand, everything else with the weapon marked "Prefer main hand", Kick, Blind, Gouge and poison macros. Spell names come from the game; the macros are created and kept up to date for you, also without Dual Wield.

### General
- English and German; spell and item names always come from the game client.
- Settings per character; notes, theme and window position account-wide. Reset per category.
