---
name: audit-deferred-agent
description: |-
  Autonomously audit Empires of the Sea deferred features against code and
  wiki: collect deferred / out-of-scope / playable-slice notes from docs,
  wiki, Design Records and the Design Changelog; mark what is already live;
  re-rank remaining gaps by impact; update docs/deferred.md and domain
  Deferred sections; open one docs-only PR; stop. Analysis only — do not
  implement features. Ask the user only on true blockers. Use when the user
  asks to audit deferred, rank deferred features, update the deferred
  backlog, or run the audit-deferred agent.

  Examples:
    - no target → full audit, update docs, PR, stop
    - cited domain → that domain's deferred list only; still refresh deferred.md
    - "what's left to implement" → same full audit path
---

# Audit deferred agent

One **deferred backlog refresh** per run. Deliverable: an open **docs-only** PR
(or a clean stop when nothing changed). Do not merge, babysit checks, force-push,
or implement gameplay features.

Owns `REQ-P2-02` bookkeeping: what wiki/docs still call deferred vs what code
already ships, ranked so a human (or implement-feature) can pick next work.

## Sources of truth

| Source | Role |
|--------|------|
| [`docs/deferred.md`](../../../docs/deferred.md) | Ranked backlog (write target) |
| `docs/**` Deferred / Known limits / Out of scope | Domain lists (write when stale) |
| [Wiki Game rules](https://github.com/waigore/empires-of-the-sea/wiki) | Deferred / current-product / playable-slice notes (read) |
| [Design Records](https://github.com/waigore/empires-of-the-sea/wiki/design-records) + [Changelog](https://github.com/waigore/empires-of-the-sea/wiki/design-changelog) | Explicit “Deferred” bullets (read) |
| Code under `scripts/`, `tests/` | Ground truth for “already live” |
| [`docs/requirements.md`](../../../docs/requirements.md) | `REQ-P2-02` |
| [`docs/pull-requests.md`](../../../docs/pull-requests.md) | PR / checks |
| [`AGENTS.md`](../../../AGENTS.md) | Docs ≤500 words; skills isolation |
| [`references/pr-body.md`](references/pr-body.md) | PR body template |

**Not this agent:** shipping a gap → [`implement-feature-agent`](../implement-feature-agent/SKILL.md).
Wrong behavior of something already shipped → [`hunt-defects-agent`](../hunt-defects-agent/SKILL.md).
Ambiguous wiki needing a design call → [`elucidate-design-agent`](../elucidate-design-agent/SKILL.md).

Do **not** hand off or chain into implement-feature. Report the top gap; stop.

## Workflow

```text
- [ ] 1. Orient
- [ ] 2. Collect deferred claims
- [ ] 3. Verify each against code
- [ ] 4. Rank remaining gaps by impact
- [ ] 5. Update docs (or stop if unchanged)
- [ ] 6. Lint + open docs-only PR and stop
```

### 1. Orient

Sync to current `main`. Read `docs/deferred.md` if present. Skim recent Design
Changelog / merged PRs so “already live” is not missed.

### 2. Collect deferred claims

Gather every deferred / out-of-scope / “current product … deferred” claim from:

1. `docs/**` — `## Deferred`, Known limits, Out of scope, stale “is deferred” prose
2. Wiki pages — Deferred sections, Current product notes, Playable slice tables
3. Design Records + Changelog — bullets labeled Deferred / stays deferred

If the user cites a domain or theme, still refresh the global `deferred.md`
ranking, but bias verification depth to that domain.

Deduplicate by feature intent (same gap named differently → one row).

### 3. Verify each against code

For each claim, find implementing modules/tests or prove absence.

| Verdict | Meaning |
|---------|---------|
| **Live** | Behavior matches the claim’s intended rule; move to “Already live” |
| **Gap** | Wiki/docs still expect it; code missing, stub, or human-only |
| **Out of scope** | Explicit design decision (e.g. DR says never) — keep separate, unranked |
| **Blocked** | Depends on missing model (e.g. no era model) — note, do not rank as shippable |

Prefer tests + rules scripts over UI copy. Cite paths / DR ids in notes.

### 4. Rank remaining gaps by impact

Rank only **Gap** rows. Bias (highest first):

1. Unlocks a whole loop (e.g. rival New World diplomacy after fog exists)
2. Mid/late campaign fidelity (armies, trade, colonies)
3. Immersion / P1 polish with no rules payoff
4. Optional knobs / convenience (difficulty extras, view prefs)

Announce the ranking briefly, then continue without waiting.

### 5. Update docs (or stop if unchanged)

Branch `docs/audit-deferred-…` from up-to-date `main`.

- Rewrite [`docs/deferred.md`](../../../docs/deferred.md): Already live table,
  Remaining gaps (ranked), Next pick, Out-of-scope / blocked footnotes
- Fix each stale domain Deferred / Known limits section to match verdicts;
  point at `deferred.md` for the ranked list
- Keep every touched Markdown ≤ 500 words (`python tools/lint_docs_words.py`)
- Index `deferred.md` in [`docs/README.md`](../../../docs/README.md) if missing

**Wiki is read-only this run.** Do not edit skill trees in a docs PR that also
changes game code (there should be no game code). Do not implement features.

If the audit finds **no** doc drift and the ranking is unchanged, **stop
without a PR** and say so.

### 6. Lint + open docs-only PR and stop

```bash
python tools/lint_docs_words.py
```

Commit (why-focused). Push. Create the PR with `gh` using
[`references/pr-body.md`](references/pr-body.md).

**Stop** after the PR URL exists (or after the no-op stop). Do not enable
auto-merge, merge, or babysit unless the user separately asks.

## Done when

- Every collected claim has a verdict
- `docs/deferred.md` + domain docs match the audit (or explicitly unchanged)
- Docs-only PR open **or** clean no-op stop
- No feature code shipped
