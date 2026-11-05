extends RefCounted
## B-02: every field marker scene loads, draws nothing at runtime and joins
## its groups so field systems can find it.

const SCENES := {
	"res://field/markers/player_spawn.tscn": PlayerSpawn.GROUP,
	"res://field/markers/extract_point.tscn": ExtractPoint.GROUP,
	"res://field/markers/loot_spot.tscn": LootSpot.GROUP,
	"res://field/markers/monster_nest.tscn": MonsterNest.GROUP,
	"res://field/markers/rescue_spot.tscn": RescueSpot.GROUP,
	"res://field/markers/hidden_route.tscn": HiddenRoute.GROUP,
	"res://field/markers/boss_arena.tscn": BossArena.GROUP,
	"res://field/markers/recording.tscn": Recording.GROUP,
}


func run() -> bool:
	var root := (Engine.get_main_loop() as SceneTree).root
	var ok := true
	for path: String in SCENES:
		var packed := load(path) as PackedScene
		var marker := packed.instantiate() as FieldMarker if packed else null
		if marker == null:
			push_error("%s does not load as a FieldMarker" % path)
			ok = false
			continue
		root.add_child(marker)
		if not marker.is_in_group(FieldMarker.GROUP_ALL) or not marker.is_in_group(SCENES[path]):
			push_error("%s is not in its groups at runtime" % path)
			ok = false
		if _has_visual(marker):
			push_error("%s draws something at runtime" % path)
			ok = false
		if marker is HiddenRoute and marker.from_point().distance_to(marker.to_point()) < 1.0:
			push_error("%s needs separate From and To points" % path)
			ok = false
		marker.free()
	return ok


func _has_visual(node: Node) -> bool:
	for child in node.get_children(true):
		if child is VisualInstance3D or _has_visual(child):
			return true
	return false
