// Flood water (D-10). Owner: Lane D. Teal toon water: two-tone bands from a scrolling noise,
// small sparkles, soft edge foam where the surface meets geometry (depth difference).
// Design 16 "팔레트": 청록 수면. reduce_flash -> sparkle_amount 0 from code.
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_back, depth_draw_opaque;

uniform vec4 shallow : source_color = vec4(0.27, 0.55, 0.56, 1.0);
uniform vec4 deep : source_color = vec4(0.12, 0.34, 0.38, 1.0);
uniform vec4 foam : source_color = vec4(0.86, 0.95, 0.94, 1.0);
uniform float scale = 0.12;
uniform float speed = 0.04;
uniform float band = 0.55;
uniform float sparkle_amount : hint_range(0.0, 1.0) = 0.6;
uniform float foam_width = 0.35;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 v_world;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz * scale;
	float n = noise(p + TIME * speed * vec2(1.0, 0.6)) * 0.6 + noise(p * 2.3 - TIME * speed * vec2(0.7, 1.2)) * 0.4;
	vec3 col = mix(deep.rgb, shallow.rgb, step(band, n));
	float sp = step(0.985, noise(p * 9.0 + TIME * 0.35)) * sparkle_amount;
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	world.xyz /= world.w;
	float diff = clamp((VERTEX.z - world.z) / foam_width, 0.0, 1.0);
	float edge = 1.0 - smoothstep(0.0, 1.0, diff);
	col = mix(col, foam.rgb, max(edge * 0.8, sp));
	ALBEDO = col;
	ROUGHNESS = 0.6;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float lit = smoothstep(0.1, 0.2, ndl) * smoothstep(0.45, 0.55, ATTENUATION);
	DIFFUSE_LIGHT += ALBEDO * mix(0.78, 1.0, lit) * LIGHT_COLOR / PI;
}
