# Map screen demo

Player-facing map UI: antique-atlas look, animated world, and the input model.

**Pillars:** P1 (presentation, animation, desktop+mobile), P2 (fog-of-war), P3 (boundaries), P4 (latency, draw cost). Province, civilian, estate, ledger and court orders are live; economy and diplomacy resolve per turn.

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

Pan has inertia; zoom anchors under the cursor; the camera clamps cover-fit.

## Phone layout

On handhelds `PlatformDisplay` makes one HUD unit one point; under 1000×560 points `HudLayout` switches to a compact cartouche, minimap, full-height dossiers, thumb targets and notch-safe insets. `test_mobile_layout.gd` pins it.

## Architecture

```
scenes/map_screen.tscn      composition: world, camera, HUD, FX
scripts/map_screen.gd       controller: world build + input → intents
scripts/map/map_model.gd    pure tile data (region-scoped)
scripts/map/map_generator.gd generation + world
scripts/map/country_borders.gd owner borders from the grid
scripts/map/map_canvas.gd   static artwork (terrain, coast, province ink)
scripts/map/map_canvas_plan.gd names + symbols (pure)
scripts/map/map_overlay.gd  borders, hover, selection
scripts/map/fog_layer.gd    fog texture layer
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

**Generation (deterministic):** noise land → terrain → provinces/sea zones (BFS) → resources → ports → contiguous ownership (`TerritoryAssignment`) → capitals → `WorldBootstrap` (ports, roads, four grain farms). Old World: six Great Powers and three Minor Nations; New World: ten Tribes. One seed reproduces both maps (`tests/test_map_generator.gd`).

**Fog of war:** `VisibilityModel` keeps three levels per tile (`unknown < fogged < fully visible`). Own provinces start visible, the rest fogged; sea zones touching an owned coast are visible. A fleet charts its zone and coastal ring; End of Turn runs decay, distant-sea fog, then the coastal pass.

**Rendering:** terrain wash (owned land washed 50% toward its crown's colour); Chaikin coast ink; **country borders above fog**; vector glyphs; “Passage” marks; sea/grain/vignette shaders. The minimap bakes a texel per tile plus projected ink — coast, province hairlines, owner ribbons — repainting on chart or crown changes.

## Animation & performance

| Motion | Where |
|--------|-------|
| Sea swell | `ui/shaders/sea.gdshader` |
| Fog reveal | `FogLayer` (child of `MapOverlay`) |
| Selection pulse / ripple | `MapOverlay` |
| Fleet bob / wake / pennant | `scripts/map/ship.gd` |
| Fleet sail glide / dock anchor | `ShipLayer`, `Ship` |
| Camera intro / inertia / zoom | `MapCamera`, `MapScreen._intro` |
| HUD slides, counts, toasts | `GameHud` |

Build ~0.55 s (128×84). Static canvas once; settled fog still; overlay + ships per frame; input ack same frame.

## Known limits

Capitals follow the capital-choice rule and `WorldBootstrap` wires their farms.
Province, civilian and estate orders are rules-backed, as are fleet movement,
docking, ship reveal and sea combat ([`fleets.md`](fleets.md)). Beachhead
landings and fleet merging ship; Patrol/Blockade/Defend, interception and AI
missions are deferred. Warp transit, colonisation and Minor/Tribe
reactive play are deferred ([`world.md`](world.md)).
