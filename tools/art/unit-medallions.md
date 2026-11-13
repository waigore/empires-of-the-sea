# Unit medallions (fal.ai)

Every worker tier, worker, hull and land regiment shows a medallion of its own,
so a roster row reads at a glance and two types are never mistaken for one
another. The plates live in `assets/art/workers/`, `assets/art/civilians/`,
`assets/art/ships/` and `assets/art/regiments/`, and belong to the same family as
the shell icons (`tools/art/shell-icons.md`) and the tech plates
(`tools/art/tech-medallions.md`): thick beveled brass ring, dark espresso field,
top-left light, one object sculpted from metal.

## One frame, many objects

The frame is never generated. `assets/art/icons/ledger.png` is cleared to an
empty field — the field's own colour sampled per radius off the source, the
inner disc carried in with a gentle lift and a 1.2 px blur, feathered into the
ring's shadow — and kept as the base. Only the central object is generated,
then keyed and pasted onto that base, so all 51 plates share the exact ring,
field, vignette and lighting as the shell chrome.

## Worker tiers: one metal per rank

The four worker ranks are the one family that is not all brass. Each tier's
tools are struck in a different metal — wrought iron, copper, blued steel, gold
— so `LedgerWorkers` reads a rank by colour as well as silhouette (REQ-P1-08).
The metal is not left to the model: each tier's prompt names that metal in place
of polished brass, and the post pass then sets the plate's hue and saturation to
the tier's own target (`TIER_INK` in `tools/art/unit_medallions.py`) while
keeping only the render's light and shadow, so a drifting render can never hand
two ranks the same colour.

## Prompt

Reference: the blank medallion (`--blank` writes it). FLUX Kontext at 1024²,
then keyed down to 128².

> A single **[object]**, sculpted in polished brass with warm gold highlights
> and deep bronze shadows, lit from the upper left, rendered in exactly the same
> glossy metallic style as the gold ring of the reference medallion. Centred,
> one object only, few large shapes and a bold simple silhouette with minimal
> fine detail so it stays legible when small, no open book, no pages, no ring,
> no frame, no text, no lettering. Isolated on a solid pure magenta #FF00FF
> background.

Keep "no open book": the base is edited from `ledger.png`, so without that ban
the model keeps painting the open book behind the new object. Keep "few large
shapes": a 30 px roster row cannot carry fine rigging.

## Post

`tools/art/unit_medallions.py <source-dir> .` does all of it — one raw
`<id>.png` render per plate, named for the catalog id:

1. Key magenta dominance, not one hex: `alpha = 1 - (min(r,b) - g) / 0.12`,
   times a luma gate so the field's own darks do not key as brass.
2. Despill translucent texels toward the mean grey, crop to the alpha bounds.
3. Worker tiers only: recast the object onto its tier's metal — hue and
   saturation from `TIER_INK`, the render's value kept — before it is fitted.
4. Fit inside **0.62 × 128 px** (0.70 wide, 0.60 tall), add a soft shadow to the
   lower right, composite onto the blank medallion, save 128×128 RGBA.
5. Import with `mipmaps/generate=true`, lossless, matching the shell icons.

`--only <id>` rebuilds a single plate. Nothing else owns these files, so a
replacement render goes in the same way.

## Object prompts

One line per plate; the tail above follows `[object]`.

