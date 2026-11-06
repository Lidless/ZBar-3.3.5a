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
- While Ctrl or Shift is held, the buttons show what that layer will do.
- Alt is not touched: it stays the game's self-cast key.
- Windows tip: pressing Shift 5 times in a row makes Windows ask about **Sticky keys**, which can pull you out of the game. In *Settings > Accessibility > Keyboard* turn off **every** option under Sticky keys, not just the main switch - Windows can still pop up with Sticky keys off if an option below it is on. That includes the keyboard shortcut and "Lock shortcut keys when pressed twice in a row" (that one would make Shift stay pressed). Also turn off the **Filter keys** keyboard shortcut. Or use only the Ctrl layer. ZBar shows this tip the first time you turn the Shift layer on.
- Saved per character and in each role profile.

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
- **Threat Plates link**: if the reworked Threat Plates with the Tank/DPS/Healer selector is installed, it is the boss - switching role there switches ZBar too, and the other way round.

**Minimap button** (can be hidden in the options)
- Left click: options. Shift+left click: unlock / lock. Right click: next role. Drag: move.

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

## Notes

- Nothing can be moved or switched in combat (a WoW restriction). Role switches requested in combat run when combat ends.
- Settings are saved per character (`ZBarCharDB`).

## Credits

ZBar by **Lidless**. Feedback: please open an issue in this repository.
