# rollfor_cool

rollfor_cool is a Wrath of the Lich King 3.3.5a addon for running loot rolls with soft-reserve support. This port is aimed at Warmane-style WotLK raids and imports soft-reserve data from softres.it Gargul exports.

## Features

- Import soft reserves from softres.it Gargul export data.
- Track soft-reserved and hard-reserved loot in game.
- Restrict SR rolls to players who reserved the dropped item.
- Allow an open roll for SR items with `/arf`.
- Answer raider whispers of `?sr` with their current soft-reserved items.
- Show a scrollable in-game soft-reserve table with `/srs`.
- Match Trial of the Crusader normal item reserves to same-named heroic drops without relying on Classic re-release item IDs.
- Track winners, plus-ones, raid trades, and awarded loot.

## Install

Copy this addon folder into:

```text
World of Warcraft\Interface\AddOns\rollfor-cool
```

The folder includes `rollfor-cool.toc` so a normal GitHub clone works without renaming the folder. It also keeps `RollFor_cool.toc` and `RollFor-WotLK.toc` for compatibility with older package names.

## Soft-Reserve Setup

1. Create and lock the raid on softres.it.
2. Copy the Gargul export data.
3. In game, open the import window with `/sr`.
4. Paste the export data and click `Import!`.

The `Heroic item matching` option is enabled by default and can be toggled from `/sr` or `/srm`. Keep it enabled for Trial of the Crusader heroic runs, because softres.it may only expose normal-mode items while Warmane heroic bosses drop different item IDs with the same item names.

This port does not ship a WotLK Classic/re-release item-ID table. For original 3.3.5a/Warmane compatibility, it uses item names from the softres.it export when available and falls back to the running 30300 client's `GetItemInfo` cache for any IDs that need to be resolved.

Open `/sr` after importing to view the reserve table; it shows each reserved item beside its expected heroic match when one can be resolved. Open `/srm` to inspect the full heroic matching panel. Both views let you hover the reserved and matched items to inspect their in-game tooltips.

## Commands

```text
/rf <item link>     Start a roll, using SR restrictions when the item is reserved
/arf <item link>    Start an open roll, ignoring SR restrictions
/rr <item link>     Raid-roll an item from bags
/irr <item link>    Instant raid-roll an item from bags
/fr                 Finish the current roll early
/cr                 Cancel the current roll
/sr                 Open the SR import/table window
/srm                Inspect heroic item matching
/srs                Print current soft-reserved items
/src                Check who has not soft-reserved
/srca               Announce missing soft reserves
/sro                Manually match mistyped softres names
/rfw                Open winner history
/rfo                Open options
```

## Development

This addon targets the Wrath 3.3.5a client and Lua 5.1. Before publishing, validate every Lua file with `luac5.1 -p`.
