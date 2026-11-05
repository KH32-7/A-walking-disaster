extends Node3D
## Base map assembly (C-09): what SceneRouter loads as the base (SceneRouter.BASE_SCENE).
## = layout.tscn (C: collision, navigation, markers) + dressing.tscn (D, optional) + player + camera.
## The dressing is loaded at runtime when the file exists, so this scene works before Lane D has
## made it and Lane C never has to save Lane D's scene. Without a dressing a plain greybox light
## and sky are added so the map is visible.

const DRESSING := "res://levels/base/base_school/dressing.tscn"
const SPAWN_ID := &"main"

@onready var layout: Node3D = $Layout
@onready var player: Node3D = $Player
@onready var build_mode: BuildMode = $BuildMode
@onready var building_views: BuildingViews = $BuildingViews
@onready var residents: ResidentCrowd = $Residents

## Placement rules for this map (C-03). Built from the layout's BuildArea / ZoneMarker / ResourceNode.
var grid: BaseGrid


func _ready() -> void:
	grid = BaseGrid.from_layout(layout)
	build_mode.grid = grid
	building_views.grid = grid
	residents.grid = grid
	residents.layout = layout
	# Paths asked for before the navmesh exists come back empty: ask again once it is baked.
	layout.navigation_ready.connect(residents.retarget)
	# D-06 건설 패널 "배치하기" → grid placement here (C-03). The connection ends with this node.
	UI.build_requested.connect(_on_build_requested)
	build_mode.placed.connect(func(uid: StringName) -> void:
		EventBus.notification_posted.emit("%s 건설 현장을 놓았다" % BaseDB.get_building(Colony.get_building(uid)["def_id"]).display_name, &"info"))
	# 직접 방어전 (C-17): Colony asks this scene to play a raid on the base map.
	Colony.defense_requested.connect(_on_defense_requested)
	if not Colony.direct_defense().is_empty():  # asked before this scene was loaded (긴급 귀환)
		_on_defense_requested.call_deferred(Colony.direct_defense()["raid"], Colony.direct_defense()["first_wave"])
	if ResourceLoader.exists(DRESSING):
		var dressing := (load(DRESSING) as PackedScene).instantiate()
		dressing.name = "Dressing"
		add_child(dressing)
	else:
		_add_greybox_lighting()
	_place_player()


## The battle node runs the waves and reports to Colony; D-14 finds it with get_battle().
func _on_defense_requested(raid: Dictionary, first_wave: int) -> void:
	if get_battle() != null:
		return
	var battle := DefenseBattle.new()
	battle.name = "DefenseBattle"
	add_child(battle)
	battle.setup(raid, first_wave, layout, player, residents, building_views)
	battle.start()


func get_battle() -> DefenseBattle:
	return get_node_or_null(^"DefenseBattle") as DefenseBattle


func _on_build_requested(def_id: StringName) -> void:
	if not build_mode.start(def_id):
		EventBus.notification_posted.emit("이 건물은 격자에 놓을 수 없어요", &"warn")


## Puts the player on the layout's PlayerSpawn (spawn_id "main").
func _place_player() -> void:
	for spawn in layout.find_children("*", "Marker3D", true, false):
		if spawn is PlayerSpawn and (spawn as PlayerSpawn).spawn_id == SPAWN_ID:
			player.global_position = (spawn as Node3D).global_position
			return
	push_warning("base_school: no PlayerSpawn '%s' in layout" % SPAWN_ID)


func _add_greybox_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "GreyboxSun"
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.name = "GreyboxEnvironment"
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	add_child(env)
