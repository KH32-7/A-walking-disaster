// Menu backdrop (UI_RULES §4 메뉴 스킨): blur the scene a little and darken it, so it shows through.
// Owner: Lane D. Used by MenuScreen. reduce: set blur_lod 0 for a plain dim.
// saturation < 1 greys the scene out (건설 화면: 컬트 오브 더 램처럼 월드를 흑백으로 가라앉힘).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 5.0) = 2.6;
uniform vec4 tint : source_color = vec4(0.04, 0.05, 0.08, 0.38);
uniform float saturation : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(g), c, saturation);
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}
