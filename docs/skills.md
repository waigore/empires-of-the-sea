# Project skills

Canonical skill bodies live under [`.agents/skills/`](../.agents/skills/) (one folder per skill). That tree is the only source of truth.

## Native wiring

When a project skill is created or renamed, add thin facades for OpenCode, Cursor, and Grok. Facades carry the same `name` / `description` frontmatter and point at the canonical body — they must not duplicate the workflow.

| Agent | Facade path |
|-------|-------------|
| Cursor | `.cursor/skills/<skill-name>/SKILL.md` |
| OpenCode | `.opencode/skill/<skill-name>/SKILL.md` |
| Grok | `.grok/skills/<skill-name>/SKILL.md` |

### Facade template

```markdown
---
name: <skill-name>
description: |-
  <same description as the canonical skill>
---

# <Title> (facade)

Canonical instructions: [`.agents/skills/<skill-name>/SKILL.md`](../../../.agents/skills/<skill-name>/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
```

### Rules

- Edit the body only under `.agents/skills/<skill-name>/`.
- Keep facade frontmatter in sync when you change the canonical `name` or `description`.
- Do not replace a facade with a full copy of the skill.

## Catalog

Listed in [`.agents/skills/README.md`](../.agents/skills/README.md).
