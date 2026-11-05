# 레인 B — 필드

출격해서 싸우고, 줍고, 구하고, 탈출하는 모든 것. 필드 맵의 레이아웃(충돌·내비·마커)도 맡는다.
아트 배치(dressing)와 UI는 D, 아이템 스탯 계산은 A(`Armory`)가 한다.

- 소유: `field/`, `data/{classes,monsters,regions,loot}/`, `levels/field/**`(`dressing.tscn` 제외), `tests/field/`
- 이미 있는 뼈대: `FieldState` 오토로드
- 개발 장소: `field/_sandbox/` 씬. `main.tscn`·다른 레인 씬은 열어서 저장하지 않는다.

## 체크리스트

- [ ] **B-01** 필드 샌드박스 + 그레이박스 테스트 맵 · M0
- [ ] **B-02** 필드 마커 씬 세트 · M0
- [x] **B-03** 플레이어 컨트롤러 · M1
- [x] **B-04** 쿼터뷰 카메라 + 조준 · M1
- [x] **B-05** 소음 시스템 · M1
- [x] **B-06** 무기 런타임 + 피해 공식 · M1
- [x] **B-07** 마물 공통 AI + 데모 마물 3종 · M1
- [x] **B-08** 루팅 컨테이너 + 루트 테이블 · M1
- [x] **B-09** 탈출 + 출격 결과 · M1
- [ ] **B-10** 구조 이벤트 3종 + 호위 · M1
- [ ] **B-11** 쓰러짐·유실물·고립 · M1
- [ ] **B-12** 침수 상가 레이아웃 · M1
- [ ] **B-13** 클래스 3종 스킬·패시브·숙련 · M2
- [ ] **B-14** 상태 이상 · M2
- [ ] **B-15** 마법 무기 런타임 (속성·정수 효과·조합·마력·해방) · M2
- [ ] **B-16** 소모품 6종 · M2
- [ ] **B-17** 동행 주민 전투 AI · M2
- [ ] **B-18** 마물 전체 목록 + 정예 + 드롭 · M2
- [ ] **B-19** 첫 보스 (고목 거인) + 보스 공통 · M2
- [ ] **B-20** 경험이 여는 길 · M2
- [ ] **B-21** 밤 시간·해질녘 · M2
- [ ] **B-22** 긴급 귀환 · M2
- [ ] **B-23** 기지 방어전용 전투 컴포넌트 제공 · M2
- [ ] **B-24** 공원 레이아웃 + 지역 데이터 5곳 · M2
- [ ] **B-25** 나머지 보스 4종 + 지역 레이아웃 3곳 · M3

---

### B-01 필드 샌드박스 · M0
- 만들 것: `field/_sandbox/field_sandbox.tscn` (바닥·벽·엄폐물 CSG, 조명, 디버그 정보). A의 오토로드가 아직 비어 있으면 `_sandbox/stubs/`의 가짜 스탯으로 돌린다.
- 완료 조건: 이 씬만 F6으로 실행해 이후 모든 B 태스크를 확인할 수 있다.

### B-02 필드 마커 씬 세트 · M0 (D와 C가 기다림)
- 만들 것: `field/markers/` — `PlayerSpawn`, `ExtractPoint`(type·대기 시간·소음), `LootSpot`(컨테이너 종류), `MonsterNest`(계열·간격·상한), `RescueSpot`(태그), `HiddenRoute`(필요 특성·두 지점), `BossArena`, `Recording`. 에디터에서만 보이는 아이콘·기즈모.
- 완료 조건: D가 dressing 작업 때 마커가 어디 있는지 보인다. 게임 실행 시 마커는 안 보인다.
- 참고: `docs/design/02-field.md` "맵 구조", "데이터 정의"

### B-03 플레이어 컨트롤러 · M1
- 만들 것: `field/player/player.tscn` (CharacterBody3D). 이동 4.5 / 달리기 7.0 / 조준 이동 2.5 m/s, 스태미나 100(초당 25, 0.8초 지연), 구르기 3.5m·무적 0.3초·스태미나 25. 입력은 `InputSetup` 액션 이름만 쓴다. 토글 조준·토글 달리기는 `Settings`를 따른다.
- 완료 조건: 수치가 `data/classes/` 또는 상수 한곳에 모여 있다. 키보드·게임패드 둘 다 동작.
- 참고: `docs/design/03-combat-classes.md` "플레이어 기본 수치"

