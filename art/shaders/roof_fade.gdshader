// Roof / wall fade for interiors in the quarter view. Owner: Lane D (D-03).
// Pixels between the camera and the player (inside `fade_radius` of the player on screen and
// above `fade_height`) dissolve with a dither pattern, so there is no sorting problem.
// `player_position` is set every frame by art/roof_fader.gd (no global uniform needed).
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform vec4 albedo : source_color = vec4(0.82, 0.80, 0.76, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 shade_color : source_color = vec4(0.42, 0.50, 0.58, 1.0);
uniform vec3 player_position = vec3(0.0);
uniform float fade_radius = 4.0;
uniform float fade_softness = 1.5;
uniform float fade_height = 1.2;   // metres above the player's feet where fading starts
uniform float fade_amount : hint_range(0.0, 1.0) = 1.0;  // 0 = off (player outdoors)
uniform float min_alpha : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int idx = x + y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = albedo.rgb * tex.rgb;
	vec2 d = v_world.xz - player_position.xz;
	float near = 1.0 - smoothstep(fade_radius, fade_radius + fade_softness, length(d));
	float above = step(player_position.y + fade_height, v_world.y);
	float keep = mix(1.0, min_alpha, near * above * fade_amount);
	if (keep < bayer4(FRAGCOORD.xy)) {
		discard;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.02, 0.08, ndl) * smoothstep(0.45, 0.55, ATTENUATION);
	vec3 shade = mix(shade_color.rgb, vec3(1.0), lit);
	DIFFUSE_LIGHT += ALBEDO * shade * LIGHT_COLOR / PI;
}
