# Top bar (cartouche)

The bar is the campaign's standing instrument panel, not a title banner. A
control earns its place only if it answers a question the player asks every
turn or performs an action on the map (`REQ-P1-02`, `REQ-P1-05`).

## Purpose rule

| Element | Player question / action |
|---------|--------------------------|
| Menu crest, nation, turn · year | Who am I, when is it, how do I pause or save? |
| Lens seal | What is this ground doing? Click cycles, hold names. |
| Region seal | Which map am I on? Switch when a second region exists. |
| Capital seal | Take me to my seat (same intent as `F`). |
| Ledger | Treasury, trade and upkeep. |
| Research | College slots and funding. |
| Court | Diplomacy, alliances and war. |
| Muster seal | Where are all my pieces? Opens the whole-empire force ledger (`O`): armies and squadrons, by chart. |
| Treasury plaque | Can I afford this? Shows the projected net income beside the count; opens the ledger. |
| Ships / Troops plaques | Where are my pieces? Each press selects the next own squadron or army in the region on screen and brings it under the camera. |
| Civilians plaque | Where is my crew? Opens the whole-empire roster (`C`) with region and craft filters. |

## What was removed

`PRESTIGE` was a vanity counter no rule read (`turn + 37`); it left the bar,
the session and the save shape, and older saves ignore the key. A one-region
map keeps its region seal inert, saying it is the only chart of the world.

## Geometry

- Desktop bar: **60 px**; compact bar: **56 px** (was 68 / 58).
- Command seals are **58×44 px**, icon over a one-word caption. On a compact
  bar the six commands collapse to **40×44** medallions; the region keeps its
  word because map identity is context. The MENU door takes the first slot, so
  no loose pause or sound seal rides the map, and the rail below holds only
  ESTATES and the Gazette.
- Status plaques are **40 px** tall. On compact they keep the medallion and
  value and drop the caption word, so the bar stays one row on an 800-point
  phone; the tooltip carries the full name.
- If the row still cannot fit, the plaques move to a measured second row
  (98 px bar). No text is clipped to force one line.

## Visual language

The backing is drawn, not imported: a varnished beam, a faint compass-rose
inlay and a double gilt rule. The brass medallions share one generated set
(coin, ship, people, swords — from the ledger reference through the GameForge
pipeline, magenta-keyed to the 128 px shell contract); the MENU crest stays
vector. Wide bars show every caption; compact bars keep the medallion and the
value, and the region keeps its word, so nothing needs hover
(`REQ-P1-02`, `REQ-P1-05`, `REQ-P1-07`, `REQ-P1-08`, `REQ-P4-04`).
