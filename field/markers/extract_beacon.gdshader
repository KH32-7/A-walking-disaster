// Extraction beacon beam (ExtractBeacon): additive green column that fades toward the top and
// pulses slowly, like flare smoke catching the light.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.37, 0.77, 0.42, 1.0);
uniform float strength = 0.55;
uniform bool fade_up = true;

void fragment() {
	// CylinderMesh: UV.y is 0 at the top, 1 at the bottom.
	float h = fade_up ? pow(UV.y, 1.6) : 1.0;
	// Softer at the silhouette, brighter facing the camera.
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float pulse = 0.8 + 0.2 * sin(TIME * 2.2 - UV.y * 6.0);
	ALBEDO = color.rgb;
	ALPHA = clamp(strength * h * pulse * (0.35 + 0.65 * facing), 0.0, 1.0);
}
