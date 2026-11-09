# Menu backdrop assets (fal.ai)

The title screen plate and carrack cut-outs are generated with FLUX through
`fal.ai` (`image_generate`), then upscaled with `fal-ai/esrgan` (2x,
`RealESRGAN_x4plus`) and prepared with Pillow. Keep the prompts here so a
replacement plate stays in the same period and composition.

## Plate — `dusk_harbour.png` (2048×1152)

> Ultra-wide cinematic oil painting on aged canvas: a Spanish colonial
> Caribbean harbour at sunset, circa 1600. On the far left, a low headland with
> a stone star-fort, bastions, a small whitewashed church tower, red-tiled
> colonial houses, tall coconut palms and a wooden quay with moored longboats.
> Open calm bay fills the centre and right, with a huge low sun on the right
> horizon casting a shimmering golden path across the water. Thin luminous
> clouds, deep indigo sky above, warm rose and ochre near the horizon. Painted
> in the manner of 17th-century Dutch and Spanish maritime old masters:
> dramatic chiaroscuro, visible brushwork, glazed shadows, muted burnt sienna,
> ochre, deep indigo and a touch of verdigris. Historically accurate 1600s
> galleon-era architecture, no modern elements, no large foreground ships, no
> text, no watermark, no frame. Keep the centre of the image calm and
> uncluttered for a title screen.

Post: remove the painter's signature (bottom-right) with a feathered water
patch, screen-blend a blurred copy into a radial mask around the sun for bloom,
then blend a lightly blurred disc region to soften the sun's hard edge.

## Carrack — `carrack.png` / `carrack_reflection.png`

> Pure black silhouette of an early 16th-century Portuguese carrack (nau) in
> full sail, circa 1520, exact side profile facing right. Four masts:
> square-rigged foremast and mainmast with billowing courses and topsails, a
> lateen mizzen and bonaventure mizzen, a long bowsprit with a spritsail. Very
> high rounded forecastle and towering sterncastle with small windows,
> pronounced tumblehome hull, short beakhead. Small streaming pennants. Fine
> rigging lines. Flat solid black fill, crisp clean edges, no grey tones, no
> shading, no highlights, pure white background, no water, no waves, no text,
> no border, isolated single object.

Post: luminance key (`alpha = (1 - luma)^0.88`) into a warm-ink RGBA cut-out,
crop to the alpha bounds, save a vertically flipped copy for the water
reflection.

## Import

Mipmaps on for all three textures (`mipmaps/generate=true`), lossless
compression; `MenuShip` uses `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` and samples
blurred LODs so the cut-out matches the painting's brush scale.

## Wiring

`MenuBackdrop` cover-fits a 1280×720 stage to any window, drifts and breathes
the plate, and layers `menu_atmosphere` (rays, haze, glitter),
`cloudshade` (drifting cloud shadow), `MenuShip` (bob, reflection, lanterns),
`MenuLife` (gulls, embers), `menu_scrim`, vignette and grain.
