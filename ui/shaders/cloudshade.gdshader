shader_type canvas_item;
render_mode blend_mul;
// Drifting cloud shadow across the whole theatre. One soft multiply band that
// travels over land and sea at its own pace, so a static map never looks frozen
// while costing a single full-screen pass (REQ-P1-04).

uniform float strength = 0.13;
uniform float speed = 0.012;
uniform float scale = 1.55;
uniform vec2 world_size = vec2(2816.0, 1848.0);
uniform vec2 drift = vec2(1.0, 0.34);

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
		p *= 2.05;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 p = (UV * world_size) / 900.0;
	float t = TIME * speed;
	float cloud = fbm(p * scale + drift * t * 6.0);
	float shade = smoothstep(0.38, 0.86, cloud) * strength;
	COLOR = vec4(vec3(1.0 - shade), 1.0);
}
