# Project skills

Canonical skill bodies live here (one folder per skill). Native facades and authoring rules: [`docs/skills.md`](../../docs/skills.md).

## Catalog

| Skill | Purpose |
|-------|---------|
| [`audit-deferred-agent`](audit-deferred-agent/SKILL.md) | Audit deferred vs code/wiki; re-rank gaps; update `docs/deferred.md`; docs-only PR |
| [`babysit-pr-agent`](babysit-pr-agent/SKILL.md) | Soft Actions queue (~3), unblock one same-repo PR for squash auto-merge |
| [`elucidate-design-agent`](elucidate-design-agent/SKILL.md) | Clarify unclear wiki rules/AI (P5-first); Design Record + Changelog; implement; PR; stop |
| [`export-android-debug`](export-android-debug/SKILL.md) | PR into `android-debug` so Actions publishes a debug APK GitHub Release; no local export unless asked |
| [`fix-tests-agent`](fix-tests-agent/SKILL.md) | Hourly (gated on open `ci-tier2`); fix full-suite failure; PR; babysit; close issue |
| [`free-playtest-agent`](free-playtest-agent/SKILL.md) | GameForge free-playtest hard-to-reach areas; harness + fixes; wiki diary/learnings; PR |
| [`hunt-defects-agent`](hunt-defects-agent/SKILL.md) | Playtest implemented wiki rules; fix session defects; P2 hill climb; open PR; stop |
| [`implement-feature-agent`](implement-feature-agent/SKILL.md) | Implement next (or cited) feature vs REQ/wiki/RUB; largest playable desktop+mobile change; self-score; PR; stop |
| [`map-lens`](map-lens/SKILL.md) | Add/change a map lens: pure projection, above-fog plaques, HUD key, desktop+mobile tests |
| [`optimize-tests-agent`](optimize-tests-agent/SKILL.md) | Profile and cut suite time; keep ≤5 min coverage / ≤2 min e2e; PR; stop |
| [`refactor-code-agent`](refactor-code-agent/SKILL.md) | Autonomously pick worst arch smell (+ recent-PR hotspots); aggressive themed refactor; PR; stop |
