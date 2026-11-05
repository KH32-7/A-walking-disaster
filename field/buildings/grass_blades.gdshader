// Short soft grass for the B-26 kit ground. Owner: Lane B.
// Our own blade-clump mesh (kit_grass.gd), UV.y = 0 at the root, 1 at the tip. Colour runs from a
// deep base to a lighter tip, the tips sway in a slow wind, and the normal points straight up so a
// carpet of blades lights like the ground under it instead of flickering blade by blade.
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled, shadows_disabled;
#include "res://art/shaders/toon_local_light.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.13, 0.22, 0.09, 1.0);
uniform vec4 tip_color : source_color = vec4(0.33, 0.45, 0.18, 1.0);
uniform float sway = 0.07;
uniform float wind_speed = 1.4;
uniform vec4 shade_color : source_color = vec4(0.42, 0.50, 0.58, 1.0);

varying float v_tip;

void vertex() {
	v_tip = UV.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * wind_speed + world.x * 0.35 + world.z * 0.27) + 0.4 * sin(TIME * 2.3 + world.z * 0.9);
	VERTEX.x += w * sway * UV.y * UV.y;
	VERTEX.z += w * sway * 0.6 * UV.y * UV.y;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	ALBEDO = mix(base_color.rgb, tip_color.rgb, v_tip);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * toon_local_light(ATTENUATION, ndl) / PI;
	} else {
		float lit = smoothstep(0.0, 0.1, ndl) * smoothstep(0.45, 0.55, ATTENUATION);
		vec3 shade = mix(shade_color.rgb, vec3(1.0), mix(0.35, 1.0, lit));
		DIFFUSE_LIGHT += ALBEDO * shade * LIGHT_COLOR / PI;
	}
}
