// Enemy outline, pass 2 of 2 (field monsters). Inverted hull like outline.gdshader, but only where
// enemy_mask.gdshader did not mark the stencil: a red ring outside the dark toon line. Width is in
// screen pixels (outline_px counts from the mesh edge, so it must be larger than the mask's grow_px).
// Red means enemy and nothing else.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;
stencil_mode read, compare_not_equal, 64;

uniform vec4 outline_color : source_color = vec4(0.88, 0.23, 0.18, 1.0);
uniform float outline_px : hint_range(0.0, 12.0) = 4.5;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 clip_n = mat3(PROJECTION_MATRIX) * (MODELVIEW_NORMAL_MATRIX * NORMAL);
	clip.xy += normalize(clip_n.xy) / VIEWPORT_SIZE * outline_px * 2.0 * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = 1.0;  // transparent pipeline, so it runs after every mask pass
}
