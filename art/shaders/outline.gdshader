// Inverted-hull outline. Owner: Lane D (D-03). Use as `next_pass` of a toon material.
// Width is in screen pixels so it stays even at all three camera distances.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.12, 0.14, 0.17, 1.0);
uniform float outline_px : hint_range(0.0, 8.0) = 2.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 clip_n = mat3(PROJECTION_MATRIX) * (MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 offset = normalize(clip_n.xy) / VIEWPORT_SIZE * outline_px * 2.0 * clip.w;
	clip.xy += offset;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
