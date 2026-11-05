shader_type spatial;
// Boss area warning on the ground (D-18, design 04 "범위 공격은 1초 전에 바닥 표시(모양 + 색)").
// Owner: Lane D. The SHAPE is the information (circle / cone / line / ring); colour only adds to it.
// Fill: faint hatch inside, a solid front that sweeps from the origin to the edge as `progress` goes
// 0 -> 1 (when it reaches the edge the attack lands), light edge with a dark outer outline.
// Local plane: X right, Z forward (the node is rotated to the attack direction).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

uniform int shape = 0; // 0 circle, 1 cone, 2 line, 3 ring
uniform float radius = 3.0;
uniform float inner = 0.0;
uniform float half_angle = 0.6;
uniform float line_length = 6.0;
uniform float line_width = 1.6;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.851, 0.271, 0.231, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.96, 0.9, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.7);
uniform float opacity = 1.0;
uniform float flash = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 p = lp.xz;
	float len = length(p);
	float d;
	float f;
	if (shape == 1) {
		float a = atan(p.x, p.y);
		d = max(len - radius, (abs(a) - half_angle) * max(len, 0.001));
		d = max(d, -p.y - 0.001 * len);
		f = len / radius;
	} else if (shape == 2) {
		d = max(abs(p.x) - line_width * 0.5, max(-p.y, p.y - line_length));
		f = p.y / line_length;
	} else if (shape == 3) {
		d = max(len - radius, inner - len);
		f = (len - inner) / max(radius - inner, 0.001);
	} else {
		d = len - radius;
		f = len / radius;
	}
	float aa = max(fwidth(d), 0.01);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float edge = 1.0 - smoothstep(0.05, 0.05 + aa * 1.5, abs(d + 0.08));
	float outer = (1.0 - smoothstep(0.0, 0.07 + aa, d)) * smoothstep(-aa, 0.0, d);
	float hatch = step(0.55, fract((p.x + p.y) * 1.6));
	float filled = 1.0 - smoothstep(progress - 0.01, progress + 0.01, f);
	float front = (1.0 - smoothstep(0.0, 0.06, abs(f - progress))) * step(0.02, progress);
	float body = inside * (0.16 + 0.16 * hatch + 0.30 * filled + 0.5 * front);
	vec3 col = mix(color.rgb, edge_color.rgb, max(edge, front * 0.6));
	float a_edge = edge * 0.95;
	vec3 rgb = mix(outline_color.rgb, col, clamp(body + a_edge, 0.0, 1.0) / max(body + a_edge + outer * outline_color.a, 0.001));
	ALBEDO = rgb + vec3(flash);
	ALPHA = clamp(max(body, a_edge) + outer * outline_color.a + flash * inside, 0.0, 1.0) * opacity;
}
