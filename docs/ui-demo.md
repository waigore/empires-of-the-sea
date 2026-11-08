# Map screen demo

Player-facing map UI: antique-atlas look, animated world, and the input model.

**Pillars:** P1 (presentation, animation, desktop+mobile), P2 (fog-of-war rules), P3 (boundaries), P4 (input latency, draw cost). Province, civilian, estate, ledger and court orders are live; economy and diplomacy resolve each turn.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Pan | drag, WASD / arrows, trackpad | one-finger drag |
| Zoom | wheel, pinch, `+` / `−`, E / Q | pinch, `+` / `−` |
| Jump | click / drag minimap | tap / drag minimap |
| Select | click province or fleet | tap |
| Switch region | OLD/NEW | tap |
| Focus capital | `F` / `Home` | CAPITAL |
| End turn | `Space` / `Enter`, gold seal | gold seal |
| Back | `Esc` deselects | system back closes the top layer, then quits |

Pan has inertia; zoom anchors under the cursor; the camera clamps with a cover-fit floor.

## Phone layout

On handhelds `PlatformDisplay` makes one HUD unit one point; under 1000×560 points `HudLayout` switches to a compact cartouche, minimap, full-height dossiers with orders first, thumb targets, notch-safe insets. `tests/test_mobile_layout.gd` pins the geometry.

## Architecture

```
scenes/map_screen.tscn      composition: world, camera, HUD, FX
scripts/map_screen.gd       controller: world build + input → intents
scripts/map/map_model.gd    pure tile data (region-scoped)
scripts/map/map_generator.gd deterministic per-region generation + world
scripts/map/country_borders.gd owner borders derived from the grid
scripts/map/map_canvas.gd   static artwork (terrain, coast, province ink)
scripts/map/map_overlay.gd  fog, country borders, hover, selection
scripts/map/map_camera.gd   pan / zoom / inertia / clamp
scripts/map/camera_math.gd  pure camera maths (tested)
scripts/map/ship_layer.gd   fleets, orders, sail animation
scripts/map/ink_paths.gd    ink line smoothing
scripts/rules/turn_time.gd  turn → calendar year
scripts/rules/world_map.gd        two regions + warp-zone pairs
scripts/rules/visibility.gd per-player fog of war (tested)
scripts/rules/capital_choice.gd  capital-choice phase (tested)
scripts/rules/world_bootstrap.gd setup ports, roads, grain farms
scripts/rules/diplomacy_*.gd relations, war, alliances, overtures
scripts/ui/diplomacy_panel.gd the court ledger (tested via screen)
scripts/ui/*                HUD, dossier, fleet panel, minimap, theme
scripts/platform/*          display scale + safe area (P3)
ui/shaders/*                sea, fog, grain, vignette
```

`MapModel` + `MapGenerator` are the sim side; the view never owns outcomes (`REQ-P3-03`).

**Generation (deterministic):** noise land → terrain → provinces/sea zones (BFS) → resources → ports → contiguous faction ownership (`TerritoryAssignment`) → capitals → setup post-pass (`WorldBootstrap`: real ports/roads, four grain farms). The Old World holds six Great Powers and three Minor Nations; the New World ten Tribes. The same seed reproduces both maps (`tests/test_map_generator.gd`).

**Fog of war:** `VisibilityModel` keeps three levels per tile (`unknown < fogged < fully visible`). Own provinces start visible, the rest fogged; sea zones touching an owned coast are visible. A fleet entering a zone charts its water and coastal ring; End of Turn runs decay, distant-sea fog, then the coastal pass.

**Rendering:** scaled terrain wash; marching-squares coasts + Chaikin province ink; **country borders drawn above fog** as an engraved shadow plus the owner's colour; vector glyphs/labels; warp-zone “Passage” marks; sea/grain/vignette shaders.

## Animation & performance

| Motion | Where |
|--------|-------|
| Sea swell | `ui/shaders/sea.gdshader` |
| Fog reveal | `MapOverlay` |
| Selection pulse / ripple | `MapOverlay` |
| Fleet bob / wake / pennant | `scripts/map/ship.gd` |
| Fleet sail glide / dock anchor | `ShipLayer`, `Ship` |
| Camera intro / inertia / zoom | `MapCamera`, `MapScreen._intro` |
| HUD slides, counts, toasts | `GameHud` |

Build ~0.55 s (128×84). Steady state: static canvas once; overlay + ships per frame. Input ack same frame.

## Known limits

Capitals follow the capital-choice rule (sea-bound province, ports, roads) and
the setup post-pass wires their farms. Province, civilian and estate orders are
rules-backed. Fleet movement, docking, ship reveal and sea-zone combat are
rules-backed ([`fleets.md`](fleets.md)); missions, interception, home-fleet merge
and AI movement are deferred. Warp-zone transit, colonisation of unclaimed land
and Minor/Tribe reactive play are deferred ([`world.md`](world.md)).