### B-04 쿼터뷰 카메라 · M1
- 만들 것: 내려다보는 각 약 55°, 거리 3단계, 마우스 커서 → 지면 레이캐스트로 조준점, 게임패드는 오른쪽 스틱 방향 + 조준 보조(Settings `aim_assist`). 실내 진입 시 지붕 투명화 훅(D가 dressing에서 쓸 그룹 이름 정하기).
- 참고: `docs/design/16-art-sound.md` "아트 방향"

### B-05 소음 시스템 · M1
- 만들 것: `field/noise/noise_emitter.gd` 컴포넌트, 반경 표(02 탭)를 데이터로, 방어구 소음 보정(`Armory`), 비 오는 날 −25%, `EventBus.noise_emitted` 발신, 반경 안 마물에게 전달. 디버그 링(샌드박스용). **화면에 보이는 정식 링 연출은 D-05**.
- 완료 조건: 조준 걷기 0m, 달리기 8m, 권총 15m가 정확히 나온다(테스트).
- 참고: `docs/design/02-field.md` "소음"

### B-06 무기 런타임 + 피해 공식 · M1
- 만들 것: 근접(3타 콤보, 막기, 완벽한 막기, 뒤치기), 사격(확산·연사·조준·탄약·재장전, 엄폐 −50%), 피해 공식 D = A × (1+0.03M) × P × E × C × 100/(100+R). A는 `Armory.get_item_stats().damage`로, 등급·강화(1+0.06U)·부가 옵션·내구도가 이미 반영돼 있다. 무기 스탯은 `Armory.get_item_stats()`에서만 읽는다. 투사체는 레이어 5·6.
- 완료 조건: 공식 단위 테스트. 권총·소총·단검·마체테·곤봉·파이프 6종이 샌드박스에서 동작.
- 참고: `docs/design/03-combat-classes.md` "근접 전투", "사격", "피해 공식", `05-gear.md` "무기 기본형"

### B-07 마물 공통 AI + 데모 3종 · M1
- 만들 것: `field/defs/monster_def.gd`, `field/monsters/monster_base.tscn`, 상태 머신(잠듦·배회·의심·조사·추적·공격·귀환), 청각(소음 × 청각 배율)·시각(부채꼴), 무리 전파, 둥지 스폰(3분마다, 상한 40), 대상 우선순위, 발광 핵 약점(×2). 데모 3종: 덩굴손, 포자 꽃망울(경보형 비명), 늪 덩어리(분열).
- 완료 조건: 머리 위 의심·추적 상태를 신호로 내보낸다(D-05가 표시). `monster_killed` 발신.
- 참고: `docs/design/04-monsters.md`

### B-08 루팅 · M1
- 만들 것: `field/loot/` 컨테이너(열기 시간, 칸당 0.5초 확인, 이동 시 취소, 잠금·따기 소음 6m, Settings `instant_loot`), `field/defs/loot_table.gd`, `data/loot/`. 주운 것은 A-08 가방 API로 넣는다. 가방 화면은 D-08.
- 참고: `docs/design/02-field.md` "루팅", `11-economy.md` "출격 1회 기대 수익"

### B-09 탈출 + 출격 결과 · M1
- 만들 것: 활성 탈출 지점 2곳 무작위, 일반(5초)·조건부(발전기·열쇠·배터리), 6m 밖 동행자 "두고 갈까요?"(D가 확인창, B는 신호·결과 처리), `EventBus.sortie_ended(result)` 형식 확정(A-05와 합의).
- 참고: `docs/design/02-field.md` "탈출"

### B-10 구조 이벤트 + 호위 · M1
- 만들 것: `RescueSpot`에서 구조 대상 생성(구조 대상 데이터는 C/A의 풀에서 `Colony`를 통해 받음), 유형 3종(갇힘·부상·소통 — 소통은 그림 카드 3지선다, 화면은 D), 따라오기·숨기 명령, 이동 방식 5종(보행·느린 보행·휠체어·부축·아이), 휠체어는 계단 불가(내비 레이어로 구분), 쓰러짐 30초. 탈출하면 `rescue_completed`.
- 참고: `docs/design/02-field.md` "구조 이벤트", "함께 나오기"

