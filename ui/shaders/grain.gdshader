shader_type canvas_item;
render_mode blend_mul;
// Paper grain: a static, very light multiply so the whole screen reads as one
// printed sheet instead of layered UI.

uniform float strength = 0.10;
uniform float scale = 0.6;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float grain = hash(floor(FRAGCOORD.xy * scale));
	float fibre = hash(floor(FRAGCOORD.xy * scale * 0.25));
	float value = 1.0 - strength * (grain * 0.7 + fibre * 0.3);
	COLOR = vec4(vec3(value), 1.0);
}
