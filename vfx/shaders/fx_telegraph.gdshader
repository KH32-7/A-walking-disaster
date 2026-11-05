// Boss area warning (D-18). Owner: Lane D. Exact shape of the hit area (BossMonster.area_contains),
// so it never depends on pack textures: circle, ring, cone, line. Local forward is -Z.
// The fill grows from the origin outward as the wind-up runs (fx_age 0..1), the border stays solid.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// 0 circle, 1 ring, 2 cone, 3 line
instance uniform int fx_shape = 0;
instance uniform float fx_radius = 1.0;
instance uniform float fx_inner = 0.0;
instance uniform float fx_half_angle = 0.5;
instance uniform float fx_length = 1.0;
instance uniform float fx_width = 1.0;
instance uniform vec4 fx_color = vec4(1.0);
instance uniform float fx_age = 0.0;

const float BORDER = 0.12;
const float FILL_ALPHA = 0.38;
const float AREA_ALPHA = 0.12;
const float BORDER_ALPHA = 0.85;

varying vec2 p;

void vertex() {
	p = VERTEX.xz;
}

void fragment() {
	float d = length(p);
	float edge = -1.0;
	float f = 0.0;
	if (fx_shape == 0) {
		edge = fx_radius - d;
		f = d / max(fx_radius, 0.001);
	} else if (fx_shape == 1) {
		edge = min(d - fx_inner, fx_radius - d);
		f = (d - fx_inner) / max(fx_radius - fx_inner, 0.001);
	} else if (fx_shape == 2) {
		float ang = d < 0.001 ? 0.0 : acos(clamp(dot(p / d, vec2(0.0, -1.0)), -1.0, 1.0));
		edge = min(fx_radius - d, d * sin(clamp(fx_half_angle - ang, -1.5, 1.5)));
		edge = d < 0.01 ? fx_radius : edge;
		f = d / max(fx_radius, 0.001);
	} else {
		float along = -p.y;
		edge = min(min(along, fx_length - along), fx_width * 0.5 - abs(p.x));
		f = along / max(fx_length, 0.001);
	}
	if (edge < 0.0) {
		discard;
	}
	float a = f <= fx_age ? FILL_ALPHA : AREA_ALPHA;
	if (edge < BORDER) {
		a = BORDER_ALPHA;
	}
	ALBEDO = fx_color.rgb;
	ALPHA = a * fx_color.a;
}
