class_name ResidentCrowd
extends Node3D
## Residents on the base map (C-07): one ResidentAgent per active resident, sent to work, the
## evening gathering and bed by the day phase (docs/design/01-flow-time.md "하루 구조"):
##   MORNING / STAY → work (workplace building, its WorkSpot, or the construction site)
##   EVENING        → gather (best 모닥불·식당 building, else the layout's GatherPoint)
##   입주 의식 대기 중  → welcome (낮에 모두 모임터로 마중, C-13)
##   NIGHT          → sleep (own bed: main-hall BedSpots marker or the bed building)
## Residents without a job idle near the gathering point. Stranded / dead / left residents are removed.

const SPREAD := 1.5  # spread people around a shared point so they don't stack (m)

var grid: BaseGrid
var layout: Node3D

var _agents: Dictionary = {}  # resident_id -> ResidentAgent


func _ready() -> void:
	# Methods, not lambdas: connections to autoload signals then end when this node is freed.
	EventBus.resident_joined.connect(_on_resident_changed)
	EventBus.resident_left.connect(_on_resident_gone)
	EventBus.resident_died.connect(_on_resident_gone)
	EventBus.phase_changed.connect(_on_phase_changed)
	EventBus.evening_settled.connect(_on_evening_settled)
	Colony.buildings_changed.connect(_on_buildings_changed)
	Colony.arrival_ready.connect(_on_resident_changed)
	Colony.resident_profile_changed.connect(_on_resident_changed)
	Colony.arrival_completed.connect(_on_arrival_completed)
	sync.call_deferred()


func agent(resident_id: StringName) -> ResidentAgent:
	return _agents.get(resident_id)


func agent_count() -> int:
	return _agents.size()


## Adds agents for new active residents, removes the others, then retargets everyone.
func sync() -> void:
	if layout == null or not is_inside_tree():
		return
	var active := Colony.active_resident_ids()
	for id: StringName in _agents.keys():
		if not id in active:
			_agents[id].queue_free()
			_agents.erase(id)
	var spawn := _gather_point()
	for id in active:
		if _agents.has(id):
			_agents[id].refresh_from_colony()
			continue
		var a := ResidentAgent.new()
		a.setup(id)
		add_child(a)
		a.global_position = spawn + _offset(id)
		_agents[id] = a
	retarget()


## Sends everyone to where the current phase wants them.
func retarget() -> void:
	if layout == null or not is_inside_tree():
		return
	for id: StringName in _agents:
		var dest := destination(id)
		_agents[id].set_target(dest["position"], dest["activity"])


## {"position": Vector3, "activity": StringName} for one resident right now.
func destination(resident_id: StringName) -> Dictionary:
	var r := Colony.get_resident(resident_id)
	match GameState.phase:
		Enums.Phase.NIGHT:
			return {"position": _bed_position(r), "activity": &"sleep"}
	# 입주 의식 1단계: everyone comes out to greet a newcomer (C-13).
	if not Colony.pending_arrivals().is_empty():
		return {"position": _gather_point() + _offset(resident_id), "activity": &"welcome"}
	match GameState.phase:
		Enums.Phase.EVENING:
			return {"position": _gather_point() + _offset(resident_id), "activity": &"gather"}
	var work = _work_position(r)
	if work != null and WorkRules.can_work(r):
		return {"position": work, "activity": &"work"}
	return {"position": _gather_point() + _offset(resident_id), "activity": &"idle"}


func _work_position(r: Dictionary) -> Variant:
	var job: StringName = r["assignment"]["job"]
	if job == &"" or job == WorkRules.REST_JOB:
		return null
	var uid: StringName = r["assignment"]["building_id"]
	var b := Colony.get_building(uid)
	if not b.is_empty() and grid != null and grid.areas.has(b["zone_id"]):
		var def := BaseDB.get_building(b["def_id"])
		var size := BaseGrid.footprint(def, int(b["rotation"]))
		return grid.footprint_center(b["zone_id"], Vector2i(b["cell"][0], b["cell"][1]), size) + _offset(r["id"])
	# Jobs at fixed map spots (방송실 → radio WorkSpot) or buildings off the grid.
	for node in layout.find_children("*", "Marker3D", true, false):
		if node is WorkSpot and node.job_id == job:
			return node.global_position + _offset(r["id"]) * 0.5
	return null


func _bed_position(r: Dictionary) -> Vector3:
	var bed := String(r["bed_id"])
	if bed == "":
		return _gather_point() + _offset(r["id"])  # 임시 거처: sleeps by the fire
	var spot := layout.get_node_or_null("BedSpots/" + bed) as Node3D
	if spot != null:
		return spot.global_position
	var uid := StringName(bed.get_slice("_bed_", 0))
	var b := Colony.get_building(uid)
	if not b.is_empty() and grid != null and grid.areas.has(b["zone_id"]):
		var def := BaseDB.get_building(b["def_id"])
		var size := BaseGrid.footprint(def, int(b["rotation"]))
		return grid.footprint_center(b["zone_id"], Vector2i(b["cell"][0], b["cell"][1]), size) + _offset(r["id"]) * 0.5
	return _gather_point()


## Best gathering building (식당 > 모닥불), else the layout's GatherPoint marker.
func _gather_point() -> Vector3:
	for def_id in [&"dining_hall", &"bonfire"]:
		for uid in Colony.working_building_ids(def_id):
			var b := Colony.get_building(uid)
			if grid != null and grid.areas.has(b["zone_id"]):
				var size := BaseGrid.footprint(BaseDB.get_building(def_id), int(b["rotation"]))
				return grid.footprint_center(b["zone_id"], Vector2i(b["cell"][0], b["cell"][1]), size)
	var marker := layout.get_node_or_null("GatherPoint") as Node3D
	return marker.global_position if marker else Vector3.ZERO


## Stable small offset per resident so a group spreads out around a point.
func _offset(resident_id: StringName) -> Vector3:
	var h := absi(hash(resident_id))
	var angle := float(h % 360) * PI / 180.0
	var dist := SPREAD * (0.5 + float(floori(h / 360.0) % 100) / 200.0)
	return Vector3(cos(angle), 0.0, sin(angle)) * dist


func _on_resident_changed(_id: StringName) -> void:
	sync.call_deferred()


func _on_resident_gone(_id: StringName, _why: StringName) -> void:
	sync.call_deferred()


func _on_phase_changed(_phase: Enums.Phase) -> void:
	retarget()


func _on_evening_settled(_report: Dictionary) -> void:
	sync.call_deferred()


func _on_buildings_changed() -> void:
	retarget.call_deferred()


func _on_arrival_completed(_id: StringName, _result: Dictionary) -> void:
	sync.call_deferred()
