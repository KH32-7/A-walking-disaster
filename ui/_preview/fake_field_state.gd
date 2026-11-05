extends RefCounted
## Fake field HUD state for previews and tests (D-04). Same keys as FieldHud's contract.
## Numbers follow the design docs (rifle 30-round mag, medkit, 4 armour cells) but are examples.


static func make(t: float) -> Dictionary:
	var ammo := 30 - (int(t * 3.0) % 31)
	return {
		"player_name": "구조대원",
		"hp": 86.0 - fmod(t * 4.0, 60.0), "hp_max": 100.0,
		"armor": 0.75, "armor_segments": 4,
		"stamina": clampf(0.5 + 0.5 * sin(t * 0.8), 0.0, 1.0),
		"xp": 0.38, "level": 4,
		"weapons": [
			{"name": "개조 소총", "ammo": ammo, "reserve": 64, "rarity": 2},
			{"name": "쇠지렛대", "melee": true, "rarity": 0},
		],
		"weapon_index": 0,
		"reloading": ammo == 0,
		"consumables": [{"name": "구급상자", "count": 2}, {"name": "소음 미끼", "count": 1}, null, null],
		"skills": [{"key": "Q", "left": maxf(0.0, 6.0 - fmod(t, 12.0)), "max": 12.0},
			{"key": "E", "left": 0.0, "max": 8.0}],
		"mana": fmod(t * 0.05, 1.0),
		"companions": [{"name": "한만석", "hp": 0.72, "command": "따라와"}],
		"objectives": [
			{"text": "지하 전력실 전력 복구", "progress": "0/1", "main": true},
			{"text": "3층 승강기 문 열기", "progress": "구조", "main": true},
			{"text": "약품장 뒤지기", "progress": "1/2"},
		],
		"heading_deg": fmod(t * 20.0, 360.0),
		"compass_markers": [{"bearing": 300.0, "kind": &"extract", "dist": 42.0},
			{"bearing": 80.0, "kind": &"objective", "dist": 18.0}],
		"minimap": {"heading": fmod(t * 20.0, 360.0), "points": [
			{"pos": Vector2(0.55, -0.4), "kind": &"objective"},
			{"pos": Vector2(-0.8, -0.9), "kind": &"extract"},
			{"pos": Vector2(-0.12, 0.15), "kind": &"companion"},
			{"pos": Vector2(0.35, 0.5), "kind": &"monster_heard"}]},
		"dusk_left_sec": maxf(0.0, 222.0 - t),
		"prompt": {"key": "F", "label": "약품장 뒤지기"} if fmod(t, 8.0) < 4.0 else {},
		"hold": {"label": "약품장 뒤지는 중", "progress": fmod(t, 1.5) / 1.5} if fmod(t, 8.0) >= 6.0 else {},
	}
