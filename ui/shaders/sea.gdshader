shader_type canvas_item;
// Engraved antique-atlas sea: slow drifting swell, pale shoals and fine
// hatch lines. Sits behind the land wash so only open water shows.

uniform vec4 deep_color : source_color = vec4(0.30, 0.44, 0.47, 1.0);
uniform vec4 mid_color : source_color = vec4(0.47, 0.60, 0.60, 1.0);
uniform vec4 pale_color : source_color = vec4(0.66, 0.77, 0.75, 1.0);
uniform float wave_scale = 7.0;
uniform float speed = 0.035;
uniform float hatch_strength = 0.05;
uniform vec2 world_size = vec2(2816.0, 1848.0);

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
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 uv = (UV * world_size) / 1850.0;
	float t = TIME * speed;
	float swell = fbm(uv * wave_scale + vec2(t * 2.0, t));
	float ripple = fbm(uv * wave_scale * 2.2 - vec2(t * 1.4, t * 0.7));

	vec3 color = mix(deep_color.rgb, mid_color.rgb, smoothstep(0.30, 0.72, swell));
	color = mix(color, pale_color.rgb, smoothstep(0.55, 0.95, ripple) * 0.35);

	float band = sin((uv.y * 26.0 + swell * 4.0 + t * 6.0) * 3.14159);
	color += vec3(0.05, 0.06, 0.06) * smoothstep(0.86, 1.0, band) * hatch_strength * 20.0;

	color += (hash(UV * 900.0) - 0.5) * 0.02;
	COLOR = vec4(color, 1.0);
}
