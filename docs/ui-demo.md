# Map screen demo

Player-facing map UI prototype: antique-atlas look, animated world, and the input model the real map keeps.

**Pillars:** P1 (presentation, animation, desktop+mobile), P2 (fog-of-war rules), P3 (boundaries), P4 (input latency, draw cost). Orders and economy are still toasts.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Pan | drag, WASD / arrows, trackpad | one-finger drag |
| Zoom | wheel, pinch, `+` / `−`, E / Q | pinch, `+` / `−` |
| Jump | click / drag minimap | tap / drag minimap |
| Select | click province or fleet | tap |
| Focus capital | `F` / `Home` | — |
| End turn | `Space` / `Enter`, gold seal | gold seal |

Pan has inertia; zoom anchors under the cursor; camera clamps to map with a cover-fit zoom floor. Actions register via `InputActions` at runtime—no hard-coded keys in gameplay.

## Architecture

```
scenes/map_screen.tscn      composition: world, camera, HUD, FX
scripts/map_screen.gd       controller: world build + input → intents
scripts/map/map_model.gd    pure tile data
scripts/map/map_generator.gd deterministic seed generation
scripts/map/map_canvas.gd   static artwork
scripts/map/map_overlay.gd  fog, hover, selection
scripts/map/map_camera.gd   pan / zoom / inertia / clamp
scripts/map/camera_math.gd  pure camera maths (tested)
scripts/map/ship_layer.gd   fleets + routes
scripts/map/ink_paths.gd    ink line smoothing
scripts/rules/turn_time.gd  turn → calendar year
scripts/rules/visibility.gd per-player fog of war (tested)
scripts/ui/*                HUD, dossier, minimap, theme
ui/shaders/*                sea, fog, grain, vignette
```

`MapModel` + `MapGenerator` are the sim side; the view reads them and never owns outcomes (`REQ-P3-03`). Swap the generator later without rewriting the renderer.

**Generation (deterministic):** noise land → terrain → provinces/sea zones (BFS) → resources → ports → ownership. Same seed → same world (`tests/test_map_generator.gd`).

**Fog of war:** `VisibilityModel` keeps three levels per player per tile (`unknown < fogged < fully visible`). Setup makes own provinces fully visible and the rest of the Old World fogged; sea zones touching an owned coast are fully visible. A fleet entering a zone charts its water and the strict coastal ring; End of Turn runs fog decay, distant-sea fog for zones with no owned coast or fleet, then the coastal pass. The overlay only renders that state.

**Rendering:** scaled terrain wash; marching-squares coasts + Chaikin borders; vector glyphs/labels; low-res fog texture; sea/grain/vignette shaders.

## Animation & performance

| Motion | Where |
|--------|-------|
| Sea swell | `ui/shaders/sea.gdshader` |
| Fog reveal | `MapOverlay` |
| Selection pulse / ripple | `MapOverlay` |
| Fleet bob / wake / pennant | `scripts/map/ship.gd` |
| Camera intro / inertia / zoom | `MapCamera`, `MapScreen._intro` |
| HUD slides, counts, toasts | `GameHud` |

Build ~0.55 s (128×84). Steady state: static canvas once; overlay + ships per frame. Input ack same frame.

## Known limits

Orders are toasts only (no rules engine). Old World only. No explorers, spies, prospecting, save/load, AI, or combat.
