shader_type canvas_item;
// Makes a hard vector cut-out belong to the painting: mip-blurred edges that
// match the painted scale, a cool-to-warm body that follows the setting sun,
// atmospheric haze towards the mastheads, and a warm rim where the light
// catches the silhouette.

uniform vec4 ink_cool : source_color = vec4(0.030, 0.037, 0.058, 1.0);
uniform vec4 ink_warm : source_color = vec4(0.110, 0.078, 0.052, 1.0);
uniform vec4 haze : source_color = vec4(0.62, 0.44, 0.33, 1.0);
uniform vec4 rim : source_color = vec4(1.0, 0.68, 0.38, 1.0);
uniform float haze_mix = 0.34;
uniform float rim_strength = 0.78;
uniform float soft_lod = 2.9;
// 0.0 for a hull drawn bow-right, 1.0 when the sprite is mirrored.
uniform float flip = 0.0;

void fragment() {
	vec4 soft = textureLod(TEXTURE, UV, soft_lod);
	float a = soft.a;
	float sun_side = mix(1.0, -1.0, flip);
	float across = mix(UV.x, 1.0 - UV.x, flip);
	vec2 px = TEXTURE_PIXEL_SIZE * 10.0;
	float lit_edge = textureLod(TEXTURE, UV + vec2(px.x * sun_side, 0.0), soft_lod).a;
	float top_edge = textureLod(TEXTURE, UV - vec2(0.0, px.y), soft_lod).a;
	float edge = clamp((a - lit_edge) * 1.5 + (a - top_edge) * 0.4, 0.0, 1.0);

	vec3 body = mix(ink_cool.rgb, ink_warm.rgb, smoothstep(0.10, 0.88, across));
	body = mix(body, haze.rgb, haze_mix * (0.45 + 0.55 * (1.0 - UV.y)));
	body = mix(body, rim.rgb, edge * rim_strength);
	COLOR = vec4(body, a);
}
