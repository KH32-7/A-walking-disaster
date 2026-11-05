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
| `Radio` | `ai/radio.gd` | A | 방송실 지기 무전 (트리거·문장) |
| `FieldState` | `field/field_state.gd` | B | 필드 쪽 영속 상태 |
| `Colony` | `base/colony.gd` | C | 주민·건물·관계·습격 위협도 |
| `Audio` | `audio/audio.gd` | D | 효과음·음악 재생 |
| `Fx` | `vfx/fx.gd` | D | 이펙트 생성 |
| `UI` | `ui/ui.gd` | D | 화면 열고 닫기, HUD |
| `SceneRouter` | `core/scene_router.gd` | A | 기지↔필드 씬 전환, 하루 흐름 진행 |

`_mcp_game_helper`는 Godot AI 플러그인 것이라 건드리지 않는다.

## 신호 (`EventBus`)

정의는 [core/event_bus.gd](../../core/event_bus.gd)가 기준이다. 누가 쏘는지:

| 신호 | 쏘는 레인 | 주로 듣는 레인 |
|---|---|---|
| `day_started`, `phase_changed`, `sortie_started`, `sortie_ended`, `evening_settled` | A | 전부 |
| `noise_emitted`, `monster_killed`, `player_downed`, `rescue_completed`, `companion_stranded`, `extraction_completed`, `emergency_return_requested` | B | A·C·D |
| `resident_joined/left/died`, `building_completed/damaged`, `relationship_changed`, `night_event_started`, `raid_warning/started/resolved` | C | A·B·D |
| `resources_changed`, `item_added/removed`, `equipment_changed` | A | D |
| `notification_posted` | 누구나 | D |
| `radio_message`, `journal_entry_added` | A | D |
| `settings_changed`, `game_saved`, `game_loaded` | A | 전부 |

## 공개 함수 (다른 레인이 호출해도 되는 것)

시그니처는 각 오토로드 파일에 있다. 아직 구현 전인 것은 `TODO(태스크ID)`로 표시돼 있고, 시그니처는 그대로 유지한다.

- **GameState**: `day`, `phase`, `season()`, `has_flag()`, `set_flag()`, `start_next_day()`, `set_phase()`
- **Economy**: `get_amount(id)`, `can_afford(cost)`, `apply(changes)`
- **Armory**: `get_equipped(owner_id, slot)`, `get_item_stats(item_uid)` (+ A-07에서 추가하는 장착/해제 함수)
- **Radio**: `say(template_id, context, priority)`
- **Settings**: `get_value(key)`, `set_value(key, value)`
- **SaveSystem**: `register_provider(key, provider)`, `save_slot(slot)`, `load_slot(slot)`
- **SceneRouter**: `go_to_base()`, `go_to_field(loadout)`
- **Colony**: `get_resident(id)`, `active_resident_ids()`, `base_noise()`, `threat`, `tier`
- **FieldState**: `in_sortie()`, `lost_gear`
- **Audio**: `play(event_id, position)`, `set_music_state(state)`
- **Fx**: `spawn(effect_id, position, params)`
- **UI**: `open(screen_id, args)`, `close(screen_id)`

새 공개 함수가 필요하면 그 오토로드의 소유 레인이 추가하고 여기에 한 줄 적는다.

## 저장

각 레인은 provider 하나만 등록한다(`save_data() -> Dictionary`, `load_data(Dictionary)`). 값은 JSON으로 쓸 수 있는 것만
(Object·Resource 대신 id). 키: `game`(A), `economy`(A), `armory`(A), `field`(B), `colony`(C). D는 저장할 게임 상태가 없다
(설정은 `Settings`가 따로 저장).

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
