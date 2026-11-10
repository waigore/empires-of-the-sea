shader_type canvas_item;
// Animated light over the painted dusk plate: slow god-rays out of the setting
// sun, a drifting haze band along the waterline, and glitter riding the sun's
// path. Kept additive-thin so the oil painting underneath still reads as art,
// not a shader demo (REQ-P1-02, P1-04).

uniform vec2 design = vec2(1280.0, 720.0);
uniform float horizon_y = 410.0;
uniform vec2 sun_pos = vec2(960.0, 389.0);
uniform vec4 ray_color : source_color = vec4(1.0, 0.80, 0.52, 1.0);
uniform vec4 haze_color : source_color = vec4(0.96, 0.79, 0.64, 1.0);
uniform vec4 glint_color : source_color = vec4(1.0, 0.88, 0.63, 1.0);
uniform float ray_amount = 0.30;
uniform float haze_amount = 0.55;
uniform float glitter_amount = 0.55;

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
	for (int i = 0; i < 3; i++) {
		value += amplitude * vnoise(p);
		p *= 2.07;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 p = UV * design;
	float t = TIME;
	vec2 sp = p - sun_pos;
	float dist = length(sp);
	float above = step(p.y, horizon_y);

	// God rays: two crossed fans of light, slowly breathing, broken up so they
	// read as painted shafts rather than a graphic starburst.
	float angle = atan(sp.y, sp.x);
	float fan = 0.5 + 0.5 * sin(angle * 26.0 + t * 0.06);
	fan *= 0.5 + 0.5 * sin(angle * 11.0 - t * 0.045 + 1.7);
	fan *= 0.55 + 0.45 * fbm(vec2(angle * 2.4, t * 0.015));
	float rays = pow(fan, 3.0) * exp(-dist / 430.0) * above * ray_amount;

	// Haze hugging the waterline, drifting with the breeze.
	float band = exp(-abs(p.y - horizon_y) / 58.0);
	float haze_noise = fbm(vec2(p.x * 0.0022 + t * 0.010, p.y * 0.0055));
	float haze = smoothstep(0.34, 0.82, haze_noise) * band * haze_amount;

	// Soft bloom that dissolves the painted sun's hard edge into the sky.
	float bloom_sky = smoothstep(horizon_y + 90.0, horizon_y - 130.0, p.y);
	float bloom = exp(-dist / 150.0) * bloom_sky * 0.26;

	// Glitter: only in the sun's widening path, scrolling towards the viewer.
	float depth = max(p.y - horizon_y, 0.0);
	float path_width = 24.0 + depth * 0.78;
	float path_ratio = (p.x - sun_pos.x) / path_width;
	float column = exp(-path_ratio * path_ratio);
	float q = 1.0 / (depth + 9.0);
	float sparkle = fbm(vec2((p.x - sun_pos.x) * q * 19.0, q * 145.0 - t * 2.1));
	float glints = smoothstep(0.60, 0.92, sparkle) * column
		* smoothstep(0.0, 14.0, depth) * glitter_amount;

	float total = clamp(rays + haze + glints + bloom, 0.0, 0.92);
	vec3 rgb = (ray_color.rgb * rays + haze_color.rgb * haze
		+ glint_color.rgb * glints + glint_color.rgb * bloom)
		/ max(rays + haze + glints + bloom, 0.0001);
	COLOR = vec4(rgb, total);
}
