extends Node
## Autoload `ResidentPool`. Owner: Lane A (task A-16).
## The hand-written survivor pool (data/resident_pool/*.tres, schema ResidentTemplate).
## No LLM: the team writes and reviews every survivor by hand.
## Design reference: docs/design/15-ai-features.md "생존자 생성", "검수 규칙", 07-residents.md
##
## Only entries with `reviewed = true` that pass ResidentTemplate.validate() are ever returned.
## Profiles are fresh Dictionaries in the shape Colony.add_resident(profile) takes.
##
## Lane C / Lane B:
##   var profile := ResidentPool.draw({"access_need": Enums.AccessNeed.MOBILITY})
##   if not profile.is_empty():
##       Colony.add_resident(profile)   # marks the entry used automatically (resident_joined)
##   ResidentPool.get_profile(&"demo_carpenter")  # a fixed story survivor, used or not
##
## Filter keys for draw() / available_ids() (all optional):
##   "demo": bool, "age_stage": Enums.AgeStage, "access_need": Enums.AccessNeed,
##   "former_job": StringName, "region_id": StringName (entries with region_id &"" match any
##   region), "exclude": Array of ids.
##
## Saved as provider `resident_pool`: which entries were already used (rescued).

const POOL_DIR := "res://data/resident_pool"

## id -> ResidentTemplate (reviewed and valid only)
var templates: Dictionary = {}
## id -> ResidentTemplate that exist but are not reviewed yet (debug listing only)
var unreviewed: Dictionary = {}

var _used: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	reload()
	SaveSystem.register_provider(&"resident_pool", self)
	EventBus.resident_joined.connect(_on_resident_joined)
	# DebugConsole loads after this autoload; register once it is ready.
	_register_debug_commands.call_deferred()


# --- Public API ---------------------------------------------------------------

## Profile of a reviewed entry, whether it was used or not. {} if unknown or not reviewed.
func get_profile(id: StringName) -> Dictionary:
	var t: ResidentTemplate = templates.get(id)
	return t.to_profile() if t != null else {}


## A random unused reviewed survivor matching `filter`, or {} when none is left.
## Does not mark it used: that happens when the resident joins (or call mark_used()).
func draw(filter: Dictionary = {}) -> Dictionary:
	var ids := available_ids(filter)
	if ids.is_empty():
		return {}
	return get_profile(ids[_rng.randi_range(0, ids.size() - 1)])


## Unused reviewed ids matching `filter`, sorted.
func available_ids(filter: Dictionary = {}) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in templates:
		if not _used.has(id) and _matches(templates[id], filter):
			out.append(id)
	out.sort()
	return out


## Every reviewed id, used or not, sorted.
func reviewed_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(templates.keys())
	out.sort()
	return out


func mark_used(id: StringName) -> void:
	if templates.has(id):
		_used[id] = true


func is_used(id: StringName) -> bool:
	return _used.has(id)


## Adds one template if it is reviewed and valid. Returns the reasons it was refused (empty =
## added). Used when loading data/resident_pool; tests use it for fake entries.
func add_template(t: ResidentTemplate, banned: PackedStringArray = ResidentTemplate.load_banned_words()) -> PackedStringArray:
	if t == null:
		return PackedStringArray(["not a ResidentTemplate"])
	var errors := t.validate(banned)
	if templates.has(t.id) or unreviewed.has(t.id):
		errors.append("duplicate id '%s'" % t.id)
	if not errors.is_empty():
		return errors
	if t.reviewed:
		templates[t.id] = t
	else:
		unreviewed[t.id] = t
		errors.append("not reviewed")
	return errors


## Reloads data/resident_pool. Keeps the used flags.
func reload() -> void:
	templates.clear()
	unreviewed.clear()
	var banned := ResidentTemplate.load_banned_words()
	for file in ResourceLoader.list_directory(POOL_DIR):
		if not file.ends_with(".tres"):
			continue
		var t := load(POOL_DIR.path_join(file)) as ResidentTemplate
		var errors := add_template(t, banned)
		if not errors.is_empty() and errors != PackedStringArray(["not reviewed"]):
			push_error("ResidentPool: %s refused: %s" % [file, "; ".join(errors)])


# --- Save provider -----------------------------------------------------------

func save_data() -> Dictionary:
	var used: Array[StringName] = []
	used.assign(_used.keys())
	used.sort()
	return {"used": used}


func load_data(data: Dictionary) -> void:
	_used.clear()
	for id in data.get("used", []):
		_used[StringName(id)] = true


# --- Internals ---------------------------------------------------------------

func _matches(t: ResidentTemplate, filter: Dictionary) -> bool:
	if filter.has("demo") and t.demo != bool(filter["demo"]):
		return false
	if filter.has("age_stage") and int(t.age_stage) != int(filter["age_stage"]):
		return false
	if filter.has("access_need") and int(filter["access_need"]) not in t.access_needs:
		return false
	if filter.has("former_job") and t.former_job != StringName(filter["former_job"]):
		return false
	if filter.has("region_id") and t.region_id != &"" and t.region_id != StringName(filter["region_id"]):
		return false
	if filter.has("exclude"):
		for ex in filter["exclude"]:
			if StringName(ex) == t.id:
				return false
	return true


func _on_resident_joined(resident_id: StringName) -> void:
	# Colony keeps the profile id as the resident id, so a pool survivor joining marks itself.
	mark_used(resident_id)


func _register_debug_commands() -> void:
	DebugConsole.register(&"pool", _cmd_pool, "pool list | pool add [id] | pool reset - 생존자 풀 (A-16)")


func _cmd_pool(args: PackedStringArray) -> String:
	var sub := args[0] if args.size() > 0 else "list"
	match sub:
		"list":
			var lines := PackedStringArray(["검수 완료 %d명, 남은 %d명, 검수 대기 %d명" % [templates.size(), available_ids().size(), unreviewed.size()]])
			for id in reviewed_ids():
				var t: ResidentTemplate = templates[id]
				lines.append("  %s %s %s%s" % [id, t.name, "(사용됨)" if is_used(id) else "", " [데모]" if t.demo else ""])
			for id: StringName in unreviewed:
				lines.append("  %s %s (검수 대기)" % [id, unreviewed[id].name])
			return "\n".join(lines)
		"add":
			var profile := get_profile(StringName(args[1])) if args.size() > 1 else draw()
			if profile.is_empty():
				return "꺼낼 생존자가 없다 (검수 완료, 미사용만)"
			var rid := Colony.add_resident(profile)
			return "주민 추가: %s %s" % [rid, profile["name"]]
		"reset":
			_used.clear()
			return "생존자 풀 사용 표시를 지웠다"
	return "사용법: pool list | pool add [id] | pool reset"
