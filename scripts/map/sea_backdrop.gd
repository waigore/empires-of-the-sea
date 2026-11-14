class_name SeaBackdrop
extends RefCounted
## The sea plane behind a world chart: its open-water margin, its rect and the
## drifting-water shader's `world_size`. A chart mount asks for the fit instead
## of knowing the plane's internals (REQ-P3-01).

## Open water painted around the chart, in world units.
const MARGIN: float = 1400.0


## Sizes `backdrop` to the chart plus `margin` of sea on every side and mirrors
## that size onto the drifting-water shader.
static func fit(backdrop: ColorRect, map_size: Vector2, margin: float = MARGIN) -> void:
	if backdrop == null:
		return
	backdrop.position = Vector2(-margin, -margin)
	backdrop.size = map_size + Vector2(margin, margin) * 2.0
	var shader: ShaderMaterial = backdrop.material as ShaderMaterial
	if shader != null:
		shader.set_shader_parameter("world_size", backdrop.size)
