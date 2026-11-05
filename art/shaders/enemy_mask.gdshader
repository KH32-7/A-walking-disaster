// Enemy outline, pass 1 of 2 (field monsters). Draws nothing visible: marks the monster's silhouette,
// grown by grow_px so it also covers the dark toon outline (outline.gdshader, 2 px), in the stencil
// buffer. No depth test, so every pixel of the shape is marked even where the dark line sits in front
// of the body. Pass 2 (enemy_outline.gdshader) draws only outside the mark: the outer edge, never the
// creases inside the body. Must render before every pass 2 (lower render_priority, both transparent).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;
stencil_mode write, compare_always, 64;

uniform float grow_px : hint_range(0.0, 8.0) = 2.5;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 clip_n = mat3(PROJECTION_MATRIX) * (MODELVIEW_NORMAL_MATRIX * NORMAL);
	clip.xy += normalize(clip_n.xy) / VIEWPORT_SIZE * grow_px * 2.0 * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
