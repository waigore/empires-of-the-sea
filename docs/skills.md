# Project skills

Canonical skill bodies live under [`.agents/skills/`](../.agents/skills/) (one folder per skill). That tree is the only source of truth.

## Native wiring

When a project skill is created or renamed, wire Cursor, OpenCode, Grok, and Hermes. Facades carry the same `name` / `description` frontmatter and point at the canonical body — they must not duplicate the workflow.

| Agent | Native path |
|-------|-------------|
| Cursor | `.cursor/skills/<skill-name>/SKILL.md` (facade) |
| OpenCode | `.opencode/skill/<skill-name>/SKILL.md` (facade) |
| Grok | `.grok/skills/<skill-name>/SKILL.md` (facade) |
| Hermes | `.hermes/skills/<skill-name>` → symlink to `../../.agents/skills/<skill-name>` |

Hermes indexes both `.hermes/skills` and `.agents/skills` when the project is trusted. A thin markdown facade would collide with the canonical body (ambiguous name). Use a **per-skill directory symlink** so both paths resolve to one skill.

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
- Do not use directory-wide symlinks for Cursor/OpenCode/Grok; Hermes uses per-skill symlinks only.

## Catalog

Listed in [`.agents/skills/README.md`](../.agents/skills/README.md).
