---
name: map-lens
description: |-
  Add or change a map lens/overlay in Empires of the Sea: a pure projection in
  scripts/rules, a Node2D layer above the fog, a HUD toggle + survey key, and
  desktop/mobile tests. Use when adding a map mode (survey, resources,
  diplomacy, terrain), changing scripts/map/resource_lens.gd, or when a player
  asks to see map information at a glance. Not for side dossiers or ledgers.

  Examples:
    - "show resources on the map" → survey lens via ResourceSurvey + ResourceLens
    - "add a terrain/diplomacy lens" → reuse the same projection → layer → key shape
    - "the lens plaques overlap / fps drops" → packing, repaint and anchor rules
---

# Map lens

A map lens is a toggleable reading of map state drawn on the map itself. The
reference implementation is the resource survey lens:

- [`scripts/rules/resource_survey.gd`](../../../scripts/rules/resource_survey.gd)
  — pure projection, node-free.
- [`scripts/map/resource_lens.gd`](../../../scripts/map/resource_lens.gd) —
  plaques, packing, hit-testing.
- [`scripts/ui/lens_legend.gd`](../../../scripts/ui/lens_legend.gd) — the key.
- [`tests/test_resource_survey.gd`](../../../tests/test_resource_survey.gd),
  [`tests/test_resource_lens.gd`](../../../tests/test_resource_lens.gd) — proof.

## Shape of the change

Do it in this order; each step is reviewable and testable alone.

1. **Projection first.** Put all decisions in `scripts/rules/` as a
   `RefCounted` with a static `snapshot(...)` returning plain dictionaries and
   counts. No nodes, no drawing.
2. **View layer.** Add a `Node2D` after `MapOverlay` in
   `scenes/map_screen.tscn`; it draws above the fog but below ships, civilians
   and armies.
3. **Wiring.** Bind the lens on `PlaySession`, rebuild it from `MapPlaySetup`,
   refresh on signals and turn boundaries, never per frame.
4. **Chrome.** Add a top-bar toggle (or reuse an existing mode control), an
   `InputActions` shortcut, and a legend.
5. **Proof.** Pure suite + integration suite + a phone-layout assertion.

## 1. Projection (`scripts/rules/**`)

- `class_name` it and `extends RefCounted` (arch-lint `RUB-P3-03`).
- Feed it `model`, `works`, units, owner, `visibility`, capital tile and tech
  caps. Return `{ "provinces": [...], "counts": {...}, "totals": {...} }`.
- Reuse existing rules: `ImprovementCatalog`, `ImprovementSystem`,
  `ImprovementLedger` status vocabulary, `VisibilityModel` and
  `Extraction`/`ImprovementCatalog.effective_yield`.
- Hide unknown ground at projection time:
  `visibility.level_at(tile) == VisibilityModel.Level.UNKNOWN` → skip the tile.
  Never draw information the player has not charted.
- Foreign rows: say only whether the tile is worked
  (`foreign` / `foreign_worked` / `foreign_building`); do not invent a yield.
- A province note needs an `anchor` that is known land. `ProvinceState.center`
  can fall in a bay (archipelagos) or stay unknown; fall back to the surveyed
  resource tile nearest the centre.
- Count `worked` as `level > 0` (including foreign and disconnected), and
  `producing` only when connected and prospected. They are different facts.

## 2. View layer (`scripts/map/**`)

- Scene order matters: `MapCanvas` → `MapOverlay` → your lens → units. Plates
  above fog are remembered knowledge; unknown tiles are already excluded.
- Draw only when `active`, the survey is non-empty and the reveal tween is
  above zero.
- Parchment plaque recipe:
  clipped-corner polygon, an offset shadow polygon, a warm paper fill, a
  dark ink outline, and a second engraved inner rule. Do **not** use
  per-plate `StyleBoxFlat` with shadows: 40 plates on a 10 Hz repaint dropped
  the harness from ~50 fps to ~3 fps. Cheap polygons and `draw_arc` only.
- One emblem per resource tile via `MapGlyphs.resource`; ring colour carries
  status, gold pips carry level, the badge and bar carry worked/total.
  More than three estates (capital grain farms can make six) → three emblems
  and a small `+N`; never silently hide the extras.
- Pack plaques greedily on `refresh()`: try below the name, then 24 px further
  down, and reject any `Rect2` that intersects an existing one (`grow(4)`).
  Compute and cache `_rects` per province so draw and hit-test agree.
