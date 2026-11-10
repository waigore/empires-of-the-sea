shader_type canvas_item;
// Soft oval scrim behind the title column. Keeps gold type legible over the
// bright painted water without flattening the corners of the artwork.

uniform vec4 tint : source_color = vec4(0.014, 0.017, 0.028, 0.62);
uniform float spread = 0.58;

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.x *= 1.35;
	float d = length(p);
	float a = (1.0 - smoothstep(0.10, spread, d)) * tint.a;
	COLOR = vec4(tint.rgb, a);
}
