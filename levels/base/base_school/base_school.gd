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
	if ResourceLoader.exists(DRESSING):
		var dressing := (load(DRESSING) as PackedScene).instantiate()
		dressing.name = "Dressing"
		add_child(dressing)
	else:
		_add_greybox_lighting()
	_place_player()


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
