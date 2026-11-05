# 공용 계약

레인끼리 맞물리는 지점은 이 문서에 적힌 것뿐이다. 바꾸려면 A에게 PR을 보내고, 영향받는 레인이 같은 PR을 확인한다.
**추가는 쉽게, 변경·삭제는 모든 사용처를 같이 고칠 때만.**

## 오토로드 (project.godot에 등록 완료, 순서대로 로드)

| 이름 | 파일 | 소유 | 하는 일 |
|---|---|---|---|
| `EventBus` | `core/event_bus.gd` | A | 레인 간 신호 |
| `Settings` | `core/settings.gd` | A | 접근성·난이도 값 |
| `GameState` | `core/game_state.gd` | A | 날짜·계절·단계·플래그 |
| `InputSetup` | `core/input_setup.gd` | A | 기본 입력 액션 등록 |
| `SaveSystem` | `core/save_system.gd` | A | 저장·불러오기 (레인별 provider) |
| `Economy` | `systems/economy.gd` | A | 창고 자원 |
| `Armory` | `systems/armory.gd` | A | 장비 인스턴스, 누가 무엇을 장착했나, 최종 스탯 |
| `Bag` | `systems/bag.gd` | A | 필드 가방 격자 + 안전 주머니 |
| `Radio` | `ai/radio.gd` | A | 방송실 지기 무전 (트리거·문장) |
| `FieldState` | `field/field_state.gd` | B | 필드 쪽 영속 상태 |
| `Colony` | `base/colony.gd` | C | 주민·건물·관계·습격 위협도 |
| `Audio` | `audio/audio.gd` | D | 효과음·음악 재생 |
| `Fx` | `vfx/fx.gd` | D | 이펙트 생성 |
| `UI` | `ui/ui.gd` | D | 화면 열고 닫기, HUD |
| `SceneRouter` | `core/scene_router.gd` | A | 기지↔필드 씬 전환, 하루 흐름 진행 |
| `DebugConsole` | `core/debug/debug_console.gd` | A | 개발용 치트 콘솔(백틱 키). 디버그 빌드에서만 동작 |
| `Quests` | `systems/quests/quests.gd` | A | 퀘스트·개인 요청·무전 소문 진행과 보상 (스토리 플래그는 `GameState`) |

`_mcp_game_helper`는 Godot AI 플러그인 것이라 건드리지 않는다.

## 신호 (`EventBus`)

정의는 [core/event_bus.gd](../../core/event_bus.gd)가 기준이다. 누가 쏘는지:

| 신호 | 쏘는 레인 | 주로 듣는 레인 |
|---|---|---|
| `day_started`, `phase_changed`, `flow_state_changed`, `weather_changed`, `sortie_started`, `sortie_ended`, `evening_settled` | A | 전부 |
| `noise_emitted`, `monster_killed`, `player_downed`, `rescue_completed`, `companion_stranded`, `extraction_completed`, `emergency_return_requested` | B | A·C·D |
| `resident_joined/left/died`, `building_completed/damaged`, `relationship_changed`, `night_event_started`, `raid_warning/started/resolved` | C | A·B·D |
| `resources_changed`, `item_added/removed`, `equipment_changed`, `bag_changed` | A | D |
| `notification_posted` | 누구나 | D |
| `radio_message`, `journal_entry_added` | A | D |
| `settings_changed`, `game_saved`, `game_loaded` | A | 전부 |
| `quest_started`, `quest_updated`, `quest_completed`, `quest_failed` | A | D(퀘스트 기록)·C(공동체) |

## 공개 함수 (다른 레인이 호출해도 되는 것)

시그니처는 각 오토로드 파일에 있다. 아직 구현 전인 것은 `TODO(태스크ID)`로 표시돼 있고, 시그니처는 그대로 유지한다.