### B-11 쓰러짐·유실물·고립 · M1
- 만들 것: `player_downed`, 가방 비우기(A-08), 장착 장비를 유실물로 `FieldState.lost_gear`에 기록, 다음 출격 1회 회수, 동행자는 `companion_stranded`. 보호 모드(`keep_bag_on_down`) 반영.
- 참고: `docs/design/01-flow-time.md` "실패 처리", `02-field.md` "고립과 유실물"

### B-12 침수 상가 레이아웃 · M1
- 만들 것: `levels/field/flooded_mall/` 의 `flooded_mall.tscn`(조립), `layout.tscn`(CSG 그레이박스, 충돌, 내비메시, 마커). `dressing.tscn`은 D가 만든다(비어 있어도 조립 씬이 동작).
- 완료 조건: `SceneRouter.go_to_field({"region_id": &"flooded_mall"})`로 들어가 탈출까지 할 수 있다.
- 참고: `docs/design/02-field.md` "지역", "맵 구조"

### B-13 클래스·스킬·숙련 · M2
- 만들 것: `field/defs/class_def.gd`, `skill_def.gd`, `data/classes/` 3종, 스킬 Q·E, 패시브(숙련 5·10), 숙련 경험치(보조무기 50%)는 `A-11`의 `add_mastery`로 저장.
- 참고: `docs/design/03-combat-classes.md` "클래스"

### B-14 상태 이상 · M2
- 출혈·경직·넉백·방어 파괴·둔화·속박·감전·젖음. `field/defs/status_effect.gd`.

### B-15 마법 무기 런타임 · M2
- 만들 것: 적중 시 `Armory.get_item_stats()`의 `element`·`essence_effects`·`combo`를 읽어 발동, 속성 배율(`Enums.element_multiplier`), 마력 게이지(근접 +5, 사격 +3, 처치 +10), 정수 해방(X, 클래스별 3종, 소음 15m). 이펙트는 `Fx.spawn`.
- 의존: A-10
- 참고: `docs/design/06-magic-essence.md`

### B-16 소모품 · M2
- 구급상자·붕대·진통제·소음 미끼·섬광탄·투척 폭탄. 참고: `03-combat-classes.md` "소모품"

### B-17 동행 주민 전투 AI · M2
- 만들 것: 모드 3종(공격적·신중·엄호), 체력 80 + 힘 × 5 + 방어구, 적성 배율, 스킬 Q(쿨 ×1.5), 쓰러짐·일으키기. 주민 능력치는 `Colony.get_resident()`, 장비는 `Armory`에서 읽는다.
- 참고: `docs/design/03-combat-classes.md` "동행 주민 전투"

### B-18 마물 전체 + 정예 + 드롭 · M2
- 04 탭 일반 마물 전부, 정예 변형(체력 ×3, 공격 ×1.5, 패턴 1개 추가), 드롭(정수·계열 재료·장비), 습격 전용 2종(C가 쓰도록 `data/monsters/`에 둠).

### B-19 첫 보스 + 보스 공통 · M2
- 보스 공통(페이즈, 범위 예고 = 모양 + 색, 3일 리스폰, 최초 처치 보상), 고목 거인(정수 공방 설계도 보상).

### B-20 경험이 여는 길 · M2
- `HiddenRoute` 마커 + 일행 특성 검사 → 지도·월드에 경로 노출 신호.

### B-21 밤·해질녘 · M2
- 12분 해질녘 신호, 15분부터 스폰 ×1.5·정예·시야 −30%·드롭 ×1.3.

### B-22 긴급 귀환 · M2
- `raid_warning`(낮) 수신 → 선택(D가 화면) → 가장 가까운 탈출 지점 경로, 대기 0초, `emergency_return_requested`.

### B-23 방어전용 전투 컴포넌트 · M2 (C-17이 기다림)
- 플레이어·무기·마물이 기지 맵에서도 동작하도록 의존성을 끊고, C가 인스턴스할 수 있는 씬 목록과 사용법을 `field/README.md`에 적는다.

### B-24 공원 + 지역 데이터 · M2
- `field/defs/region_def.gd`, `data/regions/` 5곳(해금 조건, 계열 비율, 루트 테이블), 공원 레이아웃.

### B-25 나머지 보스·지역 · M3
- 병원·업무지구·항구 레이아웃, 보스 4종.
