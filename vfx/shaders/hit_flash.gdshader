shader_type spatial;
// Hit flash overlay (D-18). Owner: Lane D. Put on GeometryInstance3D.material_overlay by HitFlash;
// works over any base material. Per-node strength through instance uniforms, so one material is shared.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

instance uniform float flash = 0.0;
instance uniform vec4 flash_color : source_color = vec4(1.0);

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = flash_color.rgb;
	ALPHA = clamp(flash * (0.6 + 0.4 * rim), 0.0, 1.0);
}
