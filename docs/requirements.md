# High-level requirements — Empires of the Sea

Score with [`rubric.md`](rubric.md). **Rules SoT:** [wiki](https://github.com/waigore/empires-of-the-sea/wiki).  
Desktop + mobile. 2D Godot 4; immersive art, animation, era music.

## Pillars

| ID | Pillar | Intent |
|----|--------|--------|
| P1 | Presentation & immersion | 16th–18th c. colonial / Age of Sail |
| P2 | Rules fidelity | Complete, correct wiki rules |
| P3 | Modular architecture | Composable, replaceable, testable |
| P4 | Performance & latency | Smooth play, responsive input |
| P5 | Usability & agency | Efficient paths; non-blocking juice |

Map every change to ≥1 pillar; challenge work that maps to none.

## P1 — Presentation & immersion

- **REQ-P1-01** — 2D primary play; no 3D core loops.
- **REQ-P1-02** — Visual language: 16th–18th c. European colonial maritime (not fantasy/sci-fi/modern).
- **REQ-P1-03** — Readable silhouettes, period motifs, coherent world—not placeholder-as-final.
- **REQ-P1-04** — Meaningful motion; never hide rules or block input (P4).
- **REQ-P1-05** — Phone + desktop; no hover-only critical UX; resolution-independent UI.
- **REQ-P1-06** — Period default music; mute/volume; don’t obscure feedback.

## P2 — Rules fidelity

- **REQ-P2-01** — Wiki is SoT; undocumented house rules ≠ done.
- **REQ-P2-02** — Wiki domains implemented or out-of-scope for the milestone.
- **REQ-P2-03** — UI/AI must not bypass/contradict rules; share engine in sims/tests where practical.
- **REQ-P2-04** — Rules unit-tested; CI coverage gate with meaningful cases.
- **REQ-P2-05** — Behavior changes update wiki same change (or release-blocking follow-up).

## P3 — Modular architecture (SOLID; `arch-lint`)

- **REQ-P3-01** (**S**) — One domain/module; ≤400 lines/≤25 methods (allowlist ≤5, shrink-only). Prefer extend (**O**); honor contracts (**L**).
- **REQ-P3-02** (**I**) — Narrow APIs/signals; no undeclared autoloads.
- **REQ-P3-03** (**D**) — Rules/sim without visual nodes; view reads state, emits intents.
- **REQ-P3-04** — Changed `scripts/rules/**` ships `tests/`.
- **REQ-P3-05** — Platform diffs only in `scripts/platform/**`.

## P4 — Performance & latency

- **REQ-P4-01** — Stable interactive framerates; avoid poorly scaling per-frame work.
- **REQ-P4-02** — Input ack within ~1–2 frames; defer heavy work.
- **REQ-P4-03** — Turn/AI/pathfinding must not freeze UI; chunk/async when needed.
- **REQ-P4-04** — Intentional imports; atlases/reuse; no unbounded hot-loop allocations.
- **REQ-P4-05** — Don’t ship known multi-second stalls on player paths.

## P5 — Usability & agency

P1 = presentation; P4 = latency; P5 = agency + non-blocking feedback.

- **REQ-P5-01** — Empire/strategic actions on main surface; clear entry for critical actions.
- **REQ-P5-02** — Strategic choice primary; bookkeeping secondary, batched, or deferred.
- **REQ-P5-03** — Competitive actions in scope discoverable, not buried.
- **REQ-P5-04** — Repeated chores: batch, default, or confirm-once (not forced one-by-one when N>1).
- **REQ-P5-05** — State-change ack within ~1–2 frames (`REQ-P4-02`); never silent.
- **REQ-P5-06** — Juice non-modal/skippable; no hidden outcomes (`REQ-P2-03`); no hitches (`REQ-P4-*`).

## Non-goals

Photoreal/3D primary play; networked multiplayer unless wiki+roadmap say so; unrelated naval-game parity; hover-only critical UX.

## How to use

Wiki for mechanics → map to `P*` / `REQ-*` → gate with [`rubric.md`](rubric.md). Mechanics stay in the wiki.
