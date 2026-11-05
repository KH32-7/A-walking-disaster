# field/ 컴포넌트를 기지 방어전에서 쓰기 (B-23)

C-17(직접 방어전)이 기지 맵에서 B의 전투 부품을 그대로 쓰기 위한 안내다. 고칠 것은 C의 씬과 스크립트뿐이고,
B 파일은 인스턴스하거나 공개 변수·함수·신호만 쓴다. 예시는 `field/_sandbox/b23_defense_test.tscn`(F6)에 있다.

## 핵심: 필드 규칙 끄기

필드에서만 해야 하는 일(쓰러지면 가방 소실, 장착 장비 유실물, 동행 고립, 출격 시계, 출격 결과, 무전의 "같은 지역 3번 쓰러짐")은
전부 `EventBus.player_downed`와 동행의 고립 타이머에서 시작한다. 기지 맵에서는 아래 스위치로 그 입구를 막는다.
`FieldState`, `ExtractionManager`, `RescueManager`, `CompanionManager`, `MonsterSpawner`, `RoamingSpawner`는 기지 맵에 두지 않는다.

| 부품 | 스위치 | 끄면 달라지는 것 |
|---|---|---|
| `Player` | `field_rules = false` (export, 씬 인스턴스에서 설정) | 쓰러질 때 `Player.downed`만 보낸다. `EventBus.player_downed`가 없으니 가방·장비·FieldState·출격 결과·라우터가 그대로다. HUD 상태(`hud_state()`)에 해 질 녘 타이머가 빠진다. |
| `FieldCompanion` | `field_rules = false`, `guard_post = <Node3D>` (add_child 전에) | 쓰러져도 30초 고립 타이머가 돌지 않는다(일으킬 때까지 쓰러진 채, `companion_stranded` 없음). 플레이어 대신 `guard_post` 곁을 지킨다. |
| `Monster` | `raid_goal = <Vector3>` (add_child 전에) | 습격 마물이 된다(`is_raider()`). 집으로 돌아가지 않고, 할 일이 없으면 `raid_goal`로 행진하고, 기지 내비메시를 따라 걷고, 길을 막는 습격 구조물을 친다. |

마물 드롭(필드 가방용 더미)을 끄려면 `drop_mult = 0.0`. 방어전 보상은 C가 정한다.

## 씬 목록

| 씬 | 쓰는 법 |
|---|---|
| `field/player/player.tscn` | 인스턴스하고 `field_rules = false`. 위치는 `PlayerSpawn` 마커로. 무기(`Weapons`, WeaponHolder)·클래스 스킬·상태 이상·소모품이 같이 온다. |
| `field/camera/field_camera.tscn` | 인스턴스하고 `target`에 플레이어. 지붕 투명화는 `IndoorZone` + 그룹 `field_roof`(기지 layout이 이미 씀). |
| `field/companion/field_companion.tscn` | 경비 주민. 아래 예시처럼 `setup()` 후 add_child. |
| `data/monsters/<id>.tres`의 `scene` | 습격 마물. `def.scene.instantiate()` 후 `def`, `raid_goal`, 위치를 넣고 add_child. 습격 전용은 `root_crusher`(뿌리 파쇄자), `debris_ram`(잔해 충차). 나머지 무리는 필드 마물 그대로. |

## 플레이어

- 신호: `downed()`, `health_changed(current, maximum)`, `stamina_changed`, `move_state_changed`.
- 읽기: `is_downed`, `health`, `stats.max_health`, `hud_state()`(D-14 방어전 HUD도 같은 키).
- 피해: `take_damage(amount, info)`. 마물이 부른다.
- 소음: 걷기·달리기·사격이 `EventBus.noise_emitted`로 나가고, 기지의 습격 마물도 그 신호를 직접 듣는다.
- 무기 탄약과 소모품은 `Bag`에서 꺼낸다. 출격 뒤 가방은 기지 창고로 비워지므로, 방어전에서 무엇을 들게 할지는 C·A가 정한다
  (예: 시작할 때 `Bag.take_from_storage`, 끝나면 `Bag.unload_to_base()`). 기본 권총(`pistol`)은 탄이 무한이다.
- 쓰러진 플레이어를 다시 일으키는 함수는 아직 없다. 방어전이 끝나면 기지 씬을 다시 불러오는 것을 전제로 한다.

## 경비 주민 (FieldCompanion)

