extends Node
## Sandbox-only stand-in for Lane A's bag (A-08, systems/bag.gd) until it lands.
## Same signatures as the ones requested from Lane A, so LootContainer works with both.
## No grid here: every stack takes one cell, CELLS cells in total (design: 시작 4x5칸).
## Sandbox scenes add it as /root/Bag only when no real Bag exists.

const CELLS := 20

## [{"item_id": StringName, "count": int}], one stack per cell.
var stacks: Array[Dictionary] = []


## Puts up to `count` of the item into free space. Returns how many went in.
func try_add(item_id: StringName, count: int) -> int:
	if count <= 0 or stacks.size() >= CELLS:
		return 0
	stacks.append({"item_id": item_id, "count": count})
	return count


func count_of(item_id: StringName) -> int:
	var total := 0
	for s in stacks:
		if s.item_id == item_id:
			total += s.count
	return total


## Removes `count` of the item. Returns false (and changes nothing) if there is not enough.
func remove_item(item_id: StringName, count: int) -> bool:
	if count_of(item_id) < count:
		return false
	for i in range(stacks.size() - 1, -1, -1):
		if count <= 0:
			break
		var s := stacks[i]
		if s.item_id != item_id:
			continue
		var used := mini(count, s.count)
		s.count -= used
		count -= used
		if s.count == 0:
			stacks.remove_at(i)
	return true
