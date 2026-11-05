shader_type canvas_item;
// Field map look (D-16): the top-down render, a little desaturated, with unexplored ground
// under a dark hatched fog. fog_tex: R = 1 where the player has been (FieldExplore cells).

uniform sampler2D fog_tex : filter_linear, hint_default_black;
uniform vec4 fog_color : source_color = vec4(0.10, 0.11, 0.15, 1.0);
uniform vec4 edge_color : source_color = vec4(0.91, 0.90, 0.88, 1.0);
uniform float desaturate = 0.3;
uniform float exposure = 0.8;
uniform float hatch_px = 12.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 mapped = mix(c.rgb, vec3(g), desaturate);
	mapped = pow(mapped, vec3(1.25)) * exposure;  // greybox ground is near white: pull it down
	float f = texture(fog_tex, UV).r;
	float seen = smoothstep(0.3, 0.7, f);
	float hatch = step(0.82, fract((FRAGCOORD.x + FRAGCOORD.y) / hatch_px));
	vec3 unseen = mix(fog_color.rgb, vec3(g * 0.35 + 0.08), 0.18) + hatch * 0.035;
	vec3 col = mix(unseen, mapped, seen);
	float edge = 1.0 - abs(f * 2.0 - 1.0);
	col = mix(col, edge_color.rgb, smoothstep(0.55, 1.0, edge) * 0.45);
	COLOR = vec4(col, 1.0);
}
