extends RefCounted
## Onboarding ramp (사용자 요청 2026-11-07, design 12 "해금 순서", 02 초반 구역, 04 초반 밀도,
## 12 초반 가방 보호): buildings and base menus open by stage, one note for what opened, early
## monster density, the park's early line and the early bag keep. Restores GameState and Colony.

var _ok := true


func run() -> bool:
	var flags := GameState.flags.duplicate(true)
	var day := GameState.day
	var colony := JSON.stringify(Colony.save_data())
	Colony.load_data({})
	GameState.flags = {}
	GameState.day = 1
	_test_building_stages()
	_test_menus()
	_test_note()
	_test_density()
	_test_early_line()
	_test_bag()
	Colony.load_data(JSON.parse_string(colony))
	GameState.flags = flags
	GameState.day = day
	return _ok


func _expect(cond: bool, message: String) -> void:
	if not cond:
		printerr(message)
		_ok = false


func _test_building_stages() -> void:
	GameState.flags = {}
	for id: StringName in [&"bed", &"bonfire", &"lumber_yard", &"quarry", &"vegetable_garden", &"palisade", &"wooden_gate"]:
		_expect(Colony.is_unlocked(id), "시작부터 열림: %s" % id)
	for id: StringName in [&"workshop", &"carpentry_shop", &"guard_post", &"picture_sign", &"dormitory", &"kitchen"]:
		_expect(not Colony.is_unlocked(id), "처음엔 숨김: %s" % id)
	_expect(not Colony.is_unlocked(&"radio_room"), "처음부터 있는 시설은 목록에 없음")
	_expect("아직 안 열림" in (Colony.can_build(&"workshop").reasons as Array), "숨긴 건물은 지을 수 없음")
	GameState.set_flag(UnlockRules.FIRST_RESCUE_FLAG)
	_expect(Colony.is_unlocked(&"workshop") and Colony.is_unlocked(&"guard_post"), "첫 구조 뒤 정비소, 경비 초소")
	_expect(not Colony.is_unlocked(&"picture_sign"), "그림 표지판은 상가 첫 탈출 뒤")
	GameState.set_flag(&"extracted_flooded_mall")
	_expect(Colony.is_unlocked(&"picture_sign"), "상가 첫 탈출 뒤 그림 표지판")
	_expect(not Colony.is_unlocked(&"dormitory"), "숙소는 정착지 전에는 숨김")
	Colony.tier = Enums.BaseTier.SETTLEMENT
	_expect(Colony.is_unlocked(&"dormitory") and Colony.is_unlocked(&"kitchen"), "정착지에서 숙소, 부엌")
	Colony.tier = Enums.BaseTier.CAMP
	GameState.flags = {}


func _test_menus() -> void:
	GameState.flags = {}
	GameState.day = 1
	for id: StringName in [&"build", &"@stay", &"@sortie"]:
		_expect(UnlockRules.menu_open(id), "처음부터 메뉴: %s" % id)
	for id: StringName in [&"residents", &"armory", &"craft", &"journal", &"outposts"]:
		_expect(not UnlockRules.menu_open(id), "처음엔 숨긴 메뉴: %s" % id)
	GameState.set_flag(UnlockRules.FIRST_RESCUE_FLAG)
	GameState.day = 2
	_expect(UnlockRules.menu_open(&"residents") and UnlockRules.menu_open(&"armory"), "첫 구조 뒤 주민, 무기고")
	_expect(UnlockRules.menu_open(&"journal"), "2일차 일지")
	_expect(not UnlockRules.menu_open(&"craft"), "제작은 정비소나 재봉실 완공 뒤")
	Colony.tier = Enums.BaseTier.SETTLEMENT
	_expect(UnlockRules.menu_open(&"outposts"), "정착지 전초기지")
	Colony.tier = Enums.BaseTier.CAMP
	GameState.flags = {}
	GameState.day = 1


func _test_note() -> void:
	GameState.flags = {}
	GameState.day = 1
	_expect(UnlockRules.take_new_unlocks() == "", "처음 호출은 기록만")
	_expect(UnlockRules.take_new_unlocks() == "", "바뀐 게 없으면 알림 없음")
	GameState.set_flag(UnlockRules.FIRST_RESCUE_FLAG)
	var note := UnlockRules.take_new_unlocks()
	_expect("새 메뉴: 주민, 무기고" in note, "메뉴 알림: %s" % note)
	_expect("새로 지을 수 있음:" in note and " 외 4개" in note, "건물 8개는 4개 + 외 4개: %s" % note)
	_expect(UnlockRules.take_new_unlocks() == "", "같은 것은 한 번만 알림")
	GameState.day = 3
	note = UnlockRules.take_new_unlocks()
	_expect("숲이 된 도심 공원 북쪽 길이 열렸어요" in note, "3일차 공원 북쪽 알림: %s" % note)
	for ch in ["—", "·", "…"]:
		_expect(not ch in UnlockRules.note_text(["주민"], ["침상", "모닥불"], ["공원"]), "알림 글에 금지 기호")
	GameState.flags = {}
	GameState.day = 1


func _test_density() -> void:
	_expect(is_equal_approx(MonsterRules.density_mult(1), 0.5), "1일차 ×0.5")
	_expect(is_equal_approx(MonsterRules.density_mult(4), 0.75), "4일차 ×0.75")
	_expect(is_equal_approx(MonsterRules.density_mult(5), 1.0), "5일차부터 그대로")
	GameState.day = 1
	_expect(MonsterRules.scaled(MonsterRules.REGION_MAX_ALIVE) == 40, "1일차 지역 상한 40")
	_expect(MonsterRules.scaled(1) == 1, "상한은 1 아래로 안 내려감")
	GameState.day = 9
	_expect(MonsterRules.scaled(MonsterRules.REGION_MAX_ALIVE) == MonsterRules.REGION_MAX_ALIVE, "9일차 그대로")
	GameState.day = 1


func _test_early_line() -> void:
	var park := RegionDef.load_def(&"city_park")
	_expect(is_equal_approx(EarlyZone.closed_line(park, 1), -32.0), "공원 1일차는 z -32 선 북쪽이 닫힘")
	_expect(EarlyZone.closed_line(park, park.early_open_day) == -INF, "열리는 날부터 맵 전체")
	_expect(EarlyZone.closed_line(RegionDef.load_def(&"flooded_mall"), 1) == -INF, "상가는 처음부터 전체")


func _test_bag() -> void:
	_expect(FieldState.early_bag_kept(1) and FieldState.early_bag_kept(FieldState.EARLY_KEEP_BAG_DAYS), "1~3일차 가방 유지")
	_expect(not FieldState.early_bag_kept(FieldState.EARLY_KEEP_BAG_DAYS + 1), "4일차부터는 평소대로")
