---
name: map-lens
description: |-
  Add or change a map lens/overlay in Empires of the Sea: a pure projection in
  scripts/rules, a Node2D layer above the fog, a HUD toggle + survey key, and
  desktop/mobile tests. Use when adding a map mode (survey, resources,
  diplomacy, terrain), changing scripts/map/resource_lens.gd, or when a player
  asks to see map information at a glance. Not for side dossiers or ledgers.

  Examples:
    - "show resources on the map" → survey lens via ResourceSurvey + ResourceLens
    - "add a terrain/diplomacy lens" → reuse the same projection → layer → key shape
    - "the lens plaques overlap / fps drops" → packing, repaint and anchor rules
---

# Map lens (facade)

Canonical instructions: [`.agents/skills/map-lens/SKILL.md`](../../../.agents/skills/map-lens/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
