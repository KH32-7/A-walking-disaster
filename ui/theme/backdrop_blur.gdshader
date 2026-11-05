// Menu backdrop (UI_RULES §4 메뉴 스킨): blur the scene a little and darken it, so it shows through.
// Owner: Lane D. Used by MenuScreen. reduce: set blur_lod 0 for a plain dim.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 5.0) = 2.6;
uniform vec4 tint : source_color = vec4(0.04, 0.05, 0.08, 0.38);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}
