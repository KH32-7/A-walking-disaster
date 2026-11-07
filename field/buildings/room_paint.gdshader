// Toon shader plus room wall paint for American Suburb wall pieces (field/buildings/city_kit.gd
// paint_walls). Same uniforms as toon.gdshader, plus the ROOM_PAINT block of toon_common.
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

#define ROOM_PAINT
#include "res://art/shaders/toon_common.gdshaderinc"
