extends CharacterBody3D
## Stand-in player for the B-07 monster test scene until B-03 lands.
## In group "player" on the player layer. WASD moves, Space (dodge) makes a
## 10 m noise, F (interact) hits the nearest monster within reach.

const SPEED := 5.0
const NOISE_RADIUS := 10.0
const HIT_DAMAGE := 25.0
const HIT_REACH := 4.0

## Hits received from monsters: [{"amount": float, "info": Dictionary}]
var hits: Array[Dictionary] = []


func _ready() -> void:
	add_to_group(Monster.PLAYER_GROUP)
	collision_layer = 1 << (Enums.LAYER_PLAYER - 1)
	collision_mask = 1 << (Enums.LAYER_WORLD - 1)


func _physics_process(_delta: float) -> void:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = Vector3(input.x, 0.0, input.y) * SPEED
	move_and_slide()
	if Input.is_action_just_pressed(&"dodge"):
		make_noise(NOISE_RADIUS)
	if Input.is_action_just_pressed(&"interact"):
		hit_nearest()


func make_noise(radius: float) -> void:
	EventBus.noise_emitted.emit(global_position, radius, self)


func hit_nearest() -> void:
	var best: Monster
	for node in get_tree().get_nodes_in_group(Monster.GROUP):
		var m := node as Monster
		if m.global_position.distance_to(global_position) <= HIT_REACH and (
				best == null or m.global_position.distance_to(global_position) < best.global_position.distance_to(global_position)):
			best = m
	if best:
		best.take_damage(HIT_DAMAGE, {"source": self, "element": Enums.Element.NONE, "position": global_position})


## Same entry point monsters expect on the real player (B-03).
func take_damage(amount: float, info: Dictionary) -> void:
	hits.append({"amount": amount, "info": info})
	print("[b07] player hit %.1f by %s bind_sec=%s" % [amount, info.get("monster_id"), info.get("bind_sec", 0.0)])
