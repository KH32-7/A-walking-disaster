// Point and spot lights on toon surfaces (street lamps, muzzle flashes, fires, indoor lamps).
// Included by every toon light() function. The sun keeps each shader's own banded shading; a local
// light instead cuts its distance falloff into two soft bands, so it draws a round pool of light
// with a bright core and a dimmer rim instead of tinting its whole range in the shade colour.
// Returns the light amount to multiply ALBEDO * LIGHT_COLOR / PI by.

//
// Global `toon_amount` (project.godot shader_globals, 1 = toon, default 0 since 2026-11-06): 0 swaps every toon surface to plain
// smooth Lambert shading, so the look can be compared with toon off (debug \ panel, Look autoload).
global uniform float toon_amount;

float toon_local_light(float attenuation, float ndl) {
	float a = attenuation * clamp(ndl * 0.8 + 0.2, 0.0, 1.0);
	float toon = smoothstep(0.03, 0.08, a) * 0.55 + smoothstep(0.2, 0.3, a) * 0.45;
	return mix(attenuation * clamp(ndl, 0.0, 1.0), toon, toon_amount);
}
