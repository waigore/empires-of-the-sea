shader_type canvas_item;
// Painted land relief. The wash texture is one texel per map tile, so the
// shader owns everything finer than a tile: a soft coast, a sand rim, a
// hillshade derived from the coarse height map, and a mottle evaluated at
// screen resolution. That is what keeps the terrain grainy when the camera
// zooms in, instead of magnifying a 22 px block (REQ-P1-03).

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec2 texel = vec2(0.0078125, 0.0119048);
uniform vec2 world_size = vec2(2816.0, 1848.0);
uniform vec4 sand_color : source_color = vec4(0.910, 0.863, 0.706, 1.0);
uniform float shade_strength = 2.6;
uniform float mottle_strength = 0.10;
uniform float sand_reach = 0.88;
uniform vec3 light_dir = vec3(-0.60, -0.74, 0.55);

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
	float coverage = base.a;
	float land = smoothstep(0.40, 0.62, coverage);
	float shallow = smoothstep(0.02, 0.34, coverage) * (1.0 - land);

	// Beach rim: terrain colour fades to sand as the coverage drops to the shore.
	vec3 color = mix(sand_color.rgb, base.rgb, smoothstep(0.50, sand_reach, coverage));

	// Hillshade from the coarse height field, light from the north-west.
	float h_l = texture(height_tex, UV - vec2(texel.x, 0.0)).r;
	float h_r = texture(height_tex, UV + vec2(texel.x, 0.0)).r;
	float h_u = texture(height_tex, UV - vec2(0.0, texel.y)).r;
	float h_d = texture(height_tex, UV + vec2(0.0, texel.y)).r;
	vec3 normal = normalize(vec3(-(h_r - h_l) * shade_strength, -(h_d - h_u) * shade_strength, 1.0));
	float lum = clamp(dot(normal, normalize(light_dir)), 0.0, 1.0);
	color *= 0.80 + 0.44 * lum;

	// Two mottle octaves: broad washes plus a fine tooth.
	vec2 p = UV * world_size / 34.0;
	float broad = fbm(p);
	float fine = vnoise(p * 4.3);
	color *= 1.0 + (broad - 0.5) * mottle_strength + (fine - 0.5) * mottle_strength * 0.55;

	// Engraved hachures: short strokes laid along the contours of a slope, so
	// hills keep a drawn texture instead of a smooth airbrushed gradient.
	vec2 grad = vec2(h_r - h_l, h_d - h_u);
	float slope = length(grad);
	if (slope > 0.0004) {
		vec2 along = normalize(vec2(-grad.y, grad.x));
		float stripe = sin(dot(UV * world_size, along) * 1.45);
		color *= 1.0 - smoothstep(0.66, 1.0, stripe) * smoothstep(0.002, 0.011, slope) * 0.17;
	}

	float alpha = max(land, shallow * 0.5);
	if (alpha < 0.004) {
		discard;
	}
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), alpha);
}
