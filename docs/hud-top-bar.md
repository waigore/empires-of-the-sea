# Top bar (cartouche)

The bar is the campaign's standing instrument panel. A control earns its place
only if it answers a question the player asks every turn or acts on the map
(`REQ-P1-02`, `REQ-P1-05`).

## Purpose rule

| Element | Player question / action |
|---------|--------------------------|
| Menu crest, nation, turn · year | Who am I, when is it, how do I save? |
| Lens seal | What is this ground doing? Click cycles, hold names. |
| Region seal | Which map am I on? |
| Capital seal | Take me to my seat (`F`). |
| Ledger | Treasury, trade and upkeep. |
| Research | College slots and funding. |
| Court | Diplomacy, alliances and war. |
| Muster seal | All my pieces, in one ledger (`O`). |
| Estates seal | What are my works doing? Opens the estates ledger. |
| Gazette seal | What happened last turn? Opens the news and its archive. |
| Treasury plaque | Can I afford this? Net income beside the count. |
| Ships / Troops plaques | Where are my pieces? Selects the next own squadron or army. |
| Civilians plaque | Where is my crew? Opens the whole-empire roster (`C`). |
| End turn | The turn's one gold door, closing the row. |

## Map surface

Idle, the chart carries only navigation and readability: zoom, minimap, lens
key. Estates, the Gazette and every other non-navigation door live on the bar.
Opened plates — estates, Gazette, battle plates, sheets, dossiers — drag by
their grip or header, so the fleet or province underneath can be read without
closing them; a closed plate returns to its layout place. A new button or
overlay over the chart must earn that cost (`REQ-P1-07`).

## Geometry

- Desktop bar: **60 px**; compact: **56 px**; a measured second row takes the
  plaques to **98 px** when the row cannot fit.
- Command seals are **52×44 px**, icon over a one-word caption; compact
  collapses them to **40×44** medallions. The region keeps its word because map
  identity is context; the MENU door takes the first slot, so no loose pause or
  sound seal rides the map.
- The turn's gold door is **140×44** (**104×44** compact) at the row's end.
- Status plaques are **40 px** tall; compact keeps the medallion and value and
  drops the caption, so the bar stays legible on an 800-point phone.

## Visual language

The backing is drawn, not imported: a varnished beam, a faint compass-rose
inlay and a double gilt rule. The brass medallions share one generated set;
the MENU crest stays vector. Wide bars show every caption; compact bars keep
the medallion and value (`REQ-P1-02`, `REQ-P1-05`, `REQ-P1-07`, `REQ-P1-08`,
`REQ-P4-04`).
