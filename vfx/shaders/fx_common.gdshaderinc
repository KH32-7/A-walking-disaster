// Shared body of fx_add / fx_mix (D-18). Owner: Lane D.
// Particles: billboard or velocity-stretched quads, flipbook from INSTANCE_CUSTOM.z, colour from the
// process material. Meshes (MESH / GROUND / BEAM): colour, age and UV length from instance uniforms.

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool particle = true;
// 0 billboard, 1 velocity stretch, 2 keep the mesh transform
uniform int align = 0;
// 0 rgba, 1 red is alpha, 2 packed (R shape, G dissolve, A alpha)
uniform int channel = 0;
uniform vec2 frames = vec2(1.0);
uniform float dissolve = 0.0;
uniform vec2 uv_scroll = vec2(0.0);
uniform bool rotate_uv = false;

instance uniform vec4 fx_color = vec4(1.0);
instance uniform float fx_age = 0.0;
instance uniform float fx_uv_length = 1.0;

varying float v_age;

void vertex() {
	// The particle branch writes POSITION, and a shader that writes it anywhere uses it for every vertex:
	// without this default the meshes (MESH / GROUND / BEAM) collapsed and were never drawn (issue #153).
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (particle) {
		v_age = INSTANCE_CUSTOM.y;
		vec3 center = MODEL_MATRIX[3].xyz;
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		if (align == 0) {
			float a = INSTANCE_CUSTOM.x;
			vec2 v = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * (VERTEX.xy * vec2(sx, sy));
			vec3 world = center + INV_VIEW_MATRIX[0].xyz * v.x + INV_VIEW_MATRIX[1].xyz * v.y;
			POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
		} else if (align == 1) {
			vec3 dir = MODEL_MATRIX[1].xyz / max(sy, 0.0001);
			vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - center);
			vec3 side = cross(dir, to_cam);
			side = length(side) < 0.001 ? INV_VIEW_MATRIX[0].xyz : normalize(side);
			vec3 world = center + side * VERTEX.x * sx + dir * VERTEX.y * sy;
			POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
		}
		float total = frames.x * frames.y;
		if (total > 1.0) {
			float f = min(floor(INSTANCE_CUSTOM.z * total), total - 1.0);
			UV = (UV + vec2(mod(f, frames.x), floor(f / frames.x))) / frames;
		}
	} else {
		v_age = fx_age;
		COLOR *= fx_color;
		UV.y *= fx_uv_length;
		UV += uv_scroll * TIME;
		if (rotate_uv) {
			UV = UV.yx;
		}
	}
}

void fragment() {
	vec4 t = texture(tex, UV);
	vec3 rgb = t.rgb;
	float a = t.a;
	if (channel == 1) {
		rgb = vec3(1.0);
		a = t.r;
	} else if (channel == 2) {
		rgb = vec3(1.0);
		a = t.r * t.a;
		if (dissolve > 0.0) {
			a *= smoothstep(v_age * dissolve, v_age * dissolve + 0.08, t.g);
		}
	}
	ALBEDO = rgb * COLOR.rgb;
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
