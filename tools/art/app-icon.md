# App icon (fal.ai)

The project icon is a carrack under sail inside a gold medallion, painted in
the same warm period palette as the shell medallions: golden-hour sky, ivory
canvas, dark oak hull, crimson pennants, teal sea, thick beveled gold ring.

Master art: `assets/art/branding/app_icon.png` (1024 square). Generation prompt
(FLUX through `image_generate`, edited from `assets/art/tech/ship_of_line.png`
so the ring and lighting stay in the family):

> Square game app icon. A carrack under full sail, painted in warm golden-hour
> light: ivory canvas sails, dark oak hull with gold trim, crimson pennants,
> deep teal sea with whitecaps, golden sky glowing behind the ship. Thick
> polished gold circular frame, perfectly centred, ship fully inside the frame
> with clear margin. Simple clean rigging, no text, no letters, no watermark.
> Rich painterly Age of Sail game art, crisp readable silhouette.

## Derive the shipped sizes

```bash
python3 tools/art/app_icon.py
```

The tool cuts the medallion a few pixels inside its rim (dropping the pale
generator fringe) and writes it on a **transparent** field with a soft shadow,
so docks and home screens show through around the round emblem. Only the
Android adaptive *background* layer is a solid plate, because the platform
composites it behind the foreground:

| File | Use |
|------|-----|
| `icon.png` | `project.godot` `config/icon` (desktop window, exported exe) — transparent corners |
| `assets/art/branding/launcher_main_192.png` | legacy Android launcher icon — transparent corners |
| `.../launcher_background_432.png` | adaptive background (dark plate, platform requirement) |
| `.../launcher_foreground_432.png` | adaptive foreground, medallion in the 66% safe zone |
| `.../launcher_monochrome_432.png` | themed-icon glyph (white ring + carrack) |

Never paint an opaque plate behind the medallion on `icon.png` or
`launcher_main_192.png`; `tests/test_branding_rules.gd` fails if the corners
are not clear.

Replace the master, rerun the tool, and commit the regenerated files together.
Never hand-edit a derived layer.