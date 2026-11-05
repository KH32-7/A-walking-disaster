// Player outline (user request 2026-11-06: the grey-clad hero blends into the road). Inverted hull
// like art/shaders/outline.gdshader, but bright and drawn in the transparent pass (ALPHA) so it lands
// after the Look screen pass and stays crisp. Added as next_pass by Look (core/look/look.gd).
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 0.92, 0.7, 1.0);
uniform float outline_px : hint_range(0.0, 8.0) = 2.5;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 clip_n = mat3(PROJECTION_MATRIX) * (MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 offset = normalize(clip_n.xy) / VIEWPORT_SIZE * outline_px * 2.0 * clip.w;
	clip.xy += offset;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
