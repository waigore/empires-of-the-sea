# Shell medallion icons (fal.ai)

The cartouche's four status medallions are generated with FLUX through
`fal.ai` (`image_generate`), edited from `assets/art/icons/ledger.png` so the
ring, dark field, top-left lighting and brass palette stay identical. Keep the
prompts here so a replacement icon stays in the same family.

All four used this base edit:

> Edit this medallion: keep the thick beveled brass ring, dark espresso circular
> field, top-left lighting and exact rendering style unchanged. Replace ONLY the
> central open book with **[object]**, sculpted in polished brass. No book, no
> pages, no text. Isolated on a solid pure magenta background.

| Icon | `[object]` |
|------|------------|
| `coin.png` | a neat stack of three thick gold coins, the top coin face-on with a simple raised cross mint mark |
| `ship.png` | a gold three-masted caravel under full sail, side view |
| `people.png` | two simple gold busts side by side, rounded head-and-shoulders silhouettes, the left figure slightly taller, no props, no faces |
| `swords.png` | two crossed gold rapiers, blades up, detailed hilts |
| `gazette.png` | a folded imperial news-sheet, front-on and slightly angled: one broadsheet with a crisp horizontal crease and a narrow empty masthead band across the top, no text, no print columns |

## Post

1. Key magenta dominance, not one hex: `alpha = 1 - (min(r,b) - g) / 0.10`,
   clamped; this catches the backdrop's lighting variation.
2. Despill edge texels toward `g`, then set fully transparent texels to a
   neutral dark brown so Lanczos does not blend magenta back into the rim.
3. Crop square to the opaque bounds with a 6% margin, resize to **128×128**
   with Lanczos, despill once more.
4. Import with `mipmaps/generate=true`, lossless compression, matching the
   existing shell medallions.

## Wiring

`ChromeIcons.texture(name)` loads the PNG; `TopBar` shows it in a `TextureRect`
named `Medallion` at 22 points. Tests assert every door and status plaque keeps
a medallion (`REQ-P1-08`).

## Regiment condition icon (chevron)

One small braid icon for the combat plate and the army dossier
(DR-20261110-19), cut from a magenta sheet with the icon-set recipe above:

> A single gold embroidered sergeant's chevron pointing upward on a flat pure
> magenta #FF00FF background, bold thick V-shaped gold braid, no text, no
> shadows, strong silhouette legible at 16–24 px.

`chevron.png` marks a regiment's experience in the Quick Battle plate, its
condition rail, the aftermath copy and the army dossier row. It is 128 px RGBA
with `mipmaps/generate=true`. `QuickBattleField`/`QuickBattleRail` draw the
chevron, `ArmyPanel` shows it beside the chevron count; no build script owns
these files, so a replacement goes in `assets/art/icons/` by hand (same family
as the shell medallions).

## Silenced battery icon (auto-resolve)

One medallion for the land toast when an auto-resolved siege silences a fort's
guns (DR-20261110-22). Base edit from `ledger.png`, same ring and lighting:

> Replace ONLY the central open book with a single brass cannon barrel broken at
> the breech, tilted slightly upward, with a short dark curl of smoke rising
> from the break, sculpted in polished brass. No book, no pages, no text.
> Isolated on a solid pure magenta #FF00FF background.

`silenced_gun.png` is 128 px RGBA with `mipmaps/generate=true`.
`BattleReport.icon_of` names it; `GameHud.toast` draws it at 26 points on a
crimson plate. No build script owns it, so a replacement goes in
`assets/art/icons/` by hand.
