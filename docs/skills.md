# Project skills

Canonical skill bodies live under [`.agents/skills/`](../.agents/skills/) (one folder per skill). That tree is the only source of truth.

## Native wiring

When a project skill is created or renamed, wire Cursor, OpenCode, and Grok facades. Facades carry the same `name` / `description` frontmatter and point at the canonical body — they must not duplicate the workflow.

Hermes needs no facade or symlink: when the project is trusted (`hermes skills trust`), it loads skills from `.agents/skills` directly. Do not add `.hermes/skills`.

| Agent | Native path |
|-------|-------------|
| Cursor | `.cursor/skills/<skill-name>/SKILL.md` (facade) |
| OpenCode | `.opencode/skill/<skill-name>/SKILL.md` (facade) |
| Grok | `.grok/skills/<skill-name>/SKILL.md` (facade) |
| Hermes | `.agents/skills/<skill-name>/` (trusted project; no extra wiring) |

### Facade template (Cursor / OpenCode / Grok)

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
- Do not use directory-wide symlinks for Cursor/OpenCode/Grok.
- Do not create `.hermes/skills` mirrors or symlinks; Hermes reads `.agents/skills` natively.

## Catalog

Listed in [`.agents/skills/README.md`](../.agents/skills/README.md).