- **GameState**: `day`, `phase`, `flow_state`, `weather`, `is_raining()`, `season()`, `has_flag()`, `set_flag()`, `start_next_day()`, `set_phase()`, `set_flow_state()` (SceneRouter 전용)
- **Economy**: `get_amount(id)`, `can_afford(cost)`, `apply(changes)`, `apply_detailed(changes)`(버려진 양 보고), `get_def(id)`, `storage_cap()`, `capped_total()`, `free_space()`, `uses_cap(id)`, `set_cap_bonus(bonus)`(C: 창고 건물)
- **Armory**: `get_equipped(owner_id, slot)`, `get_item_stats(item_uid)`, `equip(owner_id, slot, uid)`, `unequip(owner_id, slot)`,
  `list_equipped(owner_id)`, `list_storage(slot)`, `can_go_in_slot(def_id, slot)`, `get_combat_class(owner_id)`,
  `get_owner_summary(owner_id)`(방어력 합, 방어구 소음 합(상한 +3m), 최대 체력, 이동 배율, 가방 격자), `create_item(def_id, rarity, rng)`,
  `remove_item(uid)`, `get_item(uid)`(읽기 전용), `get_def(def_id)`, `wear(uid, amount)`(B: 내구도), `set_lost(uid, lost)`(B: 쓰러짐·회수).
  owner_id는 `Armory.PLAYER_ID` 또는 주민 id. 무기고 보관은 `STORAGE_ID`, 유실물은 `LOST_ID`.
  **`get_item_stats().damage`·`defense`는 등급·강화·부가 옵션·내구도까지 반영된 최종값**이다. B의 피해 공식에서 `(1+0.06U)`를 다시 곱하지 않는다.
