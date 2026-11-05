// Ground and flat roof surface for the B-26 kit. Owner: Lane B.
// A pack terrain texture projected from above in world space (no mesh UVs needed), blended with a
// second, turned and larger sample and a slow tint noise so the tiling does not show from above.
// Lighting is the Lane D toon model (art/shaders/toon_common.gdshaderinc). Keep light() in step with it.
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;
#include "res://art/shaders/toon_local_light.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float tile_size = 6.0;
uniform float variation : hint_range(0.0, 1.0) = 0.22;
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

void fragment() {
	vec2 uv = v_world.xz / tile_size;
	vec3 a = texture(albedo_texture, uv).rgb;
	vec3 b = texture(albedo_texture, mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * uv * 0.43 + vec2(0.37, 0.71)).rgb;
	vec3 col = mix(a, b, smoothstep(0.3, 0.7, value_noise(v_world.xz * 0.05)));
	col *= mix(1.0 - variation, 1.0 + variation * 0.4, value_noise(v_world.xz * 0.13 + vec2(17.0, 5.0)));
	ALBEDO = albedo.rgb * col;
}

float band_step(float edge, float x) {
	return smoothstep(edge - band_softness, edge + band_softness, x);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * toon_local_light(ATTENUATION, ndl) / PI;
	} else {
		float lit = band_step(shadow_threshold, ndl);
		float level = mix(0.0, mix(0.6, 1.0, band_step(mid_threshold, ndl)), lit);
		level *= band_step(0.5, ATTENUATION);
		vec3 shade = mix(shade_color.rgb, vec3(1.0), level);
		DIFFUSE_LIGHT += ALBEDO * shade * LIGHT_COLOR / PI;
	}
}
