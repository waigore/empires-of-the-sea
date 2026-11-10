shader_type canvas_item;
// Broken, wobbling reflection under a hull. The texture supplied is already
// flipped, so v = 0 sits at the waterline and the mask can fade downwards. The
// cut-out stays a dark shape, softened to the painted scale.

uniform vec4 tint : source_color = vec4(0.42, 0.33, 0.28, 1.0);
uniform float strength = 0.22;
uniform float ripple = 0.014;
uniform float speed = 1.15;

void fragment() {
	vec2 uv = UV;
	uv.x += sin(uv.y * 24.0 + TIME * speed) * ripple * uv.y;
	uv.x += sin(uv.y * 7.0 - TIME * speed * 0.6) * ripple * 0.7 * uv.y;
	// Vertical smear: the hull's reflection drags down the ripples.
	float a = 0.0;
	a += textureLod(TEXTURE, uv, 3.6).a;
	a += textureLod(TEXTURE, uv + vec2(0.004, 0.012), 3.9).a;
	a += textureLod(TEXTURE, uv - vec2(0.006, 0.010), 4.2).a;
	a /= 3.0;
	float fade = (1.0 - smoothstep(0.05, 0.92, uv.y)) * smoothstep(0.01, 0.18, uv.y);
	float bands = 0.66 + 0.34 * sin(uv.y * 46.0 + TIME * 1.9);
	float side = smoothstep(0.0, 0.09, UV.x) * smoothstep(1.0, 0.91, UV.x);
	vec3 ink = vec3(0.035, 0.040, 0.055);
	COLOR = vec4(mix(ink, tint.rgb, 0.30), a * fade * bands * side * strength);
}
