// Shared VFX sprite (D-18). Owner: Lane D. One material per blend mode, per-instance colour/spin/squash
// through instance uniforms so hundreds of sparks share a material.
// Meshes lie in the XY plane (vfx/fx_shapes.gd). `billboard` turns them to the camera, keeping scale.
uniform bool billboard = true;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float energy = 1.0;
instance uniform vec2 squash = vec2(1.0);
instance uniform float spin = 0.0;

void vertex() {
	vec2 v = VERTEX.xy * squash;
	float c = cos(spin);
	float s = sin(spin);
	VERTEX.xy = vec2(v.x * c - v.y * s, v.x * s + v.y * c);
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
				vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
				vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	ALBEDO = tint.rgb * COLOR.rgb * energy;
	ALPHA = clamp(tint.a * COLOR.a, 0.0, 1.0);
}
