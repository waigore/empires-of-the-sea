# Top bar (cartouche)

The bar is the campaign's standing instrument panel. A control earns its slot
only if it answers a turn-by-turn question or acts on the map (`REQ-P1-02`,
`REQ-P1-05`).

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
| Ships / Troops plaques | Where are my pieces? Selects the next own squadron or army, crossing charts. |
| Civilians plaque | Where is my crew? Opens the whole-empire roster (`C`). |
| End turn | The turn's one gold door, closing the row. |

## Map surface

Idle, the chart carries only navigation: zoom, minimap, lens key. Every bar
door opens a **full-screen modal**: its own layer above the pause menu, a wash
that takes the pointer, safe-area margins, back or Close. Nothing behind it
answers a press, so the pause seal is parked too.

Selection dossiers (province, fleet, army) stay docked side sheets: they
describe a thing on the chart, and slide in and drag by their own chrome. A new
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

## Despatch lane

Toasts raise only the turn clock, the answer to the crown's own press, and
danger to the crown (`ToastPolicy`, wiki `hud-toasts`; `REQ-P5-02`,
`REQ-P5-05`). Other news is the Gazette's.

## Visual language

The backing is drawn, not imported: a varnished beam, a faint compass-rose
inlay and a double gilt rule. The brass medallions share one generated set;
the MENU crest stays vector. Wide bars show every caption; compact bars keep
the medallion and value (`REQ-P1-02`, `REQ-P1-05`, `REQ-P1-07`, `REQ-P1-08`,
`REQ-P4-04`).