- `hit_test(world_position)` maps a tap on a displaced plaque back to its
  province; `MapPlayInput.on_tapped` must consult it before
  `model.province_at(tile)`.
- Static by default. Repaint at ~10 Hz only while a row is `building` (the
  rotating works arc); otherwise repaint only on refresh.
- Fade land units to ~22% while the lens is open and restore them when it
  closes; ships can stay at full ink.
- Fog alpha: 1.0 fully visible, ~0.88 charted. A `FOGGED` province keeps its
  remembered slip; `UNKNOWN` tiles never contribute rows.

## 3. Wiring

- Add `var lens` to `PlaySession` and a parameter to `bind_views`.
- `MapPlaySetup.build_lens(play)` is the one rebuild path. Call it from
  `build_hud` (after the economy exists, so tech caps are real), `load_region`,
  turn end, after load, and after political map refreshes.
- Refresh through signals, not polling:
  `CivilianLayer.works_changed` and `MapOverlay.fog_changed` connect to
  `ResourceLens.refresh`. Keep `is_connected` guards so a rebuild does not
  stack connections.
- Input: add `InputActions.LENS` (for example `KEY_L`) and route the keyboard
  and HUD button through one helper (`MapPlayInput.set_lens` / `toggle_lens`)
  so the toggle, key and unit fade never disagree.
- Top-bar budget is measured, not guessed: `HudLayout._row_width` must stay
  under `viewport.x - 40`. Adding a button can push the stat chips onto the
  second row at 1280 px and grow the bar from 68 to 92. Tighten separations
  and button widths (or use a four-letter label) rather than moving the chips.
- Legend placement: desktop bottom-left under the ESTATES seal
  (`top = 186`); compact top-right under the bar (`maxf(66, bar + 8)`).
  Build it before toasts so transient messages stay above it.

## 4. Tests

- Pure suite: charted-only, own vs foreign, vacant/unprospected/building/
  producing/disconnected/maxed, applied works, `+N` counts, anchor on known
  land.
- Integration suite: toggle raises the key and fades units; a works change
  refreshes the survey; region switch rebuilds; hover summary; plates do not
  intersect; `hit_test`; tapping a plate selects its province.
- Cover the draw path: set `_reveal = 1.0`, `queue_redraw()`, then
  `await get_tree().process_frame` so the renderer executes `_draw`.
- Phone proof: assert the key stays on screen and right-docked in
  `tests/test_mobile_layout.gd`; the desktop bar height assertion must stay 68.
- Run the impacted suites, then the full suite:
  `gd-tools test --coverage --parallel 4`. Keep `docs-lint` and `arch-lint`
  green. Coverage injectors can report partial instrumentation if scripts are
  edited while a run is in flight; rerun with `--no-cache` to confirm.

## Pitfalls

- `owner` is already a `Node` property on `Node2D`; name the faction field
  `faction`.
- `visibility_changed` is a native `CanvasItem` signal; name the overlay signal
  `fog_changed`.
- `scripts/map_screen.gd` is at the 400-line soft cap. Offset new lines by
  compacting neighbouring lambdas or move the logic into `MapPlay*` /
  `MapPlaySetup`; do not grow `tools/arch_size_allowlist.txt`.
- Placing a plaque at the province centre can put it on water or on unknown
  ground; always anchor on a known land tile.
- A plate packed away from its province makes taps select the wrong province
  unless `hit_test` runs first.
- Do not rebuild the survey every frame; recompute on state signals and turn
  boundaries.
- Update [`docs/improvements.md`](../../../docs/improvements.md) and
  [`tests/impact_map.toml`](../../../tests/impact_map.toml) with the new suites.
- When you add this skill or change its name, add/refresh the Cursor, OpenCode
  and Grok facades and the catalog in
  [`.agents/skills/README.md`](../README.md); Hermes reads this tree directly.

## Verify

```bash
gd-tools test tests/test_resource_survey.gd tests/test_resource_lens.gd \
  tests/test_mobile_layout.gd
gd-tools test --coverage --parallel 4
python tools/lint_docs_words.py
python tools/lint_arch.py --base-ref origin/main
```

Screenshot the lens at fit zoom, close zoom and a phone size; diff two frames
to confirm the lens is static unless a work is in progress.
