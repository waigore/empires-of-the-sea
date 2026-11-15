# Evaluation rubric — Empires of the Sea

Cite `REQ-*`/`RUB-*` in PRs.

| Source | Role |
|--------|------|
| [Game rules (wiki)](https://github.com/waigore/empires-of-the-sea/wiki) | Mechanics SoT (P2) |
| [`requirements.md`](requirements.md) | Product pillars (`REQ-*`) |
| [`../AGENTS.md`](../AGENTS.md) | Agent entry |

## How to apply

1. Touched pillars (`P1`–`P5`); others **N/A** (≠ pass).
2. Score applicable criteria; pillar then overall.
3. Cite failing IDs.

## Score scale

| Score | Label | Meaning |
|------:|-------|---------|
| 3 | Exemplary | Exceeds bar; reusable |
| 2 | Meets | Satisfies without material gaps |
| 1 | Partial | Directionally right; blocks done |
| 0 | Fail | Missing, contradicted, harmful |
| — | N/A | Outside this change |

**Pass:** applicable ≥ 2, none 0 per touched pillar; overall = all touched pass. Any **0** fails.

## Criteria (pass ≥2)

### P1 — Presentation & immersion

| ID | Pass bar |
|----|----------|
| RUB-P1-01 | 2D-first (`REQ-P1-01`) |
| RUB-P1-02 | Period motifs/UI/art 16–18th c (`REQ-P1-02`) |
| RUB-P1-03 | Readable intentional art (`REQ-P1-03`) |
| RUB-P1-04 | Key actions/transitions animated (`REQ-P1-04`) |
| RUB-P1-05 | Touch + mouse/keyboard OK (`REQ-P1-05`) |
| RUB-P1-06 | Period music; mute/volume (`REQ-P1-06`) |
| RUB-P1-07 | Readable UI at target sizes; map unobscured, chrome on the bar (`REQ-P1-07`) |
| RUB-P1-08 | Entity icons; theme + style (`REQ-P1-08`) |

### P2 — Rules fidelity

| ID | Pass bar |
|----|----------|
| RUB-P2-01 | Matches wiki Game rules (`REQ-P2-01`) |
| RUB-P2-02 | In-scope rules implemented (`REQ-P2-02`) |
| RUB-P2-03 | Presentation cannot override outcomes (`REQ-P2-03`) |
| RUB-P2-04 | Unit tests; CI (`REQ-P2-04`) |
| RUB-P2-05 | Wiki updated same change (`REQ-P2-05`) |

### P3 — Modular architecture (`arch-lint`)

| ID | Pass bar |
|----|----------|
| RUB-P3-01 | **S:** one domain; ≤400/25 (allowlist ≤5 shrink-only; hard ≤650/45) (`REQ-P3-01`) |
| RUB-P3-02 | **I:** no deep `get_node`/`$` (≥3); autoloads allowlisted (`REQ-P3-02`) |
| RUB-P3-03 | **D:** `scripts/rules` RefCounted/Object-only; view reactive (`REQ-P3-03`) |
| RUB-P3-04 | Changed rules with `tests/` (`REQ-P3-04`) |
| RUB-P3-05 | OS APIs only in `scripts/platform/**` (`REQ-P3-05`) |

### P4 — Performance & latency

| ID | Pass bar |
|----|----------|
| RUB-P4-01 | No material hitch (`REQ-P4-01`) |
| RUB-P4-02 | Input ack within ~1–2 frames (`REQ-P4-02`) |
| RUB-P4-03 | Long work does not freeze UI (`REQ-P4-03`) |
| RUB-P4-04 | Reasonable imports; no leaks (`REQ-P4-04`) |
| RUB-P4-05 | No known stalls shipped (`REQ-P4-05`) |

### P5 — Usability & agency

| ID | Pass bar |
|----|----------|
| RUB-P5-01 | Clear empire/strategic action entry (`REQ-P5-01`) |
| RUB-P5-02 | Choice primary; bookkeeping batched (`REQ-P5-02`) |
| RUB-P5-03 | Competitive actions discoverable (`REQ-P5-03`) |
| RUB-P5-04 | Batch/default/confirm-once for chores (`REQ-P5-04`) |
| RUB-P5-05 | State-change ack ~1–2 frames; never silent (`REQ-P5-05`) |
| RUB-P5-06 | Juice non-modal/skippable; no hidden outcomes (`REQ-P5-06`) |
| RUB-P5-07 | Phone+tablet↔desktop intent parity (`REQ-P5-07`) |

## Decision record

```text
Pillars touched: P_
RUB scores: P1… P2… P3… P4… P5… (or N/A)
Overall: PASS | FAIL
Blocking IDs: …
Notes: …
```

## Maintenance

New needs get `REQ-*`+`RUB-*`. Don’t remove IDs—deprecate.
