shader_type canvas_item;
// Painted land relief. `MapRelief` bakes the terrain colour, the beach, the
// shoal veil and a height field at six texels per tile; this shader owns
// everything finer than that: a hillshade with real sub-tile shape, engraved
// contour lines, the hachures of the engraver and a paper tooth. That is what
// keeps the ground grainy at every camera zoom instead of magnifying a block
// (REQ-P1-03).

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec2 texel = vec2(0.001953125, 0.002976190);
uniform vec2 world_size = vec2(2816.0, 1848.0);
uniform float shade_strength = 7.5;
uniform float contour_step = 20.0;
uniform float contour_ink = 0.20;
uniform float mottle_strength = 0.11;
uniform vec3 light_dir = vec3(-0.58, -0.72, 0.62);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * vnoise(p);
		p *= 2.07;
		amplitude *= 0.5;
	}
	return value * 1.0666;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float alpha = base.a;
	if (alpha < 0.004) {
		discard;
	}
	// The shoal veil is painted at partial alpha; only solid ground is shaded.
	float land = smoothstep(0.52, 0.94, alpha);

	float h_l = texture(height_tex, UV - vec2(texel.x, 0.0)).r;
	float h_r = texture(height_tex, UV + vec2(texel.x, 0.0)).r;
	float h_u = texture(height_tex, UV - vec2(0.0, texel.y)).r;
	float h_d = texture(height_tex, UV + vec2(0.0, texel.y)).r;
	vec2 grad = vec2(h_r - h_l, h_d - h_u);
	vec3 normal = normalize(vec3(-grad.x * shade_strength, -grad.y * shade_strength, 1.0));
	float lum = clamp(dot(normal, normalize(light_dir)), 0.0, 1.0);

	vec3 color = base.rgb * mix(1.0, 0.74 + 0.50 * lum, land);

	// Engraved contours: one line every `contour_step` of relief, only where the
	// ground actually rises, so plains keep a clean wash.
	float h = texture(height_tex, UV).r;
	float iso = abs(fract(h * contour_step + 0.5) - 0.5);
	float slope = length(grad);
	float contour = smoothstep(0.055, 0.0, iso) * smoothstep(0.006, 0.05, slope);
	color *= 1.0 - contour * contour_ink * land;

	// Two mottle octaves: broad washes plus a fine tooth, so no area of the
	// painting reads as a flat fill.
	vec2 p = UV * world_size / 30.0;
	float broad = fbm(p);
	float fine = vnoise(p * 4.7);
	color *= 1.0 + (broad - 0.5) * mottle_strength + (fine - 0.5) * mottle_strength * 0.62;

	// Hachures along the fall line: short strokes drawn across the slope, the way
	// an engraver deepens a scarp.
	if (slope > 0.004) {
		vec2 along = normalize(vec2(-grad.y, grad.x) + vec2(0.0001));
		float stripe = sin(dot(UV * world_size, along) * 1.55 + broad * 3.0);
		color *= 1.0 - smoothstep(0.62, 1.0, stripe) * smoothstep(0.007, 0.055, slope) * 0.20 * land;
	}

	// Paper tooth: the filament of the sheet under the wash.
	float tooth = hash(floor(UV * world_size * 1.7) + vec2(11.0, 7.0));
	color *= 1.0 + (tooth - 0.5) * 0.045;

	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), alpha);
}
