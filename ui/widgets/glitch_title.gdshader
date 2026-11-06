shader_type canvas_item;
// Broken-signal title (GlitchTitle). Uses only the text's alpha; colours come from uniforms.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform vec4 text_color : source_color = vec4(1.0);
uniform vec4 ghost_a : source_color = vec4(0.34, 0.76, 0.79, 1.0);
uniform vec4 ghost_b : source_color = vec4(0.96, 0.78, 0.27, 1.0);
uniform float slices = 16.0;

varying vec4 v_mod;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 over(vec4 top, vec4 bot) {
	float a = top.a + bot.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + bot.rgb * bot.a * (1.0 - top.a)) / max(a, 0.0001);
	return vec4(rgb, a);
}

void vertex() {
	v_mod = COLOR;  // keep the node's modulate (fade in)
}

void fragment() {
	vec2 uv = UV;
	float row = floor(uv.y * slices);
	// Some slices jump sideways; more of them the stronger the glitch.
	float torn = step(1.0 - intensity * 0.7, hash(vec2(row, seed)));
	uv.x += torn * (hash(vec2(row, seed + 7.0)) - 0.5) * 0.10 * intensity;
	// Thin rows drop out like a weak signal.
	float drop = step(hash(vec2(floor(uv.y * 120.0), seed + 3.0)), intensity * 0.2);
	float split = 0.014 * intensity;
	float a_main = texture(TEXTURE, uv).a * (1.0 - drop * 0.8);
	float a_l = texture(TEXTURE, uv - vec2(split, 0.0)).a;
	float a_r = texture(TEXTURE, uv + vec2(split * 0.6, 0.0)).a;
	float g = min(intensity * 1.5, 1.0) * 0.85;
	vec4 ghosts = over(vec4(ghost_b.rgb, a_r * g), vec4(ghost_a.rgb, a_l * g));
	COLOR = over(vec4(text_color.rgb, a_main), ghosts);
	COLOR.a *= v_mod.a;
}
