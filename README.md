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
- While a layer uses the game's *Pick Up Action Key* (Shift by default), that key is set to none, so a Shift+click cannot drag a spell off a locked bar by accident. To move spells anyway, click the small **lock** under the main bar's page number: Shift+drag works again, and a moved spell takes its Ctrl / Shift actions with it (a swap if the other button is not empty). A button with only Ctrl / Shift actions (no spell of its own) can be dragged the same way: its actions swap with the other button's. Anything let go off the bars asks first whether to remove it (No puts it back, with its Ctrl / Shift actions). It locks itself again when combat starts or after 2 minutes without dragging. Or use `/zbar` (Content mode). The old key comes back when the layer is turned off.
- **Windows and the Shift layer:** Windows has two keyboard helpers that react to Shift - **Sticky keys** (pressing Shift 5 times pops up a window that can pull you out of the game) and **Filter keys** (holding right Shift for 8 seconds turns it on, then quick key presses can be ignored). In *Settings > Accessibility > Keyboard* open the **Sticky keys** and the **Filter keys** menu and turn **every option inside those two menus** off (the rest of the Keyboard page can stay as it is). Turning off only their main switch is **not enough**: Windows can still pop up if an option below it is on (e.g. the keyboard shortcut, or "Lock shortcut keys when pressed twice in a row", which would make Shift stay pressed). Or use only the Ctrl layer. ZBar shows this the first time you turn the Shift layer on.
- Saved per character and in each talent tree profile.

**Macro builder** (*Interface > AddOns > ZBar > Macro Builder*, or `/zbar macro`)
- Click a macro together instead of typing it: spells from a list (spellbook with or without cooldown, pet spells, usable items - with search, like in WeakAuras Simple Remastered) or dragged from the spellbook.
- Per spell: enemy / friendly / any target, try on mouseover, focus, target, target's target, yourself if you have no target (an enemy target is never healed by mistake), or yourself as a fallback, a held key (Alt, Ctrl, Shift or none) and in / out of combat. The first spell that fits is cast - e.g. attack on an enemy, heal on a friend.
- Or a cast sequence, with reset on new target, after combat or after some seconds.
- Extras: show tooltip, target mouse (point and press: targets what is under the mouse first), dismount, cancel form, stop casting, auto target, start attack, pet attack, trinket 1 / 2, hide error messages.
- Icon: automatic (follows the spell the macro would cast) or one of the macro's spells, always shown.
- Live preview with a character counter: the game allows 255 characters, a longer macro cannot be saved.
- Character macro (default) or account macro, chosen per macro. ZBar remembers how each macro was built, so it can be changed here later. Macros not made by ZBar are never overwritten.
- Pick Up puts the macro on your cursor: drop it on any button or Ctrl / Shift layer.

**Blocks** (move as one unit, keep their own inner layout)
- Stance bar, totem bar, pet bar, XP bar, reputation bar.

**Custom bars** (hide only)
- Conquest of Azeroth class resource bars (`CoAResourceSegmentBar`, `CoAResourceOrb`, ...), each on its own.
- Hide them from the bar's own right-click menu (**Hide (ZBar)**), from unlock mode, or in the options.

**Layout** (on the toolbar that opens with `/zbar` or Unlock Bars)
- **Save Layout Only / Restore Layout Only**: positions only, not tied to a talent tree.
- **Undo** the last 15 moves, resizes and hides (this session).
- **Factory Reset**: every bar back to its Blizzard position.

