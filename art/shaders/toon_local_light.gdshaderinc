// Point and spot lights on toon surfaces (street lamps, muzzle flashes, fires, indoor lamps).
// Included by every toon light() function. The sun keeps each shader's own banded shading; a local
// light instead cuts its distance falloff into two soft bands, so it draws a round pool of light
// with a bright core and a dimmer rim instead of tinting its whole range in the shade colour.
// Returns the light amount to multiply ALBEDO * LIGHT_COLOR / PI by.

float toon_local_light(float attenuation, float ndl) {
	float a = attenuation * clamp(ndl * 0.8 + 0.2, 0.0, 1.0);
	return smoothstep(0.03, 0.08, a) * 0.55 + smoothstep(0.2, 0.3, a) * 0.45;
}
