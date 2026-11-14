# High-level requirements — Empires of the Sea

Score with [`rubric.md`](rubric.md). **Rules SoT:** [wiki](https://github.com/waigore/empires-of-the-sea/wiki). 2D Godot 4; desktop, phone, tablet; map to ≥1 pillar.

## Pillars

| ID | Pillar | Intent |
|----|--------|--------|
| P1 | Presentation & immersion | 16th–18th c. colonial / Age of Sail |
| P2 | Rules fidelity | Complete, correct wiki rules |
| P3 | Modular architecture | Composable, replaceable, testable |
| P4 | Performance & latency | Smooth, responsive play |
| P5 | Usability & agency | Efficient paths; platform parity |

## P1 — Presentation & immersion

- **REQ-P1-01** — 2D primary play; no 3D core loops.
- **REQ-P1-02** — 16th–18th c. European colonial maritime look (not fantasy/sci-fi/modern).
- **REQ-P1-03** — Readable silhouettes, period motifs—not placeholder-as-final.
- **REQ-P1-04** — Meaningful motion; never hide rules or block input (P4).
- **REQ-P1-05** — Phone, tablet, desktop; no hover-only critical UX; resolution-independent UI.
- **REQ-P1-06** — Period default music; mute/volume; don’t obscure feedback.
- **REQ-P1-07** — Readable UI: contrast, type, density; critical chrome legible phone+tablet+desktop; scan over decor. Map stays readable: chrome on the bar; weigh overlays that obscure it (soft).
- **REQ-P1-08** — Distinct intentional icon per player-facing entity type; GameForge/image-gen; period-fit (`REQ-P1-02`) + shared style; no placeholder/emoji/default.

## P2 — Rules fidelity

- **REQ-P2-01** — Wiki is SoT; undocumented house rules ≠ done.
- **REQ-P2-02** — Wiki domains implemented or out-of-scope for milestone.
- **REQ-P2-03** — UI/AI must not bypass/contradict rules; share engine in sims/tests where practical.
- **REQ-P2-04** — Rules unit-tested; CI coverage gate with real cases.
- **REQ-P2-05** — Behavior changes update wiki same change.

## P3 — Modular architecture (SOLID; `arch-lint`)

- **REQ-P3-01** (**S**) — One domain/module; ≤400/≤25 (allowlist ≤5, shrink-only). Extend (**O**); honor (**L**).
- **REQ-P3-02** (**I**) — Narrow APIs/signals; no undeclared autoloads.
- **REQ-P3-03** (**D**) — Rules/sim without visual nodes; view reads state, emits intents.
- **REQ-P3-04** — Changed `scripts/rules/**` ships `tests/`.
- **REQ-P3-05** — Platform diffs only in `scripts/platform/**`.

## P4 — Performance & latency

- **REQ-P4-01** — Stable framerates; avoid poorly scaling per-frame work.
- **REQ-P4-02** — Input ack in ~1–2 frames; defer heavy work.
- **REQ-P4-03** — Turn/AI/pathfinding must not freeze UI; chunk/async when needed.
- **REQ-P4-04** — Intentional imports; atlases/reuse; no unbounded hot-loop allocs.
- **REQ-P4-05** — Don’t ship known multi-second stalls.

## P5 — Usability & agency

P1 = look; P4 = latency; P5 = agency. Same outcomes everywhere; paths differ.

- **REQ-P5-01** — Empire/strategic actions on main surface; clear critical entry.
- **REQ-P5-02** — Choice primary; bookkeeping batched or deferred.
- **REQ-P5-03** — Competitive actions in scope discoverable, not buried.
- **REQ-P5-04** — Chores: batch, default, or confirm-once (not one-by-one).
- **REQ-P5-05** — State-change ack ~1–2 frames (`REQ-P4-02`); never silent.
- **REQ-P5-06** — Juice non-modal/skippable; no hidden outcomes (`REQ-P2-03`); no hitches (`REQ-P4-*`).
- **REQ-P5-07** — Intent parity phone+tablet↔desktop. Allowed: OS chrome, safe areas, packaging, `scripts/platform/**`, perf—not desktop-only or weaker mobile.

## Non-goals

Photoreal/3D primary; networked multiplayer unless the wiki says so; hover-only critical UX; desktop-only that cuts mobile.
