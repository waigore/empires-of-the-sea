shader_type canvas_item;
// Engraved antique-atlas sea: drifting swell, travelling crests, twinkling
// glints and a fine ripple hatch. Sits behind the land wash so only open water
// shows. Waves are world-anchored (uv scaled by world_size) so enlarging the
// backdrop does not change their density.

uniform vec4 deep_color : source_color = vec4(0.278, 0.420, 0.451, 1.0);
uniform vec4 mid_color : source_color = vec4(0.443, 0.576, 0.580, 1.0);
uniform vec4 pale_color : source_color = vec4(0.663, 0.769, 0.749, 1.0);
uniform float wave_scale = 6.5;
uniform float speed = 0.060;
uniform float hatch_strength = 0.11;
uniform float crest_strength = 0.85;
uniform float glint_strength = 0.10;
uniform vec2 world_size = vec2(2816.0, 1848.0);
uniform vec2 drift = vec2(0.72, 0.24);

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

	float swell = fbm(uv * wave_scale + drift * t * 2.0);
	float ripple = fbm(uv * wave_scale * 2.3 - drift * t * 2.8);

	vec3 color = mix(deep_color.rgb, mid_color.rgb, smoothstep(0.30, 0.72, swell));
	color = mix(color, pale_color.rgb, smoothstep(0.52, 0.95, ripple) * 0.38);

	// Travelling crests: thin pale lines rolling on the swell, so the sea reads
	// as moving water rather than a drifting noise field.
	float axis = dot(uv, vec2(0.80, 0.60)) * 26.0 - t * 34.0;
	float crest = sin(axis + swell * 7.0 + uv.x * 2.0);
	crest = smoothstep(0.90, 1.0, crest) * smoothstep(0.34, 0.72, swell);
	color += vec3(0.085, 0.095, 0.088) * crest * crest_strength;

	// Slanted hatch of the engraver, plus a finer counter-hatch: at fit zoom the
	// open water has to carry linework of its own, not just a colour field.
	vec2 wp = UV * world_size;
	float band = sin((uv.y * 26.0 + swell * 4.0 + t * 6.0) * 3.14159);
	color += vec3(0.05, 0.06, 0.06) * smoothstep(0.86, 1.0, band) * hatch_strength * 20.0;
	float fine = sin(wp.y * 0.115 + wp.x * 0.034 + swell * 5.0 + t * 2.0);
	color += vec3(0.045, 0.055, 0.055) * smoothstep(0.88, 1.0, fine) * hatch_strength * 4.0;

	// Glints only where the ripple crowns, so the sparkle keeps a shape.
	float cell = hash(floor(uv * 240.0) + vec2(floor(t * 26.0)));
	float glint = step(0.9975, cell) * smoothstep(0.55, 0.92, ripple);
	color += vec3(0.13, 0.135, 0.125) * glint * glint_strength * 10.0;

	color += (hash(UV * 900.0) - 0.5) * 0.018;
	COLOR = vec4(color, 1.0);
}
