// A patch of ground (grass over soil) whose rounded-rectangle edge crumbles into what is below it
// instead of ending on a straight line (base clearing, ForestDressing). Owner: art.
// The patch is a flat mesh centred on its own origin; half_size and corner_radius describe its
// outline. Inside `feather` metres of the edge the patch fades out, and value noise pushes that fade
// in and out so the border reads as torn tufts and bare spots. The texture is projected from above
// in world space so neighbouring patches line up.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float uv_metres = 4.0;
uniform vec2 half_size = vec2(10.0);
uniform float corner_radius = 4.0;
// Width (m) of the soft band along the edge.
uniform float feather = 4.0;
// How far (m) noise moves the edge in and out.
uniform float ragged = 2.5;
uniform float noise_scale = 0.18;

varying vec2 v_local;
varying vec2 v_world;

void vertex() {
	v_local = VERTEX.xz;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
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
	return value_noise(p) * 0.55 + value_noise(p * 2.3 + 17.0) * 0.3 + value_noise(p * 5.1 + 41.0) * 0.15;
}

// Signed distance to the rounded rectangle (negative inside).
float rounded_rect(vec2 p) {
	float r = min(corner_radius, min(half_size.x, half_size.y));
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	float d = rounded_rect(v_local);
	float n = fbm(v_world * noise_scale) - 0.5;
	// 0 at the mesh edge .. 1 a feather inside it, pushed by the noise.
	float a = smoothstep(0.0, feather, -d - ragged * 0.5 + n * ragged * 2.0);
	vec4 t = texture(albedo_texture, v_world / uv_metres);
	ALBEDO = albedo.rgb * t.rgb * mix(0.85, 1.05, value_noise(v_world * 0.13 + 5.0));
	ALPHA = a;
	ROUGHNESS = 1.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
