// Element glow core (monster cores, engraved weapons, essence pickups). Owner: Lane D (D-03).
// Design 16 "마물 비주얼 언어": green=petal, stone=square, water=drop, light=bolt. The shape comes
// from the mesh; this shader gives the colour, fresnel halo and a slow pulse.
// reduce_flash (Settings) -> set pulse_amount to 0 from code.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(0.48, 0.85, 0.42, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 1.6;
uniform float core_amount : hint_range(0.0, 1.0) = 0.65;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.5;
uniform float pulse_speed : hint_range(0.0, 6.0) = 1.4;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float pulse = 1.0 - pulse_amount * (0.5 + 0.5 * sin(TIME * pulse_speed * 6.2831));
	float a = clamp(core_amount + f, 0.0, 1.0) * pulse;
	ALBEDO = glow_color.rgb * energy * a;
}
