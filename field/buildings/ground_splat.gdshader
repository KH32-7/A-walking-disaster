// Whole-region ground for the B-26 kit. Owner: Lane B.
// One mesh over all the land. A baked splat map (R road, G vegetation, B dirt by buildings and water
// banks, blurred) picks the pack terrain textures, and value noise breaks every edge so roads crumble
// into the verge instead of ending on a straight line. Textures are projected from above in world space.
// Lighting is the Lane D toon model (art/shaders/toon_common.gdshaderinc). Keep light() in step with it.
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;

uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform vec2 splat_origin = vec2(-112.5);
uniform vec2 splat_size = vec2(225.0);

uniform sampler2D land_a : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D land_b : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D vegetation : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D road : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D dirt : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float land_tile = 7.0;
uniform float vegetation_tile = 5.0;
uniform float road_tile = 6.0;
uniform float dirt_tile = 5.0;
// How far noise pushes the edges (splat units). Higher = more ragged.
uniform float edge_noise = 0.55;
// The pack asphalt is dark; lift it so the cool grade does not crush it to black.
uniform float road_bright = 1.0;
uniform vec4 tint : source_color = vec4(1.0);

uniform vec4 shade_color : source_color = vec4(0.42, 0.50, 0.58, 1.0);
uniform float band_softness : hint_range(0.0, 0.2) = 0.03;
uniform float shadow_threshold : hint_range(-1.0, 1.0) = 0.05;
uniform float mid_threshold : hint_range(-1.0, 1.0) = 0.45;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.3 + 11.0) * 0.3 + value_noise(p * 5.1 + 3.0) * 0.15;
}

// Two samples, the second turned and larger, mixed by slow noise: no visible tiling from above.
vec3 tex2(sampler2D t, vec2 xz, float tile) {
	vec2 uv = xz / tile;
	vec3 a = texture(t, uv).rgb;
	vec3 b = texture(t, mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * uv * 0.43 + vec2(0.37, 0.71)).rgb;
	return mix(a, b, smoothstep(0.3, 0.7, value_noise(xz * 0.05)));
}

void fragment() {
	vec2 xz = v_world.xz;
	vec4 s = texture(splat_map, (xz - splat_origin) / splat_size);
	float n = fbm(xz * 0.35) - 0.5;
	float n2 = fbm(xz * 0.09 + 40.0) - 0.5;

	vec3 col = mix(tex2(land_a, xz, land_tile), tex2(land_b, xz, land_tile * 1.3), smoothstep(-0.15, 0.2, n2));
	float d = smoothstep(0.25, 0.65, s.b + n * edge_noise);
	col = mix(col, tex2(dirt, xz, dirt_tile), d * 0.85);
	float v = smoothstep(0.35, 0.6, s.g + n * edge_noise);
	col = mix(col, tex2(vegetation, xz, vegetation_tile), v);
	float r = smoothstep(0.45, 0.6, s.r + n * edge_noise);
	// Crumbled shoulder: dirt just outside the asphalt.
	float shoulder = smoothstep(0.15, 0.45, s.r + n * edge_noise) * (1.0 - r);
	col = mix(col, tex2(dirt, xz, dirt_tile), shoulder * 0.7);
	col = mix(col, tex2(road, xz, road_tile) * road_bright, r);
	col *= mix(0.86, 1.06, value_noise(xz * 0.13 + vec2(17.0, 5.0)));
	ALBEDO = tint.rgb * col;
}

float band_step(float edge, float x) {
	return smoothstep(edge - band_softness, edge + band_softness, x);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = band_step(shadow_threshold, ndl);
	float level = mix(0.0, mix(0.6, 1.0, band_step(mid_threshold, ndl)), lit);
	level *= band_step(0.5, ATTENUATION);
	vec3 shade = mix(shade_color.rgb, vec3(1.0), level);
	DIFFUSE_LIGHT += ALBEDO * shade * LIGHT_COLOR / PI;
}
