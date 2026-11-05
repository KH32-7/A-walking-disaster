shader_type spatial;
// B: player vision light (design 02-field "시야"). Full-screen quad on the FieldCamera.
// Multiplies the scene: 1 inside the vision (lit_boost a bit above), out_shade outside.
render_mode unshaded, blend_mul, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec2 player_xz;
uniform vec2 facing_xz = vec2(0.0, -1.0);
uniform float circle_start = 1.0;
uniform float circle_end = 2.1;
uniform float cone_half_deg = 32.0;
uniform float cone_feather_deg = 13.0;
uniform float cone_fade_start = 11.5;
uniform float cone_range = 18.0;
uniform vec3 out_shade : source_color = vec3(0.70, 0.70, 0.78);
uniform float lit_boost = 1.32;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec2 d = world.xz - player_xz;
	float dist = length(d);
	float circle = 1.0 - smoothstep(circle_start, circle_end, dist);
	float ang = degrees(acos(clamp(dot(d / max(dist, 0.001), facing_xz), -1.0, 1.0)));
	float cone = (1.0 - smoothstep(cone_half_deg - cone_feather_deg, cone_half_deg + cone_feather_deg, ang))
		* (1.0 - smoothstep(cone_fade_start, cone_range, dist));
	float vis = 1.0 - (1.0 - circle) * (1.0 - cone); // soft union, no seam
	ALBEDO = mix(out_shade, vec3(lit_boost), vis);
}
