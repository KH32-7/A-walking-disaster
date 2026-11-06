extends Node
## Sending a resident to a construction site from the site card (Colony.assign_job) makes them walk
## there at once (user report 2026-11-06: they only left after the site was moved, because only
## buildings_changed retargeted the crowd).

const BASE := "res://levels/base/base_school/base_school.tscn"


func run() -> bool:
	var snap := {"economy": JSON.from_native(Economy.save_data()), "colony": JSON.from_native(Colony.save_data())}
	Economy.load_data({})
	Colony.load_data({})
	var rid := Colony.add_resident({})
	var base := (load(BASE) as PackedScene).instantiate()
	add_child(base)
	await _frames(4)
	var ok := true
	var site := Colony.place_building(&"bed", Vector2i(4, 2), 0, &"front_yard", false)
	await _frames(3)
	var agent: ResidentAgent = base.residents.agent(rid)
	ok = _expect(agent != null, "the resident walks the base map") and ok
	if agent != null:
		var before := agent.target_position()
		ok = _expect(Colony.assign_job(rid, WorkRules.CONSTRUCTION_JOB, site), "sent to the site") and ok
		await _frames(2)
		var dest: Dictionary = base.residents.destination(rid)
		ok = _expect(agent.activity == &"work", "the agent is told to work (%s)" % agent.activity) and ok
		ok = _expect(agent.target_position().distance_to(dest["position"]) < 0.5 and
			agent.target_position().distance_to(before) > 1.0, "the agent heads for the site without the site moving") and ok
		Colony.unassign_job(rid)
		await _frames(2)
		ok = _expect(agent.activity == &"idle", "taken off the site: back to idle (%s)" % agent.activity) and ok
	base.queue_free()
	await _frames(2)
	Economy.load_data(JSON.to_native(snap.economy))
	Colony.load_data(JSON.to_native(snap.colony))
	return ok


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr("test_assign_retarget: " + message)
	return cond
