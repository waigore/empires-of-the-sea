shader_type canvas_item;
// Softens the tile-resolution fog mask so the frontier reads as a wash of
// unexplored paper, and adds a faint engraved hatch over unknown ground.

uniform vec2 texel = vec2(0.0078125, 0.011904762);
uniform float softness = 1.7;
uniform vec2 map_tiles = vec2(128.0, 84.0);
uniform float tile_size = 22.0;

void fragment() {
	vec4 sum = vec4(0.0);
	float total = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y)) * texel * softness;
			float weight = (x == 0 && y == 0) ? 2.0 : 1.0;
			sum += texture(TEXTURE, UV + offset) * weight;
			total += weight;
		}
	}
	vec4 color = sum / total;

	float world = (UV.x * map_tiles.x + UV.y * map_tiles.y) * tile_size;
	float hatch = smoothstep(0.90, 1.0, fract(world / 34.0));
	float coverage = clamp(color.a * 1.3, 0.0, 1.0);
	color.rgb *= 1.0 - hatch * 0.07 * coverage;
	COLOR = color;
}
