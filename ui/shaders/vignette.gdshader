shader_type canvas_item;
// Warm corner falloff that focuses the eye on the map centre.

uniform vec4 tint : source_color = vec4(0.08, 0.05, 0.02, 1.0);
uniform float strength = 0.42;
uniform float inner = 0.34;
uniform float outer = 0.95;

void fragment() {
	vec2 uv = UV - 0.5;
	float distance = length(uv * vec2(1.0, 1.18));
	float amount = smoothstep(inner, outer, distance);
	COLOR = vec4(tint.rgb, amount * strength);
}
