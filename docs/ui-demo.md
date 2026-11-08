# Map screen demo

Player-facing prototype of the map UI: antique-atlas presentation, animated
world, and the input model the real map screen will keep.

**Pillars:** P1 (presentation, animation, desktop + mobile), P3 (module
boundaries), P4 (input latency, draw cost). No rules outcomes are decided here,
so nothing in this demo claims P2 coverage beyond the turn calendar.

---

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Pan | drag, WASD / arrows, two-finger trackpad | one-finger drag |
| Zoom | wheel, pinch, `+` / `−`, E / Q | pinch, `+` / `−` |
| Jump | click / drag the minimap | tap / drag the minimap |
| Select | click a province or fleet | tap |
| Focus capital | `F` / `Home` | — |
| End turn | `Space` / `Enter`, gold seal | gold seal |

Pan has inertia; zoom is anchored under the cursor; the camera is clamped to the
map and its zoom floor is a cover fit, so no window shape ever shows empty
background past the map edge. Actions are registered in `InputActions` at
runtime, so no gameplay code hard-codes a key.

---

## Architecture

```
scenes/map_screen.tscn      composition: world layers, camera, HUD, screen FX
scripts/map_screen.gd       controller: builds the world, turns input into intents
scripts/map/map_model.gd    pure tile data (terrain, province, sea zone, resource)
scripts/map/map_generator.gd deterministic generation from a seed
scripts/map/map_canvas.gd   static artwork: terrain wash, ink coast, borders, labels
scripts/map/map_overlay.gd  animated layer: fog of war, hover, selection
scripts/map/map_camera.gd   pan / zoom / inertia / clamping
scripts/map/camera_math.gd  pure camera maths (tested without a viewport)
scripts/map/ship_layer.gd   fleet markers, routes between sea zones
scripts/map/ink_paths.gd    segment tracing + Chaikin smoothing for ink lines
scripts/rules/turn_time.gd  turn -> calendar year (wiki: turn-time-mapping)
scripts/ui/*                HUD, province dossier, minimap, icons, theme, palette
ui/shaders/*                sea, fog, grain, vignette
```

The rules/simulation side is `MapModel` + `MapGenerator`; the view reads it and
never owns outcomes (`REQ-P3-03`). Everything visual is built from the model, so
swapping in a rules-engine-backed world later means replacing the generator, not
the renderer.

### Generation

Land shape (two noise fields + elliptical falloff, cellular smoothing, tiny
island/lake cleanup) -> terrain blobs by elevation/moisture -> provinces by
farthest-point seeds and multi-source BFS growth -> sea zones the same way ->
resources on allowed terrain -> ports on the most sheltered coastal tile ->
faction ownership by nearest capital.

Generation is deterministic: the same seed yields the same terrain, provinces,
sea zones and names (`tests/test_map_generator.gd`).

### Rendering

- Terrain is a `width x height` image scaled up with linear filtering, so the
  wash blends like watercolour instead of showing a tile grid.
- Coastlines come from marching squares, then segment tracing and two Chaikin
  passes; province and sea-zone borders use the same smoothing.
- Glyphs (trees, peaks, dunes, reeds, ports, capitals) and labels are vector
  drawing, so they stay crisp at any zoom and need no atlas.
- Fog of war is a low-resolution texture with a blur shader, so revealing a zone
  rebuilds one small image instead of thousands of draw calls.
- The animated sea is a shader over a backdrop larger than the map; grain and
  vignette are screen-space passes.

---

## Animation inventory

| Motion | Where |
|--------|-------|
| Drifting swell and hatch on the sea | `ui/shaders/sea.gdshader` |
| Fog reveal fade, unknown -> fogged -> visible | `MapOverlay` |
| Selection pulse and click ripple | `MapOverlay` |
| Fleet bobbing, wake, pennant | `scripts/map/ship.gd` |
| Camera intro glide, inertia, smooth zoom | `MapCamera`, `MapScreen._intro` |
| Panel slide-in, treasury count-up, income float | `GameHud` |
| Toast queue fade, end-turn glow pulse | `GameHud` |
| Parchment fade from black on load | `scenes/map_screen.tscn` |

Two frames two seconds apart differ on ~8% of pixels (sea, ships, glow) while
the HUD stays static — motion is localised, not noisy.

---

## Performance notes

- One-time build: ~0.55 s for a 128x84 map (generation ~0.5 s, canvas ~40 ms).
- Steady state: the static canvas issues its draw commands once; only the overlay
  (fog texture + a few outlines) and the ship layer redraw per frame.
- Input is acknowledged in the same frame (camera state changes immediately,
  easing is visual only).

---

## Known limits (demo scope)

- Province/fleet orders are illustrative: they raise a toast, they do not mutate
  a rules engine.
- Only the Old World region is generated; no warp zones or New World map.
- Fog is a presentation-only reveal; ownership intel is not modelled per player.
- No save/load, no AI, no combat.
