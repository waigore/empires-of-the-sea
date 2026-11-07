# High-level requirements — Empires of the Sea

Canonical product requirements for agents and humans. Evaluate work against [`rubric.md`](rubric.md).

**Platforms:** desktop (Windows, macOS, Linux) and mobile (Android, iOS).  
**Presentation:** 2D Godot 4 gameplay with immersive art and animation.

---

## Pillars

| ID | Pillar | Intent |
|----|--------|--------|
| P1 | Presentation & immersion | 2D play that feels like 16th–18th century European colonial / Age of Sail worlds |
| P2 | Rules fidelity | Complete, correct implementation of the game’s rules |
| P3 | Modular architecture | Composable systems that stay replaceable and testable |
| P4 | Performance & latency | Smooth play and responsive input on target devices |

Every feature, PR, and design choice should map to at least one pillar. If it maps to none, challenge the change.

---

## P1 — Presentation & immersion

### REQ-P1-01 — 2D gameplay presentation
All primary gameplay is 2D (sprites, tilemaps, UI overlays, 2D VFX). 3D is not used for core play loops.

### REQ-P1-02 — Colonial / Age of Sail aesthetic (16th–18th century Europe)
Visual language (ships, ports, maps, UI chrome, typography, color, heraldry cues) should evoke European colonial maritime eras of roughly the 16th–18th centuries—not generic fantasy, sci-fi, or modern naval themes.

### REQ-P1-03 — Immersive graphics
Art direction prioritizes readable silhouettes, period-appropriate materials/motifs, and coherent world presentation over placeholder or purely utilitarian graphics once a system ships as “player-facing.”

### REQ-P1-04 — Immersive animation
Meaningful motion for ships, weather/sea feel, UI feedback, and state changes. Idle and transition animations should support immersion without blocking rules clarity or input responsiveness (see P4).

### REQ-P1-05 — Cross-platform presentation
Layouts, touch targets, and visual scale remain usable on phones and desktops. No hover-only critical UX; resolution-independent UI (anchors, containers, theme scales).

---

## P2 — Rules fidelity

### REQ-P2-01 — Single source of truth
Game rules live in a documented ruleset (under `docs/` or linked design docs). Code implements that document; undocumented house rules are not accepted as “done.”

### REQ-P2-02 — Full rules coverage
All defined rules domains (e.g. turn structure, movement, combat, economy, victory, edge cases) are implemented or explicitly tracked as out-of-scope for a given milestone. “Partial” is only valid when the ruleset marks the rule optional/deferred.

### REQ-P2-03 — Correctness over convenience
UI shortcuts and AI helpers must not bypass or contradict rules. Simulations, replays, and tests should agree with the same rules engine where practical.

### REQ-P2-04 — Verifiable rules
Rules logic is unit-tested (gd-tools). Coverage of rules modules is expected to meet or exceed the project CI gate (`gd-tools test --coverage --min 80`) with meaningful cases, not only happy paths.

### REQ-P2-05 — Rules changes are documented
Changing behavior requires updating the rules source of truth in the same change set (or an immediately linked follow-up that blocks release of that behavior).

---

## P3 — Modular architecture

### REQ-P3-01 — Clear module boundaries
Gameplay domains (e.g. map, fleet, combat, economy, UI, persistence) live in focused scenes/scripts with explicit APIs. Prefer extending existing modules over new frameworks.

### REQ-P3-02 — Loose coupling
Prefer signals, small adapters, and dependency injection–style wiring over deep node-path reach-ins and god-objects. Autoloads only for true cross-cutting concerns.

### REQ-P3-03 — Rules engine separable from presentation
Rules/simulation state must be usable without relying on visual nodes. Presentation reads state and emits intents; it does not own authoritative rule outcomes.

### REQ-P3-04 — Testability
Modules are testable in isolation (pure logic or mocked collaborators). New systems ship with tests under `tests/`.

### REQ-P3-05 — Platform adapters stay thin
Desktop vs mobile differences (input, safe areas, performance knobs) stay behind feature checks or small adapters; core logic remains shared.

---

## P4 — Performance & latency

### REQ-P4-01 — Frame budget
Target stable interactive frame rates on mid-range desktop and supported mobile devices. Avoid per-frame work that scales poorly with fleets, map size, or VFX without measurement and mitigation.

### REQ-P4-02 — Input latency
Player actions (tap/click, drag, confirm) feel immediate: acknowledge input within one or two frames where possible; heavy work deferred off the critical path or chunked.

### REQ-P4-03 — Rules/AI without hitching
Turn resolution, pathfinding, and AI decisions must not freeze the UI. Long work uses async/chunking/worker patterns appropriate to Godot, with progress feedback when waits are unavoidable.

### REQ-P4-04 — Asset and memory discipline
Textures, atlases, audio, and animation resources use intentional import settings. Prefer atlases and reuse; avoid unbounded runtime allocations in hot loops.

### REQ-P4-05 — Measurable regressions
Performance-sensitive changes should note expected impact and, when feasible, include a simple before/after check (profiler notes, frame-time observation, or automated smoke). Do not ship known multi-second stalls on player-facing paths.

---

## Non-goals (current scope)

- Photorealistic or 3D primary gameplay
- Networked multiplayer unless explicitly added to the ruleset and roadmap
- Feature parity with unrelated naval games outside the project ruleset
- Hover-only or desktop-exclusive critical UX

---

## How to use

1. Map a task to pillar IDs (`P1`–`P4`) and relevant `REQ-*` IDs.
2. Score or gate the work with [`rubric.md`](rubric.md).
3. Keep this file high-level; put detailed mechanics in the ruleset docs once they exist.