- **Bag**: 루팅(B-08)용 `try_add(id, n) -> 들어간 양`, `count_of(id)`, `remove_item(id, n) -> bool`(이슈 #6). `resize_for_player()`(출격 준비), `add_resource(id, n) -> 못 넣은 양`, `add_item(uid) -> entry_id`, `take_from_storage(id, n)`,
  `move(entry_id, pos, rotated, area)`, `remove(entry_id, amount)`, `consume(id, n)`, `count(id)`, `entries(area)`, `entry_at(cell, area)`,
  `can_place(size, pos, rotated, area)`, `is_cell(cell, area)`, `unload_to_base()`(탈출: 자원→Economy, 장비→무기고),
  `lose_contents()`(쓰러짐: 안전 주머니 제외 소실. 보호 모드 `keep_bag_on_down`이면 B가 호출하지 않음).
  영역은 `Bag.AREA_BAG` / `Bag.AREA_POCKET`(2칸). 가방 속 장비의 Armory 소유자는 `Armory.BAG_ID`.
- **Radio**: `say(trigger_id, context, priority) -> bool`(쿨다운·빈도·1회 제한에 막히면 false), `set_combat(active)`(B: 전투 중 한 줄),
  `morning_broadcast()`. 트리거 id는 `data/radio/`: B가 부르는 것 `low_ammo`, `low_health`, `noise_high`, `rescuee_low_health`,
  `no_progress {direction}`, `dusk {minutes}`. 아침 방송·습격 징후·60초 경보·낮 습격 예상(`Colony.predict_raid`)·같은 지역 3번 쓰러짐은
  Radio가 신호(`day_started`, `raid_warning`, `sortie_started`, `player_downed`)를 듣고 알아서 말한다. LLM 없음.
- **Settings**: `get_value(key)`, `set_value(key, value) -> bool`(모르는 키·틀린 타입 거부), `apply_preset(id, new_game)`, `matching_preset()`,
  `reset_to_defaults(include_difficulty)`. 키 목록은 `Settings.DEFAULTS`. 난이도 프리셋은 `story`·`normal`·`hard`·`hardcore`
  (`Settings.PRESETS`), 항목을 따로 바꾸면 `difficulty`가 `custom`이 된다. 하드코어는 새 게임에서만 고른다.
  접근성·소리 설정은 `user://settings.cfg`에 바로 저장되고, 난이도 항목은 게임 저장(`difficulty` provider)에도 들어간다.
- **SaveSystem**: `register_provider(key, provider)`, `save_slot(slot) -> bool`, `load_slot(slot) -> bool`, `has_slot(slot)`, `delete_slot(slot)`, `slot_info(slot)`(불러오기 화면용), `autosave()`, `save_suspend()`, `has_suspend()`, `load_suspend()`, `current_slot`
- **SceneRouter**: 하루 흐름의 유일한 진행자. `state()`, `stayed_today`(C: 머무르기 날 생산 +20%), `last_sortie_result`, `last_evening_report`.
  - D(화면): `start_new_game(slot, difficulty)`, `load_game(slot)`, `load_suspended()`, `quit_to_title()`, `open_sortie_prep()`,
    `cancel_sortie_prep()`, `go_to_field(loadout)`, `stay_at_base()`, `end_stay()`, `finish_result()`, `confirm_evening()`, `finish_night()`.
  - C(기지): `start_day_raid(raid)`, `end_day_raid()`, `start_night_event(event_id, participants)`, `end_night_event()`.
  - B(필드)는 함수를 부르지 않고 신호만 보낸다: `extraction_completed`·`player_downed`(쓰러짐 처리—가방 비우기·유실물—를 끝낸 뒤),
    `rescue_completed`, `companion_stranded`, `emergency_return_requested`. 라우터가 이것으로 `sortie_ended` 결과를 만든다:
    `{"extracted", "region_id", "loot": Bag.unload_to_base() 결과, "rescued", "stranded", "xp"}`.
  - 허용되지 않은 전환은 거부(false + 오류). 디버그·테스트용 `advance()`가 기본 경로로 한 단계 진행.
  - main.tscn의 `World` 아래에 기지/필드 씬을 바꿔 넣는다. 씬 파일이 아직 없으면 비워 둔다.
- **Colony**: `get_resident(id)`, `active_resident_ids()`, `base_noise()`, `threat`, `tier`,
  `population()`, `bed_count()`, `free_beds()`, `add_resident(profile) -> id`(구조자 입주도 이것), `assign_bed(resident_id, bed_id)`,
  `settle_day()`, `roll_raid(time)`, `resolve_raid(raid, mode)`, `predict_raid(raid)` (형식은 아래 "하루 정산과 습격")
- **FieldState**: `in_sortie()`, `lost_gear`
- **Audio**: `play(event_id, position)`, `set_music_state(state)`
- **Fx**: `spawn(effect_id, position, params)`
- **UI**: `open(screen_id, args)`, `close(screen_id)`
- **DebugConsole**: `register(name, callable, help)`, `execute(line)`, `is_open()`, `godmode`(B가 읽음).
  각 레인은 자기 스크립트에서 `register`로 명령을 추가한다(콘솔 파일은 고치지 않음). 같은 이름으로 다시 등록하면 교체된다.
  `raid`, `resident`는 C가, `give`는 A-07이 교체할 자리표시 명령이다. 출시 빌드에서는 등록·실행이 모두 무시된다.
- **Quests** (A-13): `start(quest_id, giver_id)`, `advance(quest_id, objective_id, amount)`(C: 공동체 퀘스트), `complete(quest_id)`, `fail(quest_id, reason)`,
  `get_status(quest_id)`(-1 = 시작 전, `Quests.Status`), `is_active()`, `is_completed()`, `days_left()`, `get_def()`, `active_quests()`(D: 퀘스트 기록),
  `active_field_objectives(region_id)`(B: 필드 목표 `{"quest_id", "objective_id", "kind": &"visit"|&"recover"|&"rescue", "region_id", "marker", "target_id", "count", "remaining", "text"}`).
  진행은 신호로만 한다: 지역 방문·데려가기(`sortie_ended` 탈출), 아이템 회수(`sortie_ended`의 loot), 사람 데려오기(`rescue_completed`의 profile `id`),
  기지 제작(`building_completed`), 특정 날 방어(`raid_resolved`). 유품은 `data/resources/`의 자원(예: `keepsake_plane`)이라 B는 `marker` 자리에 줍는 물건을 두고
  `Bag.try_add`로 넣기만 하면 된다. 보상의 신뢰도는 `Colony.add_trust(resident_id, amount)`(C에 요청)를 부른다. 무전 소문은 Radio 트리거 `quest_rumor`로 말한다.

새 공개 함수가 필요하면 그 오토로드의 소유 레인이 추가하고 여기에 한 줄 적는다.

## 하루 단계와 흐름 상태

- `Enums.Phase`(5개)는 기획 01 "데이터 정의"의 큰 단계이고 저장된다. 게임 규칙(생산, 습격 판정 등)은 이것만 본다.
- `Enums.FlowState`는 기획 01 "게임 상태" 표의 세부 상태다(출격 준비, 결과, 낮 습격, 밤 습격·이벤트 등).
  UI가 화면을 고를 때 쓴다. 바꾸는 쪽은 `SceneRouter`뿐이고, 각 FlowState가 어느 Phase에 속하는지는
  `GameState.PHASE_OF_FLOW`에 있다. 바뀔 때 `flow_state_changed`가 먼저, Phase가 바뀌면 `phase_changed`가 뒤따른다.

## 하루 정산과 습격 (C ↔ A-05)

`Colony.settle_day() -> Dictionary` (C-05):

```
{
  "changes":  {res_id: int},       # 순변화. A가 Economy.apply_detailed()에 넘김
  "produced": {res_id: int},
  "consumed": {res_id: int},
  "morale":   {resident_id: int},  # 오늘 변화량
  "events":   [{"type": StringName, "resident_id": StringName, "text": String}]
}
```

순서(A-05): `Colony.settle_day()` → `Economy.apply_detailed(report.changes)` → `report["discarded"]`(창고 한도로 버린 양) 추가 →
`EventBus.evening_settled.emit(report)`. 주민 상태(배고픔·피로·사기)는 `settle_day()` 안에서 C가 갱신하고, Economy는 C가 직접 바꾸지 않는다.

`Colony.roll_raid(time: Enums.RaidTime) -> Dictionary` (C-08):
`{"occurs": bool, "raid_id": StringName, "time": Enums.RaidTime, "type": StringName, "directions": Array[StringName],
"strength": float, "target": StringName (&"base" 또는 전초기지 node_id), "warning_sec": float}`. `raid_warning`/`raid_started`의 info도 이 Dictionary.

`Colony.resolve_raid(raid, mode: Enums.RaidMode) -> Dictionary`:
`{"outcome": Enums.RaidOutcome, "damage": Dictionary, "casualties": Array, "summary": Array[String]}`, `raid_resolved`를 보낸다.
직접 방어전(C-17)도 끝나면 같은 형식.

`Colony.predict_raid(raid) -> Dictionary`: `{"ratio_min": float, "ratio_max": float, "likely": Enums.RaidOutcome}` (A-14 무전의 예상 결과 구간).

## 날씨

`GameState.weather`(`Enums.Weather`), `GameState.is_raining()`. 매일 아침(`start_next_day`) 계절별 확률로 굴리고
`EventBus.weather_changed`를 보낸다. 비 오는 날 소음 반경 배율은 `GameState.RAIN_NOISE_MULT`(0.75). 저장은 `game` provider.

## 공용 enum

`core/enums.gd`에 기획 "데이터 정의" 표의 enum 중 여러 레인이 읽는 것을 모아 둔다:
`ResourceCategory`, `ExtractType`, `RelationFlag`, `ArrivalMethod`, `RaidTime`, `RaidMode`, `QuestType`,
`RequestType`, `EndingChoice`, `Weather` 등. 한 레인 안에서만 쓰는 enum은 그 레인의 `defs/` 스크립트에 둬도 된다.

## 저장

각 레인은 provider 하나만 등록한다(`save_data() -> Dictionary`, `load_data(Dictionary)`). 값은 JSON으로 쓸 수 있는 것만
(Object·Resource 대신 id). 키: `game`(A), `difficulty`(A, Settings의 난이도 항목), `economy`(A), `armory`(A), `bag`(A), `radio`(A), `router`(A), `field`(B), `colony`(C). D는 저장할 게임 상태가 없다
(설정은 `Settings`가 따로 저장).

- 파일은 Godot 타입 JSON(`JSON.from_native`)이라 `int`/`float`, `StringName`, `Vector3` 등이 그대로 돌아온다. Object·Resource는 안 된다.
- `load_data`는 빈 Dictionary를 받을 수 있어야 한다(파일에 그 키가 없으면 `{}`로 호출해 기본값으로 되돌림).
- 슬롯 0~2. 자동 저장은 SceneRouter가 `current_slot`에 한다: 아침 시작, 출격 직전(출격 준비 상태로 저장되어 불러오면 준비 화면),
  탈출 직후(결과 화면). 새 게임은 `SaveSystem.reset_all()`로 모든 provider를 `load_data({})`.
- 필드 중 종료는 `save_suspend()`. `load_suspend()`는 불러온 뒤 파일을 지운다.
- 저장 형식이 호환되지 않게 바뀌면 A가 `SaveSystem.SAVE_VERSION`을 올린다. 버전이 다른 파일은 불러오지 않는다.
- 키 `quests`(A, A-13): 퀘스트 상태·진행도·진행 중인 출격의 지역과 동행.

## 아이템 id 규칙

- 자원·소모품은 `data/resources/`의 id(`Economy.get_def`). 탄약은 `ammo_pistol`(권총·기관단총), `ammo_rifle`(소총·저격총),
  `ammo_shell`(산탄총). 총의 `get_item_stats()["ammo_id"]`가 어느 탄약을 쓰는지 알려준다. 소모품: `first_aid_kit`, `bandage`, `noise_lure`.
- 통조림은 따로 없다. 필드에서 나오는 식량은 `food`.
- 정수는 `essence_<element>_<grade>`(예: `essence_green_low`). 정의는 A-10, 그 전까지는 한도 없는 자원으로 취급.
- 장비는 `Armory.create_item(def_id, rarity)`로 만들고 `Bag.add_item(uid)`로 넣는다. def_id는 `data/items/`.

## 데이터(.tres)와 스키마

| 데이터 폴더 | 소유 | 스키마 위치 |
|---|---|---|
| `data/items`, `data/recipes`, `data/resources`, `data/essences`, `data/quests`, `data/radio`, `data/resident_pool` | A | `systems/defs/` |
| `data/classes`, `data/monsters`, `data/regions`, `data/loot` | B | `field/defs/` |
| `data/buildings`, `data/traits`, `data/jobs`, `data/events`, `data/raids` | C | `base/defs/` |
| `data/ui` (오디오 이벤트, 테마 값) | D | `ui/` |

스키마 필드는 기획 문서 각 탭의 "데이터 정의" 표를 따른다(`docs/design/`). id는 `StringName`, 소문자 스네이크(`vine_tendril`).

## 물리 레이어 (`Enums.LAYER_*`)

1 world · 2 player · 3 ally(주민·동행·구조자) · 4 monster · 5 player_projectile · 6 monster_projectile · 7 interactable · 8 trigger

## 맵 파일과 마커

```
levels/field/<region_id>/
  <region_id>.tscn   B  (layout + dressing을 인스턴스하는 조립 씬)
  layout.tscn        B  (충돌, 내비메시, 마커)
  dressing.tscn      D  (메시, 조명, 장식, 파티클)
levels/base/base_school/
  base_school.tscn   C
  layout.tscn        C
  dressing.tscn      D
```

- **필드 마커**(B-02, `field/markers/`): `PlayerSpawn`, `ExtractPoint`, `LootSpot`, `MonsterNest`, `RescueSpot`,
  `HiddenRoute`, `BossArena`, `Recording`.
- **기지 마커**(C-01, `base/markers/`): `BuildArea`, `ZoneMarker`, `ResourceNode`(나무·잔해), `RaidSpawnPoint`, `WorkSpot`, `OutpostNode`.
- D는 dressing을 만들 때 layout을 참고용으로 인스턴스할 수 있지만 layout을 저장하지 않는다.
  마커 위치를 바꾸고 싶으면 B·C에 요청한다.

## UI와 게임플레이의 경계

- 게임플레이 레인(A·B·C)은 `Control` 노드를 만들지 않는다. 필요한 정보는 신호와 getter로 내놓는다.
- 샌드박스에서 쓰는 디버그 UI만 예외(`_sandbox/` 안, 출시 빌드에 안 들어감).
- D는 게임 규칙을 계산하지 않는다. 예: 강화 비용은 `Armory`에 묻고, 습격 예상 결과는 `Colony`에 묻는다.
- 색만으로 구분하는 정보는 없다(등급·속성·관계는 모양이나 글을 함께).
