class_name MonsterPack
extends RefCounted
## A group of monsters that wander together and alert each other (B-07).
## Design reference: docs/design/04-monsters.md "무리"

var members: Array[Monster] = []


func add(monster: Monster) -> void:
	if not members.has(monster):
		members.append(monster)
	monster.pack = self


func remove(monster: Monster) -> void:
	members.erase(monster)


## First alive member that can move. Followers wander around it.
func leader() -> Monster:
	for m in members:
		if is_instance_valid(m) and not m.is_dead() and m.can_move():
			return m
	return null


## One member started chasing: the rest of the pack becomes suspicious.
func alert(caller: Monster, point: Vector3) -> void:
	for m in members:
		if m != caller and is_instance_valid(m):
			m.pack_alert(point)
