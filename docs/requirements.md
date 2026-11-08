# High-level requirements — Empires of the Sea

Canonical product requirements. Score work with [`rubric.md`](rubric.md).  
**Rules SoT:** [wiki](https://github.com/waigore/empires-of-the-sea/wiki).  
**Platforms:** desktop + mobile. **Presentation:** 2D Godot 4 with immersive art, animation, era music.

## Pillars

| ID | Pillar | Intent |
|----|--------|--------|
| P1 | Presentation & immersion | 16th–18th c. European colonial / Age of Sail feel |
| P2 | Rules fidelity | Complete, correct wiki rules |
| P3 | Modular architecture | Composable, replaceable, testable systems |
| P4 | Performance & latency | Smooth play, responsive input |

Map every change to ≥1 pillar; challenge work that maps to none.

## P1 — Presentation & immersion

- **REQ-P1-01** — Primary gameplay is 2D; no 3D core loops.
- **REQ-P1-02** — Visual language evokes 16th–18th c. European colonial maritime eras (not fantasy/sci-fi/modern).
- **REQ-P1-03** — Player-facing art: readable silhouettes, period motifs, coherent world—not placeholder-as-final.
- **REQ-P1-04** — Meaningful motion for ships, sea/weather, UI, state changes; never hide rules or block input (P4).
- **REQ-P1-05** — Usable on phone and desktop; no hover-only critical UX; resolution-independent UI.
- **REQ-P1-06** — Default music period-fitting (prefer Baroque/Classical); mute/volume controllable; don’t obscure feedback.

## P2 — Rules fidelity

- **REQ-P2-01** — Wiki is rules SoT; code implements it; undocumented house rules ≠ done.
- **REQ-P2-02** — All wiki domains implemented or explicitly out-of-scope for the milestone.
- **REQ-P2-03** — UI/AI must not bypass or contradict rules; sims/tests share the engine where practical.
- **REQ-P2-04** — Rules logic unit-tested; meet CI coverage gate with meaningful cases.
- **REQ-P2-05** — Behavior changes update the wiki in the same change (or a release-blocking follow-up).

## P3 — Modular architecture (SOLID; CI: `arch-lint`)

- **REQ-P3-01** (**S**) — One domain per module; agreed layout; no god files (size/method caps). Prefer extending existing modules over new frameworks (**O**); subtypes honor contracts (**L**).
- **REQ-P3-02** (**I**) — Narrow APIs/signals over deep reach-ins; no undeclared autoloads (allowlist only when truly cross-cutting).
- **REQ-P3-03** (**D**) — Rules/sim usable without visual nodes; view reads state and emits intents.
- **REQ-P3-04** — Modules testable in isolation; changed `scripts/rules/**` ships tests under `tests/`.
- **REQ-P3-05** — Platform diffs only in `scripts/platform/**`; core shared.

## P4 — Performance & latency

- **REQ-P4-01** — Stable interactive frame rates; avoid poorly scaling per-frame work.
- **REQ-P4-02** — Acknowledge input within ~1–2 frames; defer heavy work off the critical path.
- **REQ-P4-03** — Turn/AI/pathfinding must not freeze UI; chunk/async with progress when waits are needed.
- **REQ-P4-04** — Intentional imports; prefer atlases/reuse; no unbounded hot-loop allocations.
- **REQ-P4-05** — Note impact; don’t ship known multi-second stalls on player paths.

## Non-goals

Photoreal/3D primary play; networked multiplayer unless wiki+roadmap say so; unrelated naval-game parity; hover-only critical UX.

## How to use

1. Read wiki Game rules for mechanics.  
2. Map task → `P*` / `REQ-*`.  
3. Gate with [`rubric.md`](rubric.md).  
4. Keep this high-level; mechanics stay in the wiki.
