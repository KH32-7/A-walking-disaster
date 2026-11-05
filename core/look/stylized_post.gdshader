// Full-screen stylized look (prototype, user request 2026-11-06): painterly filter that flattens
// photo-like texture detail, depth/normal outlines, and a simple color grade. Drawn by a quad that
// Look (core/look/look.gd) keeps in front of the current Camera3D. Numbers: LookTuning
// (data/look/look_tuning.tres), live-tunable with the \ debug panel.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

// Painterly (Kuwahara) radius in pixels, 0 = off. Smooths texture noise into flat patches, keeps edges.
uniform int paint_radius : hint_range(0, 6) = 3;
// Pixels between painterly samples: wider strokes for the same cost (bilinear fills the gaps).
uniform float paint_step : hint_range(1.0, 4.0) = 2.5;
uniform float outline_px : hint_range(0.0, 4.0) = 1.5;
uniform float outline_depth : hint_range(0.0, 1.0) = 0.12; // relative depth jump that counts as an edge
uniform float outline_normal : hint_range(0.0, 2.0) = 0.7; // 1 - dot(normals) that counts as an edge
uniform float outline_strength : hint_range(0.0, 1.0) = 0.8;
uniform vec4 outline_color : source_color = vec4(0.08, 0.09, 0.11, 1.0);
uniform float outline_fade_far = 60.0; // no outlines past this view distance (m)
uniform float saturation : hint_range(0.0, 2.0) = 1.2;
uniform float contrast : hint_range(0.5, 2.0) = 1.1;
uniform float brightness : hint_range(0.5, 2.0) = 1.3;
// Light bands: lightness snapped to this many steps, 0 = off.
uniform int bands : hint_range(0, 8) = 0;
uniform float band_mix : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}

vec3 kuwahara(vec2 uv, vec2 px) {
	vec3 m0 = vec3(0.0); vec3 m1 = vec3(0.0); vec3 m2 = vec3(0.0); vec3 m3 = vec3(0.0);
	vec3 s0 = vec3(0.0); vec3 s1 = vec3(0.0); vec3 s2 = vec3(0.0); vec3 s3 = vec3(0.0);
	int r = paint_radius;
	for (int j = -r; j <= r; j++) {
		for (int i = -r; i <= r; i++) {
			vec3 c = texture(screen_tex, uv + vec2(float(i), float(j)) * px).rgb;
			vec3 c2 = c * c;
			if (i <= 0 && j <= 0) { m0 += c; s0 += c2; }
			if (i >= 0 && j <= 0) { m1 += c; s1 += c2; }
			if (i <= 0 && j >= 0) { m2 += c; s2 += c2; }
			if (i >= 0 && j >= 0) { m3 += c; s3 += c2; }
		}
	}
	float n = float((r + 1) * (r + 1));
	m0 /= n; m1 /= n; m2 /= n; m3 /= n;
	vec3 v0 = abs(s0 / n - m0 * m0);
	vec3 v1 = abs(s1 / n - m1 * m1);
	vec3 v2 = abs(s2 / n - m2 * m2);
	vec3 v3 = abs(s3 / n - m3 * m3);
	float best = v0.r + v0.g + v0.b;
	vec3 col = m0;
	float t = v1.r + v1.g + v1.b;
	if (t < best) { best = t; col = m1; }
	t = v2.r + v2.g + v2.b;
	if (t < best) { best = t; col = m2; }
	t = v3.r + v3.g + v3.b;
	if (t < best) { col = m3; }
	return col;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 col = paint_radius > 0 ? kuwahara(uv, px * paint_step) : texture(screen_tex, uv).rgb;

	// Grade.
	col *= brightness;
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(l), col, saturation);
	col = max((col - 0.18) * contrast + 0.18, vec3(0.0));
	if (bands > 0) {
		l = dot(col, vec3(0.2126, 0.7152, 0.0722));
		float lb = (floor(l * float(bands)) + 0.5) / float(bands);
		col = mix(col, col * (lb / max(l, 0.0001)), band_mix);
	}

	// Outlines from depth and normal jumps.
	float d = view_depth(uv, INV_PROJECTION_MATRIX);
	if (outline_px > 0.0 && outline_strength > 0.0 && d < outline_fade_far) {
		vec2 o = px * outline_px;
		vec3 n = view_normal(uv);
		float edge = 0.0;
		vec2 offs[4] = vec2[](vec2(o.x, 0.0), vec2(-o.x, 0.0), vec2(0.0, o.y), vec2(0.0, -o.y));
		for (int k = 0; k < 4; k++) {
			float dn = view_depth(uv + offs[k], INV_PROJECTION_MATRIX);
			// Only the near side of a jump draws, so lines stay one side thick.
			if ((dn - d) > outline_depth * d) edge = 1.0;
			if (1.0 - dot(n, view_normal(uv + offs[k])) > outline_normal) edge = 1.0;
		}
		float fade = 1.0 - smoothstep(outline_fade_far * 0.7, outline_fade_far, d);
		col = mix(col, outline_color.rgb, edge * outline_strength * fade);
	}
	ALBEDO = col;
}
