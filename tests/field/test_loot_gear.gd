extends Node
## Finished weapons in containers (사용자 요청 2026-11-06): LootTable.gear_chance / gear_pool, and a gear
## slot that becomes a real item in the bag when taken. Called by tests/run_tests.gd.


func run() -> bool:
	var ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t := LootTable.new()
	t.gear_pool = [&"pistol"]
	t.gear_chance = 0.0
	ok = _expect(t.roll_gear(rng) == &"", "chance 0: no weapon") and ok
	t.gear_chance = 1.0
	ok = _expect(t.roll_gear(rng) == &"pistol", "chance 1: a weapon from the pool") and ok
	# Every region table has a low, non-zero chance and a pool of real item defs.
	for path in ["res://data/loot/tables/city_park_supply_crate.tres", "res://data/loot/tables/flooded_mall_supply_crate.tres"]:
		var table := load(path) as LootTable
		ok = _expect(table.gear_chance > 0.0 and table.gear_chance <= 0.15, "%s: low weapon chance (%.2f)" % [path, table.gear_chance]) and ok
		for id: StringName in table.gear_pool:
			ok = _expect(Armory.get_def(id) != null, "%s: weapon %s exists" % [path, id]) and ok
	# Taking the gear slot: a new item in the bag.
	var c := (load("res://field/loot/loot_container.tscn") as PackedScene).instantiate() as LootContainer
	c.def = load("res://data/loot/containers/supply_crate.tres")
	add_child(c)
	c.add_gear(&"pistol")
	c.state = LootContainer.State.OPEN
	c._slots[0].identified = true
	var before := Bag.entries().size()
	ok = _expect(c.take(0) == 1 and Bag.entries().size() == before + 1, "taking the weapon puts it in the bag") and ok
	for e: Dictionary in Bag.entries():
		if StringName(e.get("kind", &"")) == &"item":
			Bag.remove(int(e.id))
	c.queue_free()
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
