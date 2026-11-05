class_name FxLayer
extends Resource
## One piece of an effect (D-18). Owner: Lane D. Built by FxNode.
## Texture and mesh paths point into res://assets/vfx/ and are kept as strings, so a clone without the
## assets submodule still loads every effect .tres; FxNode skips a layer whose file is missing.

## TELEGRAPH: boss area warning drawn by vfx/shaders/fx_telegraph.gdshader from params
## (shape, radius, inner, angle_deg, length, width, direction, kind). Needs no texture.
enum Kind { PARTICLES, MESH, GROUND, BEAM, LIGHT, TELEGRAPH }
## BILLBOARD faces the camera. VELOCITY: particle quad stretched along its motion.
## FLAT: particle quad lies on the ground. DIRECTION: MESH points along params.direction.
enum Align { BILLBOARD, VELOCITY, FLAT, DIRECTION }
enum Blend { ADD, MIX }
## RGBA: the texture's own colour and alpha. MASK: red channel is the alpha (grey masks without alpha).
## PACKED: Stylized Shoot & Hit set (R shape, G dissolve, A alpha).
enum Channel { RGBA, MASK, PACKED }

@export var kind := Kind.PARTICLES
@export_file("*.png") var texture := ""
## Index = Enums.Element. A non-empty entry replaces `texture` for that element.
@export var element_textures := PackedStringArray()
## MESH, or the particle shape when set (an .fbx/.obj from the pack).
@export_file var mesh := ""
## Flipbook columns x rows. Played once over each particle's life.
@export var sheet := Vector2i.ONE
@export var channel := Channel.RGBA
@export var blend := Blend.ADD
@export var color := Color.WHITE
## Multiply by the element colour (UiTokens.ELEMENT_COLORS) when params.element is set.
@export var tint_element := false
## Bright layer: dimmed when Settings.reduce_flash is on.
@export var flash := false
## Shown only when every key equals the spawn param, e.g. {"crit": true} or {"combat_class": 1}.
@export var when := {}

@export var delay := 0.0
## Seconds. PARTICLES: each particle's life. Others: the layer's life (or fade-in time when `loop`).
@export var lifetime := 0.5
## Keep going until the whole effect ends (zones with params.duration).
@export var loop := false

@export_group("Particles")
@export var amount := 8
@export_range(0.0, 1.0) var explosiveness := 1.0
@export var align := Align.BILLBOARD
## Particle size min, max (m).
@export var size := Vector2(0.3, 0.5)
## Size at the end of a particle's life, relative to its start.
@export var end_scale := 1.0
## VELOCITY align: quad length / width.
@export var stretch := 1.0
@export var speed := Vector2(1.0, 3.0)
## Local emit direction; DIRECTION-aligned effects turn it toward params.direction.
@export var direction := Vector3.UP
@export_range(0.0, 180.0) var spread_deg := 180.0
@export var gravity := 0.0
@export var emit_radius := 0.0
@export var spin := true
## Turn the emitter toward params.direction / params.normal while keeping `align` for drawing
## (DIRECTION align does this too). `direction` is then authored as FORWARD (-Z).
@export var follow_direction := false

@export_group("Shape")
## MESH / GROUND / BEAM: size at start (x) and end (y) in m. GROUND is the diameter, BEAM x is the width.
@export var grow := Vector2(1.0, 1.0)
@export var offset := Vector3.ZERO
@export var mesh_rotation_deg := Vector3.ZERO
## BEAM: speed (m/s) of a streak of length grow.y running to params.to. 0 draws the whole line.
@export var travel_speed := 0.0
## UV scroll per second (BEAM electricity, GROUND swirl).
@export var uv_scroll := Vector2.ZERO
## Swap U and V (a beam texture drawn left to right instead of bottom to top).
@export var rotate_uv := false
## PACKED: fraction of the shape eaten by the G channel by the end of the layer.
@export_range(0.0, 1.0) var dissolve := 0.0

@export_group("Fade")
## Fractions of the layer's life.
@export_range(0.0, 1.0) var fade_in := 0.0
@export_range(0.0, 1.0) var fade_out := 0.6
## Size, emit radius and speed scale with params.radius / FxDef.base_radius.
@export var follow_radius := false

@export_group("Light")
@export var light_energy := 2.0
@export var light_range := 4.0