| Plate | `[object]` |
|-------|------------|
| **Worker tiers** | |
| `peasant` | a curved reaping sickle, blade sweeping left from a short turned wooden grip |
| `apprentice` | a copper water pail with a tall bail handle arched over its rim, body tapering to a flat base |
| `journeyman` | a blacksmith's anvil seen almost from the front, broad face toward the viewer, one horn turning left, a wide heavy foot |
| `master` | a ceremonial guild mace upright, a moulded grip and round pommel below a heavy orb head with three curling leaves |
| **Workers** | |
| `explorer` | an open compass crossed with a brass spyglass over a rolled sea chart |
| `engineer` | a mason's trowel crossed with a pair of dividers over a small stone arched bridge |
| `builder` | a carpenter's hammer crossed with a hand saw over a stack of squared planks |
| `spy` | a hooded cloaked figure seen from the chest up with the face hidden in shadow, one gloved finger raised to the lips and a sealed letter under the arm |
| `merchant` | a merchant's balance scale above a studded money chest with three coins spilling from its lid |
| `rail_builder` | a length of rail track on timber sleepers crossed with a railway sledgehammer |
| **Hulls** | |
| `carrack` | a broad three-masted carrack with a rounded high stern and square sails under full sail, side view |
| `fluyte` | a Dutch fluyt with a pear-shaped hull, a narrow deck and two square-rigged masts, side view |
| `sloop` | a small single-masted sloop with one gaff mainsail and a jib up front, side view |
| `trader` | a bluff-bowed merchant trader with a wide deep cargo hull, two masts and an open cargo hatch, side view |
| `galleon` | a galleon with a long low hull, a tall ornate stern castle and three masts under sail, side view |
| `indiaman` | a large East Indiaman with three masts under full sail, a high squared stern and a row of gunports along the hull, side view |
| `frigate` | a single-deck frigate with a row of gunports along a long sleek hull and three masts under full sail, side view |
| `raider` | a pirate xebec raider with a very long overhanging bow, one huge triangular lateen sail on a sharply raked mast, a low narrow hull with visible oar ports and a small black flag at the masthead, side view |
| `ship_of_the_line` | a two-decker ship of the line with two rows of gunports, a high stern and three masts under full sail, side view |
| `clipper` | a clipper with tall raked masts, a sharp hollow bow and every sail drawing, side view |
| `merchant_steamship` | a paddle steamship with one big side paddle wheel, a tall smokestack and two masts, side view |
| `ironclad` | an ironclad warship with a low armoured hull, one large round gun turret and a short funnel, side view |
| **Regiments** | |
| `peasant_levies` | a farmer's pitchfork crossed with a scythe above a bundle of wheat |
| `pikemen` | a bundle of three long pikes standing upright and bound together with a cord, the steel heads side by side |
| `arquebusiers` | an early matchlock arquebus with a forked rest and a powder flask beside it, side view |
| `bowmen` | a tall longbow with a leather quiver of arrows beside it, both upright |
| `squires` | a light cavalry sabre laid across a cavalry saddle with a hanging stirrup, side view |
| `knights` | a knight's great helm wearing a small pennant, with two lances crossed behind it |
| `culverin` | a long culverin cannon barrel on a two-wheeled field carriage, side view |
| `calivermen` | a light caliver musket crossed with a bandolier of powder charges, side view |
| `halberdiers` | a halberd with a broad polished axe blade crossed with a partizan, both upright |
| `musketeers` | a flintlock musket with a resting fork and a hanging powder horn, side view |
| `cossacks` | a curved sabre crossed with a short lance above a fur-lined cap |
| `lancers` | an upright lance with a swallow-tailed pennon crossed with a second lance, both polished |
| `harquebusiers` | a wheellock pistol crossed with a heavy cavalry sabre, side view |
| `horse_artillery` | a light cannon on a two-wheeled carriage hitched behind a limber and drawn by one horse in profile, side view, horse and gun both clearly separated |
| `royal_artillery` | a heavy brass cannon barrel on a large two-wheeled carriage with a pyramid of round shot beside it, side view |
| `skirmishers` | a hunting horn crossed with a short rifle |
| `regulars` | a drummer's side drum with two crossed drumsticks resting on its head |
| `grenadiers` | a tall grenadier's mitre cap with a round grenade above it |
| `hussars` | a hussar's fur busby with a tall plume above a curved sabre laid flat beneath it |
| `cuirassiers` | a steel cuirass breastplate with a heavy straight broadsword laid across it |
| `light_artillery` | a small light field gun with two spoked wheels and a rammer leaning against the barrel, side view |
| `heavy_artillery` | a massive siege mortar squatting on a heavy timber bed with three round shot beside it, side view |
| `sharpshooters` | a long rifle with a small telescopic sight mounted on top, side view |
| `rifle_infantry` | a rifle with a fixed bayonet laid across a soldier's knapsack, side view |
| `guards` | a tall bearskin guard's cap with a star badge and two swords crossed behind it |
| `scouts` | a small spyglass crossed with a folded map scroll |
| `carbine_cavalry` | a short cavalry carbine crossed with a rider's stirrup, side view |
| `field_artillery` | a field gun with two large spoked wheels and a long barrel, seen from the side with one round shot beside the wheel |
| `siege_guns` | a huge siege gun barrel mounted on a blocky timber bed with an iron rammer and two round shot, side view |

## Wiring

`CivilianArt`, `ShipArt`, `RegimentArt` and `WorkerTierArt` each load one texture
per catalog id (`assets/art/<family>/<id>.png`), cached, null when the plate is
missing so the row keeps its width and shows a gap. `WorkerTierArt.badge()` puts
the tier's plate in `LedgerWorkers` — 28 px on a desktop row, 32 px on a phone
row — and `LedgerWorkers.tier_marks()` exposes the rows' marks. `UnitMedallion` is
the fixed-size, mipmapped `TextureRect` the dossiers place: `FleetPanel` leads
its shipyard launch and break-up rows with it, `ArmyPanel` its roster and drill
yard. `test_ui_rules.gd` fails when a catalog type or a worker tier has no plate,
when two types resolve the same file, and when two tiers' marks measure as one
metal.
