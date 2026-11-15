# Top bar (cartouche)

The bar is the campaign's instrument panel, not a title banner. A control
earns its place only if it answers a question the player asks every turn or
acts on the map (`REQ-P1-02`, `REQ-P1-05`).

## Purpose rule

| Element | Player question / action |
|---------|--------------------------|
| Menu crest, nation, turn · year | Who am I, when is it, how do I pause or save? |
| Lens seal | What is this ground doing? Click cycles, hold names. |
| Region seal | Which map am I on? Switch when a second region exists. |
| Capital seal | Take me to my seat (same intent as `F`). |
| Ledger | Treasury, trade and upkeep. |
| Estates seal | What is my realm producing? Opens the estates ledger. |
| Research | College slots and funding. |
| Court | Diplomacy, alliances and war. |
| Muster seal | Where are all my pieces? Opens the whole-empire force ledger (`O`): armies and squadrons, by chart. |
| Gazette seal | What happened this turn? Opens the news and its archive. |
| Treasury plaque | Can I afford this? Shows the projected net income beside the count; opens the ledger. |
| Ships / Troops plaques | Where are my pieces? Each press selects the next own squadron or army in the region and brings it under the camera. |
| Civilians plaque | Where is my crew? Opens the whole-empire roster (`C`) with region and craft filters. |

## What was removed

`PRESTIGE` was a vanity counter no rule read; it left the bar, the session and
the save shape, and older saves ignore the key. A one-region map keeps its
region seal inert.

## Geometry

- Desktop bar: **60 px**; compact bar: **56 px** (was 68 / 58).
- Command seals are **58×44 px**, icon over a one-word caption. On a compact
  bar the eight commands collapse to **40×44** medallions; the region keeps its
  word because map identity is context. The MENU door takes the first slot; no
  loose seal rides the map, so the rail below the bar is clear.
- Status plaques are **40 px** tall. Compact shows the medallion and value,
  dropping the caption word, so the bar stays one row on a 914-point phone; the
  tooltip carries the name.
- When the row cannot fit, the plaques move to a measured second row (98 px
  bar). The 800-point floor takes that row; no text is clipped to force one line.

## Visual language

The backing is drawn, not imported: a varnished beam, a faint compass-rose
inlay and a double gilt rule. The brass medallions share one generated set
(coin, ship, people, swords, manor, gazette — GameForge, magenta-keyed to the
128 px shell contract); the MENU crest stays vector. Wide bars show every
caption; compact bars keep the medallion and value, and the region its word, so
nothing needs hover
(`REQ-P1-02`, `REQ-P1-05`, `REQ-P1-07`, `REQ-P1-08`, `REQ-P4-04`).
