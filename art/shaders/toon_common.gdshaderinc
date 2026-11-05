// Shared body of toon.gdshader and toon_double_sided.gdshader. Owner: Lane D (D-03).
// Each wrapper declares shader_type and render_mode, then includes this file.

uniform vec4 albedo : source_color = vec4(0.78, 0.79, 0.76, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 shade_color : source_color = vec4(0.42, 0.50, 0.58, 1.0);   // shadow tint (cool blue)
uniform int bands : hint_range(2, 3) = 3;
uniform float band_softness : hint_range(0.0, 0.2) = 0.03;
uniform float shadow_threshold : hint_range(-1.0, 1.0) = 0.05;
uniform float mid_threshold : hint_range(-1.0, 1.0) = 0.45;
uniform vec4 rim_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.35;
uniform float rim_width : hint_range(0.0, 1.0) = 0.72;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.0;
uniform float specular_size : hint_range(0.9, 1.0) = 0.985;
// Cut-out alpha (leaves, fences). Opaque pipeline: never write ALPHA directly.
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 0.0;

varying vec3 v_world_normal;

void vertex() {
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = albedo.rgb * tex.rgb;
	if (alpha_cut > 0.0 && albedo.a * tex.a < alpha_cut) {
		discard;
	}
	EMISSION = emission_color.rgb * emission_energy;
}

float band_step(float edge, float x) {
	return smoothstep(edge - band_softness, edge + band_softness, x);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = band_step(shadow_threshold, ndl);
	float level = lit;
	if (bands == 3) {
		level = mix(0.0, mix(0.6, 1.0, band_step(mid_threshold, ndl)), lit);
	}
	float shadow_atten = band_step(0.5, ATTENUATION);
	level *= shadow_atten;
	vec3 shade = mix(shade_color.rgb, vec3(1.0), level);
	DIFFUSE_LIGHT += ALBEDO * shade * LIGHT_COLOR / PI;

	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	rim = band_step(rim_width, rim) * clamp(ndl + 0.4, 0.0, 1.0);
	DIFFUSE_LIGHT += rim_color.rgb * rim * rim_amount * LIGHT_COLOR / PI;

	if (specular_amount > 0.0) {
		vec3 h = normalize(LIGHT + VIEW);
		float spec = band_step(specular_size, dot(NORMAL, h));
		SPECULAR_LIGHT += spec * specular_amount * LIGHT_COLOR * shadow_atten;
	}
}
