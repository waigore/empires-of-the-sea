# Capital choice

A Great Power seats its court before turn 1. Rules: wiki
[Capital Choice Phase](https://github.com/waigore/empires-of-the-sea/wiki/capital-choice-phase).

## Flow

`NEW GAME` → **capital chart** → map screen. The chart is a stripped map screen
(sea, ink, camera) over the generated Old World; `SET SAIL` on the setup page no
longer starts the campaign directly.

The chart generates the world **once**. Confirming hands that same `WorldMap` to
`MapScreen.preset_world`, so the seat the player picked is the seat the campaign
starts on — no second roll, and the world is not generated twice.

## Rules (pure, `scripts/rules/`)

| Call | Meaning |
|------|---------|
| `CapitalChoice.can_seat(model, faction, province)` | Owned **and** sea-bound province |
| `CapitalChoice.seat_error(model, faction, province, tile)` | `""` when legal, else the refusal code |
| `CapitalChoice.seat_capital(model, faction, province, tile)` | Applies the seat and its capital works |
| `CapitalChoice.place_capital(model, faction, kind)` | Auto-choice (setup default, Minors/Tribes) |

Seating a court:

- The **province** must be owned by the crown and sea-bound (P–S edge).
- The **tile** may be any land tile of that province; it becomes plains and loses
  any resource or extraction (select-then-convert, as in auto-choice).
- Ports and harbour roads are laid out per wiki § Capital Setup
  (`CapitalPorts.layout`); the province town moves to the seat and Great Power
  town development becomes 4.
- The **old** seat loses its capital flag, tile, ports and roads; its town stays
  at level 1.
- A refused seat leaves the model untouched and returns an error code.

The auto-chosen seat is preselected, so confirming without touching the chart is
the documented setup default.

## Presentation

`scripts/ui/capital_choice_screen.gd` + `scenes/capital_choice.tscn`:

- Tap a province, then a tile. Taps on the sea or another crown's land are
  refused in the banner (never silent).
- `CapitalSeatMarker` washes the chosen province, inks its border and pulses a
  ring on the seat tile.
- Mouse, trackpad and touch all pan/zoom the chart; `BACK` (or Escape) returns
  to setup; `SEAT THE COURT` confirms.
- Banner and action bar are anchored, compact on short (phone-landscape) screens.

## Persistence

`SaveWorld` stores `capital_tile` and `ports` per province, so a reload keeps a
hand-picked seat and its harbour instead of the regenerated auto-choice one.

## Tests

- `tests/test_capital_choice.gd` — seating rules and refusals.
- `tests/test_capital_seat_screen.gd` — chart pick, confirm, refusals, back.
- `tests/test_menu_flow.gd` — setup → chart → campaign, chosen seat reaches the
  Home Army.
- `tests/test_save_world.gd` — seat tile and harbours round-trip.
- `tools/e2e_smoke.gd` — clicks through the chart on the real flow.