**Talent tree profiles** (Conquest of Azeroth, per character)
- One profile per talent tree of your class (three or four), shown with its kind: e.g. *Slayer - Melee*, *Infernal - Caster*, *Tyrant - Tank* (read from the game's own spec data, with primary stats, armor and difficulty).
- Each tree keeps its own bar positions, **bar contents** (spells, macros, items, mounts), Ctrl / Shift layers, an optional **gear set** (Equipment Manager) and its **talent build**.
- Switching asks first (**Change Talents** / **Cancel**). Talents load first through the talent window's own Import and Save Changes, then the bars, so the tree's talent spells land on them too. If the talents cannot be loaded (time-out), nothing is half switched.
- Below level 10 (no talent trees yet) the trees show *Talent trees open at level 10* - the character is still known as a Conquest of Azeroth character, not a classless one.
- A tree that was never saved starts empty (all its points to spend - the talent button glows); your bars stay as they are until you set them up and save.
- Switched trees in the game's own talent window? ZBar follows: the old tree's bars are saved, the new tree's bars loaded.
- Auto-save when switching refreshes trees that were saved before.
- **Unspent talent points**: the game does not tell you, so the talent micro button glows while you have points to spend, and its tooltip says how many (class / spec).

**Dual spec profiles** (Classless realm: no talent trees)
- Each dual spec keeps its own bar positions, Ctrl / Shift layers and gear set, loaded when you change spec. The game swaps talents and bar contents with the spec itself.

**Minimap button** (can be hidden in the options)
- Conquest of Azeroth: left / middle / right click switches talent tree; the tooltip shows which is which. A class with four trees picks its three in the options (*Minimap clicks*). Alt+right click: options. Drag: move.
- Classless: click opens the options.

## Settings lost after running the game as administrator?

If your addon settings suddenly look reset (for example after an update you started as administrator), they are
**not lost**. Windows keeps two copies of the game's saved settings when the game is installed under
`C:\Program Files (x86)\`:

| How the game was started | Settings are read from / saved to |
| --- | --- |
| Normally | `%LOCALAPPDATA%\VirtualStore\Program Files (x86)\Grimfall\Games\Wotlk\WTF` |
| As administrator | `C:\Program Files (x86)\Grimfall\Games\Wotlk\WTF` |

Switching between the two loads the other, older copy. This affects every addon that saves settings, not only this one.

**C – recommended: update as administrator, play normally**
1. Start the launcher as administrator and let the update finish.
2. **Do not press Play.** Close the launcher.
3. Start the launcher again normally and play from there.

**B – once and for all: give yourself write access to the game folder**
- Right click `C:\Program Files (x86)\Grimfall` → *Properties → Security → Edit* → select *Users* → tick
  *Modify* → *OK*. After that the game never needs administrator rights and there is only one copy.

**Your settings already "disappeared"?** With the game closed:
1. Copy the `WTF` folder from `%LOCALAPPDATA%\VirtualStore\Program Files (x86)\Grimfall\Games\Wotlk`
   to `C:\Program Files (x86)\Grimfall\Games\Wotlk` and replace the files there.
2. If you chose **B**: rename `%LOCALAPPDATA%\VirtualStore\Program Files (x86)\Grimfall` (e.g. to `Grimfall_old`),
   so Windows stops reading the old copy.

## Commands

| Command | |
|---|---|
| `/zbar` | unlock / lock the bars |
| `/zbar save` | save the layout only (positions) |
| `/zbar restore` | restore the layout-only save |
| `/zbar undo` | undo the last move / resize / hide |
| `/zbar reset` | factory reset (reloads the UI) |
| `/zbar tree 1-3 \| name` | switch talent tree (e.g. `/zbar tree infernal`) |
| `/zbar savetree` | save layout, bars, layers and talents to the current tree |
| `/zbar reloadtree` | load the current tree's saved bars again |
| `/zbar options` | open the options (Interface > AddOns > ZBar) |
| `/zbar layers` | set up the Ctrl / Shift layers |
| `/zbar macro` | open the macro builder |

## Notes

- Nothing can be moved or switched in combat (a WoW restriction). Talent tree switches are not possible in combat.
- Settings are saved per character (`ZBarCharDB`).

## Credits

ZBar by **Lidless**. Feedback: please open an issue in this repository.
