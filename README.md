# ZBar (WoW 3.3.5a)

Rearrange the **default Blizzard action bars** without replacing them.
Unlike Dominos or Bartender, ZBar keeps the original bars and buttons, so your
keybinds, macros and other addons keep working - it only lets you move,
group, resize and hide what is already there.

Made for the Grimfall private server (Conquest of
Azeroth and Classless realms), works on any 3.3.5a client.

## Install

1. Download the repository (Code > Download ZIP).
2. Copy the `ZBar` folder into `World of Warcraft\Interface\AddOns`.
3. Restart the game (a `/reload` is not enough for new addon files).

## Features

**Rearranging** (`/zbar` to unlock)
- The 4 default action bars (Main, Bottom Left, Bottom Right, Right, Right 2).
- Drag a single button, or **Alt+drag** a whole bar.
- Buttons dropped next to each other snap into a group, with a frame to move the group together.
- Dropped on top of something? It slides off to the nearest free spot, or goes back if there is none.
- Mouse wheel on a group header or a blue box: resize. Right-click: hide / show.
- **Content mode**: drag a button's spell or macro instead of the button (the old Shift+drag).
- Stance / form pages follow the moved main bar buttons.

**Ctrl / Shift layers** (per button, works in combat)
- Hold **Ctrl** or **Shift** while pressing a button's key (or clicking it) and it does a second / third action: a spell, a macro, an item or a **pet action**.
- Turn each layer on in *Interface > AddOns > ZBar > Ctrl / Shift Layers*. Turning a layer on frees the default keys in its way (Ctrl+1-0: pet bar keys, Shift+1-6: bar paging); turning it off puts them back.
- Assign in *Mode: Modifiers* (`/zbar layers`): hold Ctrl or Shift and drop a spell, macro or item on a button; right-click a button for pet actions or to clear.
- While Ctrl or Shift is held, the buttons show what that layer will do - icon and tooltip (also on buttons whose base slot is empty).
- Alt is not touched: it stays the game's self-cast key.
- While a layer uses the game's *Pick Up Action Key* (Shift by default), that key is set to none, so a Shift+click cannot drag a spell off a locked bar by accident. Rearrange spells with `/zbar` (Content mode). The old key comes back when the layer is turned off.
- **Windows and the Shift layer:** Windows has two keyboard helpers that react to Shift - **Sticky keys** (pressing Shift 5 times pops up a window that can pull you out of the game) and **Filter keys** (holding right Shift for 8 seconds turns it on, then quick key presses can be ignored). In *Settings > Accessibility > Keyboard* open the **Sticky keys** and the **Filter keys** menu and turn **every option inside those two menus** off (the rest of the Keyboard page can stay as it is). Turning off only their main switch is **not enough**: Windows can still pop up if an option below it is on (e.g. the keyboard shortcut, or "Lock shortcut keys when pressed twice in a row", which would make Shift stay pressed). Or use only the Ctrl layer. ZBar shows this the first time you turn the Shift layer on.
- Saved per character and in each role profile.

**Macro builder** (*Interface > AddOns > ZBar > Macro Builder*, or `/zbar macro`)
- Click a macro together instead of typing it: spells from a list (spellbook with or without cooldown, pet spells, usable items - with search, like in WeakAuras Simple Remastered) or dragged from the spellbook.
- Per spell: enemy / friendly / any target, try on mouseover, focus, target, target's target, yourself if you have no target (an enemy target is never healed by mistake), or yourself as a fallback, a held key (Alt, Ctrl, Shift or none) and in / out of combat. The first spell that fits is cast - e.g. attack on an enemy, heal on a friend.
- Or a cast sequence, with reset on new target, after combat or after some seconds.
- Extras: show tooltip, dismount, cancel form, stop casting, auto target, start attack, pet attack, trinket 1 / 2, hide error messages.
- Live preview with a character counter: the game allows 255 characters, a longer macro cannot be saved.
- Character macro (default) or account macro, chosen per macro. ZBar remembers how each macro was built, so it can be changed here later. Macros not made by ZBar are never overwritten.
- Pick Up puts the macro on your cursor: drop it on any button or Ctrl / Shift layer.

**Blocks** (move as one unit, keep their own inner layout)
- Stance bar, totem bar, pet bar, XP bar, reputation bar.

**Custom bars** (hide only)
- Conquest of Azeroth class resource bars (`CoAResourceSegmentBar`, `CoAResourceOrb`, ...), each on its own.
- Hide them from the bar's own right-click menu (**Hide (ZBar)**), from unlock mode, or in the options.

**Layout**
- **Save Layout Only / Restore Layout Only**: positions only, not tied to a role.
- **Undo** the last 15 moves, resizes and hides (this session).
- **Factory Reset**: every bar back to its Blizzard position.

**Role profiles** (Tank / DPS / Healer, per character)
- Each role keeps its own bar positions, **bar contents** (spells, macros, items, mounts) and an optional **gear set** (Equipment Manager).
- Switching role loads all of it. Spells the new spec does not know are skipped and listed in chat.
- Auto-save when switching roles (unlearned talent spells removed by a respec are kept in the profile).
- Dual spec: optionally switch role automatically with Spec 1 / Spec 2.
- **Talents (Conquest of Azeroth, optional)**: with "Save talents with roles" on, a manual role save also stores your talent build. Switching to a role with a different build asks first (**Change Talents** / **Cancel** - Cancel keeps your current role, also in Threat Plates); talents and bars belong together, since talent spells are on the bars. The build is loaded through the talent window's own Import and Save Changes, and the bars are loaded after the server confirmed it, so new talent spells land on them too. If the talents cannot be loaded (time-out), nothing is half switched: you stay in your old role with its layout, layers and talents, and chat says "Role switch failed (timed out), please try again." The automatic save while switching never overwrites talents. The options show each role's build (spec, class / spec points, talent names in the tooltip).
- **Threat Plates link**: if the reworked Threat Plates with the Tank/DPS/Healer selector is installed, it is the boss - switching role there switches ZBar too, and the other way round.

**Minimap button** (can be hidden in the options)
- Left click: DPS. Middle click: Tank. Right click: Healer. Alt+right click: options. Drag: move. (Unlocking the bars: `/zbar` or the options.)

## Commands

| Command | |
|---|---|
| `/zbar` | unlock / lock the bars |
| `/zbar save` | save the layout only (positions) |
| `/zbar restore` | restore the layout-only save |
| `/zbar undo` | undo the last move / resize / hide |
| `/zbar reset` | factory reset (reloads the UI) |
| `/zbar role tank\|dps\|healer` | switch role |
| `/zbar saverole` | save layout + bars to the current role |
| `/zbar reloadrole` | load the current role again |
| `/zbar options` | open the options (Interface > AddOns > ZBar) |
| `/zbar layers` | set up the Ctrl / Shift layers |
| `/zbar macro` | open the macro builder |

## Notes

- Nothing can be moved or switched in combat (a WoW restriction). Role switches requested in combat run when combat ends.
- Settings are saved per character (`ZBarCharDB`).

## Credits

ZBar by **Lidless**. Feedback: please open an issue in this repository.
