# Top bar (cartouche)

The bar is the campaign's standing instrument panel, not a title banner. A
control earns its place only if it answers a question the player asks every
turn or performs an action on the map (`REQ-P1-02`, `REQ-P1-05`).

## Purpose rule

| Element | Player question / action |
|---------|--------------------------|
| Crest, nation, turn · year | Who am I, and when is it? |
| Region seal | Which map am I on? Switch when a second region exists. |
| Capital seal | Take me to my seat (same intent as `F`). |
| Ledger | Treasury, trade and upkeep. |
| Research | College slots and funding. |
| Court | Diplomacy, alliances and war. |
| Treasury plaque | Can I afford this? Shows the projected net income beside the count; opens the ledger. |
| Ships / Troops plaques | Where are my pieces? Each press selects the next own squadron or army in the region on screen and brings it under the camera. |
| Civilians plaque | Where is my crew? Opens the whole-empire roster (`C`) with region and craft filters. |

## What was removed

`PRESTIGE` was a saved integer that began at 38 and rose by one each turn. No
rule read it, no panel explained it, and its value was always `turn + 37`: a
vanity counter that echoed the calendar. It was removed from the bar, the
session, and the save shape. Older saves keep loading; the unknown key is
ignored.

A region select on a one-region map is equally false affordance: the seal stays
as context but goes inert, with copy that says it is the only charted region.

## Geometry

- Desktop bar: **60 px**; compact bar: **56 px** (was 68 / 58).
- Command seals are **58×44 px**, icon over a one-word caption. On a compact
  bar the four commands collapse to **44×44** medallions; the region keeps its
  word because map identity is context, not a command.
- Status plaques are **40 px** tall. On compact they keep the medallion and
  value and drop the caption word, so the bar stays one row on an 800-point
  phone; the tooltip carries the full name.
- If the row still cannot fit, the plaques move to a measured second row
  (98 px bar). No text is clipped to force one line.

## Visual language

The backing is drawn, not imported: a varnished beam, a faint compass-rose
inlay and a double gilt rule. All nine bar medallions share the generated
antique-brass set; the coin, ship, people and swords icons were made with the
GameForge image pipeline from the ledger reference, magenta-keyed and
downsampled to the 128 px shell contract. Plaques lift on hover and press flat
on tap. Wide bars show every caption; compact bars keep the medallion and the
value, and the region keeps its word, so no critical control depends on hover
(`REQ-P1-02`, `REQ-P1-05`, `REQ-P1-07`, `REQ-P1-08`, `REQ-P4-04`).
