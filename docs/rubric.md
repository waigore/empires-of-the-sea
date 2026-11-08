# Evaluation rubric — Empires of the Sea

Quality gate for design, implementation, and review. Cite `REQ-*` / `RUB-*` in PRs.

| Source | Role |
|--------|------|
| [Game rules (wiki)](https://github.com/waigore/empires-of-the-sea/wiki) | Mechanics SoT (P2) |
| [`requirements.md`](requirements.md) | Product pillars (`REQ-*`) |
| [`../AGENTS.md`](../AGENTS.md) | Agent entry |

## How to apply

1. Identify touched pillars (`P1`–`P4`); others may be **N/A** (N/A ≠ pass).
2. Score every applicable criterion; compute pillar then overall outcome.
3. Cite failing IDs when requesting changes.

## Score scale

| Score | Label | Meaning |
|------:|-------|---------|
| 3 | Exemplary | Exceeds bar; reusable pattern |
| 2 | Meets | Satisfies without material gaps |
| 1 | Partial | Directionally right; blocks “done” |
| 0 | Fail | Missing, contradicted, or harmful |
| — | N/A | Outside this change |

**Pillar pass:** all applicable ≥ 2 and none 0. **Overall pass:** every touched pillar passes. Any applicable **0** → fail. Milestone reviews score all pillars.

## Criteria (pass = score ≥ 2)

### P1 — Presentation & immersion

| ID | Pass bar (`REQ`) |
|----|------------------|
| RUB-P1-01 | Clearly 2D-first (`REQ-P1-01`) |
| RUB-P1-02 | Motifs/UI/art period-aligned 16–18th c. (`REQ-P1-02`) |
| RUB-P1-03 | Readable, intentional art on shipped surfaces (`REQ-P1-03`) |
| RUB-P1-04 | Key actions/transitions animated appropriately (`REQ-P1-04`) |
| RUB-P1-05 | Touch + mouse/keyboard both viable (`REQ-P1-05`) |
| RUB-P1-06 | Period-fitting default music; mute/volume work (`REQ-P1-06`) |

### P2 — Rules fidelity

| ID | Pass bar (`REQ`) |
|----|------------------|
| RUB-P2-01 | Behavior matches wiki Game rules (`REQ-P2-01`) |
| RUB-P2-02 | All in-scope rules for the change implemented (`REQ-P2-02`) |
| RUB-P2-03 | Presentation cannot override outcomes (`REQ-P2-03`) |
| RUB-P2-04 | Meaningful unit tests; CI gate met (`REQ-P2-04`) |
| RUB-P2-05 | Wiki rules updated in same change (`REQ-P2-05`) |

### P3 — Modular architecture (SOLID; `arch-lint`)

| ID | Pass bar (`REQ`) |
|----|------------------|
| RUB-P3-01 | **S:** one domain; layout OK; ≤400/25 (allowlist ≤5, shrink-only; hard ≤650/45) (`REQ-P3-01`) |
| RUB-P3-02 | **I:** no deep `get_node`/`$` (depth ≥3); autoloads only if allowlisted (`REQ-P3-02`) |
| RUB-P3-03 | **D:** `scripts/rules` is RefCounted/Object-only; view reactive (`REQ-P3-03`) |
| RUB-P3-04 | Changed rules paired with `tests/` changes (`REQ-P3-04`) |
| RUB-P3-05 | OS/platform APIs only under `scripts/platform/**` (`REQ-P3-05`) |

### P4 — Performance & latency

| ID | Pass bar (`REQ`) |
|----|------------------|
| RUB-P4-01 | No material hitch on target paths (`REQ-P4-01`) |
| RUB-P4-02 | Input ack within ~1–2 frames (`REQ-P4-02`) |
| RUB-P4-03 | Long work does not freeze UI (`REQ-P4-03`) |
| RUB-P4-04 | Reasonable imports; no obvious leaks (`REQ-P4-04`) |
| RUB-P4-05 | Impact considered; no known stalls shipped (`REQ-P4-05`) |

## Decision record

```text
Pillars touched: P_
RUB scores: P1… P2… P3… P4… (or N/A)
Overall: PASS | FAIL
Blocking IDs: …
Notes: …
```

## Maintenance

New high-level needs get matching `REQ-*` + `RUB-*`. Don’t remove IDs—deprecate with a replacement. Keep scores behavioral and observable.
