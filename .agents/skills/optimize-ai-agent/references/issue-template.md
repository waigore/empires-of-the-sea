# AI planner gap — issue template

**Title:** `[AI] <short planner gap>`

**Labels:** `todo` + `bug` (wrong/suboptimal live behavior) or `enhancement`
(missing planner use of an already-shipped feature)

```markdown
## Summary
<1–2 sentences: which planner / feature is mis- or under-used>

## Evidence (AI-vs-AI)
- Seed / size / turns: <e.g. 1500 / Standard / 200>
- Harness: <tools/ai_vs_ai.gd | live observer | probe>
- Crowns / outcome: <winner or unfinished; notable standings>
- Signals: <order mix, provinces/power, wars, under-used feature>

## Expected
<competitive / optimized planner behavior; cite wiki AI or docs/ai.md>

## Actual
<what the run showed>

## Analysis
- Likely locus: <scripts/ai/… or map_play_* AI wiring>
- Gap type: <mis-use | under-use | suboptimal heuristic>
- Wiki / docs alignment: <matches | conflicts | silent>
- Severity: <major | minor | polish>
- Not in scope: <rules-outside-AI | missing feature | UX — if relevant>

## Acceptance
- [ ] Planner uses the feature competitively in a comparable AI-vs-AI / probe run
```
