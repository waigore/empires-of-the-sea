# Design record + changelog shapes

Wiki SoT: [Design Records](https://github.com/waigore/empires-of-the-sea/wiki/design-records), [Design Changelog](https://github.com/waigore/empires-of-the-sea/wiki/design-changelog).

## Allocate an ID

1. Use **UTC** date `YYYYMMDD`.
2. List existing `DR-YYYYMMDD-*` / `dr-YYYYMMDD-*` pages for that day.
3. Next `NN` = max existing + 1, zero-padded to **2** digits (`01`…`99`). If ≥100 that day, use 3 digits.
4. ID = `DR-YYYYMMDD-NN`. Page slug = `dr-YYYYMMDD-NN`.

IDs sort chronologically as plain text. Never reuse or renumber.

## New record page (`dr-YYYYMMDD-NN.md`)

```markdown
# DR-YYYYMMDD-NN — Short title

| Field | Value |
|-------|-------|
| **Status** | accepted |
| **Date** | YYYY-MM-DD (UTC) |
| **Theme** | <one theme for this run's batch> |
| **Supersedes** | none |

## Sources

- Unclear: <page#section> …
- Checked, already clear / not resolving this: <page> …

## Ambiguity

<what was unclear, contradictory, or missing>

## Change

<precise elucidated rule or AI behavior>

## Reasoning

P5-first: <which REQ-P5-* / RUB-P5-*>. Other pillars: <brief or N/A>.

## Impact

- Wiki: <pages edited>
- Code: <systems / none>
- Player-visible: <one sentence>
```

## Index + changelog

On `design-records.md`, **prepend** a table row (newest first).

On `design-changelog.md`, **prepend**:

```markdown
## DR-YYYYMMDD-NN — Short title
- **Change:** one sentence
- **Impact:** wiki pages + systems touched
- **Record:** [DR-YYYYMMDD-NN](dr-YYYYMMDD-NN)
```

Remove the `_(No entries yet.)_` / `_(none yet)_` placeholders on first real entry.
