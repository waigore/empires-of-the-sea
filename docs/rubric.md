# Evaluation rubric — Empires of the Sea

Always-referable quality gate for design, implementation, and review.

| Source | Role |
|--------|------|
| [Game rules (wiki)](https://github.com/waigore/empires-of-the-sea/wiki) | Mechanics source of truth (P2) |
| [`requirements.md`](requirements.md) | Product pillars (`REQ-*`) |
| [`../AGENTS.md`](../AGENTS.md) | Agent entry point |

Use requirement IDs (`REQ-P*-**`) in PRs, reviews, and agent summaries so judgments stay traceable.

---

## How to apply

1. Identify which pillars the change touches (`P1`–`P4`). Untouched pillars may be marked **N/A**.
2. For each touched pillar, score every applicable criterion below.
3. Compute pillar outcome, then overall outcome.
4. Cite failing `REQ-*` / `RUB-*` IDs when requesting changes.

**Do not treat N/A as a pass.** N/A only means the change does not affect that criterion.

---

## Score scale

| Score | Label | Meaning |
|------:|-------|---------|
| 3 | Exemplary | Exceeds the bar; reusable pattern or clear headroom |
| 2 | Meets | Satisfies the requirement without material gaps |
| 1 | Partial | Directionally right; gaps that block “done” |
| 0 | Fail | Missing, contradicted, or harmful to the pillar |
| — | N/A | Outside scope of this change |

**Pillar pass:** all applicable criteria scored **≥ 2**, and no applicable criterion scored **0**.  
**Overall pass:** every touched pillar passes. Any **0** on an applicable criterion → overall fail.

Milestone / release reviews should score all pillars (no blanket N/A).

---

## P1 — Presentation & immersion

| ID | Criterion | 3 | 2 | 1 | 0 |
|----|-----------|---|---|---|---|
| RUB-P1-01 | 2D presentation (`REQ-P1-01`) | Polished 2D pipeline reused elsewhere | Clearly 2D-first, fits project patterns | Mixed or unclear presentation path | 3D/core play or broken 2D framing |
| RUB-P1-02 | Period aesthetic (`REQ-P1-02`) | Strong 16–18th c. colonial maritime identity | Motifs/UI/art clearly period-aligned | Generic or weakly period | Wrong era/genre reads as primary |
| RUB-P1-03 | Graphics immersion (`REQ-P1-03`) | Cohesive player-facing art ready for ship | Readable, intentional art for shipped surfaces | Placeholder-heavy on player-facing paths | Clashes, illegible, or throwaway as “final” |
| RUB-P1-04 | Animation immersion (`REQ-P1-04`) | Motion clarifies state and world feel | Key actions/transitions animated appropriately | Sparse/janky motion; immersion incomplete | No meaningful motion, or motion hides rules/input |
| RUB-P1-05 | Desktop + mobile UX (`REQ-P1-05`) | Excellent both input modes | Touch + mouse/keyboard both viable | One mode awkward but usable | Critical path fails on a target form factor |

---

## P2 — Rules fidelity

| ID | Criterion | 3 | 2 | 1 | 0 |
|----|-----------|---|---|---|---|
| RUB-P2-01 | Source of truth (`REQ-P2-01`) | Wiki page + code cross-linked cleanly | Behavior matches wiki Game rules | Behavior partly undocumented | Undocumented or conflicting “truth” |
| RUB-P2-02 | Coverage (`REQ-P2-02`) | Domain complete incl. edge cases | All in-scope rules for the change implemented | Major cases only; known holes | Required rules skipped or faked |
| RUB-P2-03 | No bypass (`REQ-P2-03`) | UI/AI proven to go through rules APIs | Presentation cannot override outcomes | Soft bypasses or dual logic paths | Cheats/shortcuts contradict rules |
| RUB-P2-04 | Verified (`REQ-P2-04`) | Strong tests for edges + regressions | Meaningful unit tests; CI gate still met | Thin tests / happy-path only | No tests where rules changed, or CI broken |
| RUB-P2-05 | Docs sync (`REQ-P2-05`) | Wiki + rationale updated with change | Wiki rules page updated in same change | Wiki lags with promised follow-up | Behavior changed; wiki silent |

---

## P3 — Modular architecture

| ID | Criterion | 3 | 2 | 1 | 0 |
|----|-----------|---|---|---|---|
| RUB-P3-01 | Boundaries (`REQ-P3-01`) | Clean module, easy to extend | Clear ownership; fits layout conventions | Blurry ownership; growing grab-bag | Cross-cutting spaghetti / new framework without need |
| RUB-P3-02 | Coupling (`REQ-P3-02`) | Signal/API seams reused project-wide | Loose coupling; no deep reach-ins | Some brittle node paths | Tight god-object / hidden globals |
| RUB-P3-03 | Rules vs view (`REQ-P3-03`) | Simulation runnable headless/tests | Rules authoritative; view is reactive | Mixed authority in places | View owns rule outcomes |
| RUB-P3-04 | Testability (`REQ-P3-04`) | Isolated tests + seams for future ones | New logic covered under `tests/` | Hard to test; minimal coverage | Untestable structure |
| RUB-P3-05 | Platform thinness (`REQ-P3-05`) | Shared core; adapters minimal | Platform diffs isolated | Scattered `OS` checks in gameplay | Gameplay forked per platform |

---

## P4 — Performance & latency

| ID | Criterion | 3 | 2 | 1 | 0 |
|----|-----------|---|---|---|---|
| RUB-P4-01 | Frame budget (`REQ-P4-01`) | Profiled; clear headroom | No material hitch on target paths | Occasional hitch under load | Persistent jank on normal play |
| RUB-P4-02 | Input latency (`REQ-P4-02`) | Instant feedback + deferred work | Input ack within ~1–2 frames | Noticeable delay, still usable | Actions feel buffered/stuck |
| RUB-P4-03 | Non-blocking sim (`REQ-P4-03`) | Chunked/async with clear UX | Long work does not freeze UI | Brief freezes on heavy turns | Multi-second UI freeze on player path |
| RUB-P4-04 | Assets/memory (`REQ-P4-04`) | Atlases/reuse; tight imports | Reasonable imports; no obvious leaks | Heavy assets without care | Unbounded growth or reckless imports |
| RUB-P4-05 | Regression awareness (`REQ-P4-05`) | Measured before/after | Impact considered; no known stalls shipped | Unknown impact, risk accepted loosely | Known severe regression shipped |

---

## Decision record (copy into PR / review)

```text
Pillars touched: P_
RUB scores:
  P1: … (or N/A)
  P2: …
  P3: …
  P4: …
Overall: PASS | FAIL
Blocking IDs: …
Notes: …
```

---

## Rubric maintenance

- New high-level requirements get a `REQ-*` in `requirements.md` and a matching `RUB-*` row here.
- Do not remove IDs; mark obsolete criteria as deprecated with a replacement ID.
- Keep scores behavioral and observable—prefer “what a reviewer can see/run” over intent-only language.
