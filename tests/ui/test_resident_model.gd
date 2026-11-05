extends Node
## ResidentModel: which pack model a resident wears, gender fallback, and runtime loading that
## keeps the greybox when the private assets/ submodule is missing (CI).

const Move := RescueSpawn.Move
const A := Enums.AgeStage


func run() -> bool:
	var ok := true
	var mobility := [Enums.AccessNeed.MOBILITY]
	ok = _expect(ResidentModel.pick(_r(&"a", &"male", A.ADULT), Move.WHEELCHAIR) == ResidentModel.WHEELCHAIR_M, "wheelchair rescue: wheelchair") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"female", A.ADULT), Move.WHEELCHAIR) == ResidentModel.WHEELCHAIR_F, "woman in a wheelchair") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"male", A.ADULT, mobility)) == ResidentModel.WHEELCHAIR_M, "base: mobility adult uses a wheelchair") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"male", A.ELDER, mobility)) == ResidentModel.CANE_M, "base: mobility elder man walks with a cane") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"female", A.ELDER, mobility)) == ResidentModel.CRUTCHES_F, "base: mobility elder woman on crutches") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"male", A.ELDER, mobility), Move.SUPPORTED) == ResidentModel.CANE_M,
		"field supported elder matches the base") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"male", A.ADULT), Move.SUPPORTED) == ResidentModel.CRUTCHES_M, "supported adult man on crutches") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"female", A.CHILD), Move.CHILD) == ResidentModel.CHILD, "child model for children") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"male", A.TEEN, mobility)) == ResidentModel.WHEELCHAIR_F, "teen wheelchair model for the young") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"female", A.ELDER)) == ResidentModel.ELDER_F, "elder woman") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"female", A.ADULT, [], &"police")) == ResidentModel.POLICE_F, "police woman") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"male", A.ADULT, [], &"nurse")) == ResidentModel.DOCTOR_M, "male nurse in the doctor coat") and ok
	ok = _expect(ResidentModel.pick(_r(&"a", &"male", A.ADULT, [], &"mechanic")) == ResidentModel.WORKER_M, "male mechanic in work clothes") and ok
	ok = _expect(ResidentModel.CASUAL_F.has(ResidentModel.pick(_r(&"a", &"female", A.ADULT, [Enums.AccessNeed.HEARING], &"painter"))),
		"no visible need: a casual model, never a disability one") and ok
	for id: StringName in [&"one", &"two", &"three"]:
		var g := ResidentModel.gender_of({"id": id})
		ok = _expect(ResidentData.GENDERS.has(g) and g == ResidentModel.gender_of({"id": id}), "gender from id is fixed (%s)" % id) and ok
	ok = _expect(is_equal_approx(ResidentModel.scale_for(_r(&"a", &"male", A.TEEN)), ResidentModel.TEEN_SCALE), "teens a little smaller") and ok

	# Loading: with assets the greybox hides and idle plays; without them nothing changes.
	var body := Node3D.new()
	var grey := Node3D.new()
	grey.name = "Greybox"
	body.add_child(grey)
	var model := ResidentModel.new()
	body.add_child(model)
	add_child(body)
	for r: Dictionary in [_r(&"a", &"male", A.ADULT), _r(&"b", &"female", A.ADULT), _r(&"c", &"male", A.ADULT), _r(&"d", &"female", A.CHILD)]:
		var moves := [Move.WALK, Move.WHEELCHAIR, Move.SUPPORTED, Move.CHILD]
		var move: int = moves[[&"a", &"b", &"c", &"d"].find(r["id"])]
		var path := ResidentModel.pick(r, move)
		var shown := model.show_resident(r, move)
		if ResourceLoader.exists(path):
			ok = _expect(shown and model.has_model() and not grey.visible, "model shown, greybox hidden (%s)" % path.get_file()) and ok
			ok = _expect(model.current_motion() == ResidentModel.IDLE, "idle plays (%s)" % path.get_file()) and ok
			model._process(0.1)
			body.position.x += 1.0
			model._process(0.1)
			ok = _expect(model.current_motion() == ResidentModel.WALK, "moving plays walk (%s)" % path.get_file()) and ok
		else:
			ok = _expect(not shown and not model.has_model() and grey.visible, "no assets: greybox stays (%s)" % path.get_file()) and ok
	model.clear()
	ok = _expect(grey.visible and model.model_path() == "", "clear shows the greybox again") and ok
	body.free()
	return ok


func _r(id: StringName, gender: StringName, age: int, needs: Array = [], job: StringName = &"student") -> Dictionary:
	return {"id": id, "gender": gender, "age_stage": age, "access_needs": needs, "former_job": job}


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