```gdscript
var guard: FieldCompanion = preload("res://field/companion/field_companion.tscn").instantiate()
guard.setup(resident_id, Colony.get_resident(resident_id))   # 능력치·특성·적성
guard.field_rules = false
guard.guard_post = post_marker          # 초소·문·대피소 앞 Node3D. 파 사이에 바꿔도 된다.
guard.position = post_marker.global_position
add_child(guard)
```

- 무기·방어구는 `Armory`에서 주민 id로 읽는다(MAIN, 없으면 SUB). 무기가 없으면 싸우지 않고 자리만 지킨다.
- 체력 80 + 힘 x 5 + 방어구. 모드(`set_mode`)는 공격적·신중·엄호. 경비는 공격적(기본)을 권한다.
- 신호: `downed()`, `revived()`, `attacked(target)`. 상태: `state`(`State.ACTIVE` / `DOWNED`), `health`, `max_health`.
  플레이어가 F를 3초 눌러 일으킬 수 있다. 끝까지 쓰러진 경비의 부상 처리는 C가 한다.
- 레이어 3(ally)에 있어서 마물이 노린다. 쓰러지면 레이어 7로 바뀌어 마물이 놓는다.

## 습격 마물 (Monster)

```gdscript
var m := def.scene.instantiate() as Monster
m.def = def
m.raid_goal = gather_point            # 행진 목표: 대피소 앞, 기지 한가운데 등
m.drop_mult = 0.0
m.position = spawn_point.global_position + scatter   # RaidSpawnPoint, spread_radius
m.died.connect(_on_raider_died)       # 파 처치 집계
add_child(m)
```

- 노리는 순서: 보이는 플레이어(쓰러진 플레이어는 건너뜀) > 레이어 3 몸체(경비, 주민) > 길을 막는 구조물.
  소리를 들으면 필드처럼 의심하고 찾아간다(`EventBus.noise_emitted`). 주민이 소리를 내게 하려면 그 신호의 source를 주민 노드로.
- `raid_goal`은 언제든 바꿔도 된다. 잔해 충차(`def.charges_gates`)는 남은 문 중 가장 가까운 곳을 먼저 향한다.
- 이동은 마물이 있는 월드의 내비게이션 맵(`base_school/layout.tscn`이 굽는 것)을 따른다. 길이 막혀 끝나면 목표로 곧장 걸어
  앞을 막는 구조물을 친다. 내비메시를 다시 굽지 않아도, 나중에 지은 벽·문은 이렇게 부수고 지나간다.
- 신호: `died(monster)`, `damaged(amount, info)`, `attack_landed(target, info)`(구조물을 칠 때도), `state_changed`.
  처치하면 필드처럼 `EventBus.monster_killed`가 나가고 `Progression`이 처치 경험치를 준다.
- 분열(늪 덩어리) 자식도 `raid_goal`을 물려받는다.

### C가 만드는 노드에 필요한 것

**구조물**(벽, 목책, 문, 바리케이드, 함정 등 마물이 부술 수 있는 것)

- 충돌 레이어 1(world) 몸체. 몸체 자신이나 그 부모가 그룹 `RaidMarch.STRUCTURE_GROUP`(`raid_structures`)에 있고
  `take_damage(amount: float, info: Dictionary)`가 있다.
- 문·바리케이드는 그룹 `RaidMarch.GATE_GROUP`(`raid_gates`)에도 넣는다.
- 부서지면 그룹에서 빼거나 노드를 지운다. 마물은 그 뒤로 그것을 치지 않는다.
- 피해 판정은 C가 한다. `info`에 들어오는 값:
  `source`(Monster), `monster_id`, `element`(계열), `structure_damage_mult`(뿌리 파쇄자 3.0: 벽·목책일 때 C가 곱한다),
  `charges_gates`(잔해 충차 true). `amount`는 마물 공격력(정예 배율 포함)이다.

**주민**(경비가 아닌 사람)

- 충돌 레이어 3(ally) 몸체에 `take_damage(amount: float, info: Dictionary)`. 마물이 보면 쫓아와 친다.
  `info`는 플레이어가 받는 것과 같다(`source`, `element`, `monster_id`, 상태 이상 `status`).
- 대피했거나 쓰러져서 더는 노릴 수 없으면 레이어 3을 끈다.

## 하지 않는 것

- 승패, 파 진행, 20초 준비, 5분 버티기, 자동 판정 넘기기, 함정 재설치는 C-17이 한다.
- 방어전 HUD는 D-14(`Player.hud_state()`, 마물·동행 신호를 읽음).
- 습격 무리 구성(강도 → 마물 포인트)과 스폰 위치는 C가 정한다. B는 `MonsterDef.tier`(습격 전용은 `SIEGE`)와 데이터만 둔다.
