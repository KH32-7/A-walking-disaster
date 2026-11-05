shader_type canvas_item;
// Full-screen colour-blind filter (D-15). Owner: Lane D. Driven by ColorFilterLayer from
// Settings.color_filter: 1 protanopia, 2 deuteranopia, 3 tritanopia (0 = layer hidden).
// Daltonisation: simulate how the colour looks with the deficiency (Machado et al. 2009,
// severity 1.0, linear RGB), take what is lost and push it into channels that are still seen.
// Shapes and labels stay the main cue (UI_RULES §1.6); this only makes colour easier to tell.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int mode = 0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

vec3 to_linear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }
vec3 to_srgb(vec3 c) { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }

vec3 mul(vec3 r0, vec3 r1, vec3 r2, vec3 c) { return vec3(dot(r0, c), dot(r1, c), dot(r2, c)); }

vec3 simulate(vec3 c, int m) {
	if (m == 1) {
		return mul(vec3(0.152286, 1.052583, -0.204868), vec3(0.114503, 0.786281, 0.099216),
			vec3(-0.003882, -0.048116, 1.051998), c);
	}
	if (m == 2) {
		return mul(vec3(0.367322, 0.860646, -0.227968), vec3(0.280085, 0.672501, 0.047413),
			vec3(-0.011820, 0.042940, 0.968881), c);
	}
	return mul(vec3(1.255528, -0.076749, -0.178779), vec3(-0.078411, 0.930809, 0.147602),
		vec3(0.004733, 0.691367, 0.303900), c);
}

vec3 shift(vec3 err, int m) {
	if (m == 3) {
		// blue-yellow loss: move it into red and green
		return mul(vec3(1.0, 0.0, 0.7), vec3(0.0, 1.0, 0.7), vec3(0.0, 0.0, 0.0), err);
	}
	// red-green loss: move it into green and blue
	return mul(vec3(0.0, 0.0, 0.0), vec3(0.7, 1.0, 0.0), vec3(0.7, 0.0, 1.0), err);
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	vec3 lin = to_linear(src);
	vec3 err = lin - simulate(lin, mode);
	vec3 corrected = clamp(lin + shift(err, mode), vec3(0.0), vec3(1.0));
	COLOR = vec4(mix(src, to_srgb(corrected), mode == 0 ? 0.0 : strength), 1.0);
}
