# 공용 계약

기능끼리 맞물리는 공개 함수·신호의 정리다. M2 이후로 레인 구분이 없어서 누구든 고칠 수 있다.
표의 "소유" 칸과 본문의 레인 글자(A~D)는 처음 만든 쪽을 적은 기록이고, 수정 권한을 뜻하지 않는다.
**추가는 쉽게, 변경·삭제는 모든 사용처를 같이 고칠 때만.** 바꾸면 같은 PR에서 이 문서도 고친다.

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
| `Progression` | `systems/progression.gd` | A | 플레이어 레벨·경험치·특기, 클래스 숙련 저장 |
| `ResidentPool` | `systems/resident_pool.gd` | A | 손으로 쓴 생존자 풀(`data/resident_pool/`), 검수된 프로필만 꺼냄 |
| `Quests` | `systems/quests/quests.gd` | A | 퀘스트·개인 요청·무전 소문 진행과 보상 (스토리 플래그는 `GameState`) |
| `Journal` | `ai/journal.gd` | A | 생존 일지·엔딩 에필로그 (템플릿) |
| `Look` | `core/look/look.gd` | A | 화면 전체 스타일 후처리(붓터치·외곽선·색 보정) 시안과 주인공 밝은 외곽선. 값은 `data/look/look_tuning.tres`, 화면 스타일은 기본 꺼짐, 주인공 외곽선은 기본 켜짐. 전역 셰이더 값 `toon_amount`(툰 셰이딩 0~1)도 여기서 넣는다. 디버그: `\` 패널(스타일·툰·맵 조명 슬라이더, 맵 조명은 그 맵 dressing.tscn에 저장), `]` 켜기/끄기, 콘솔 `look` |

`_mcp_game_helper`는 Godot AI 플러그인 것이라 건드리지 않는다.

## 신호 (`EventBus`)

정의는 [core/event_bus.gd](../../core/event_bus.gd)가 기준이다. 누가 쏘는지:

| 신호 | 쏘는 레인 | 주로 듣는 레인 |
|---|---|---|
| `day_started`, `phase_changed`, `flow_state_changed`, `weather_changed`, `sortie_started`, `sortie_ended`, `evening_settled` | A | 전부 |
| `noise_emitted`, `monster_killed`, `player_downed`, `rescue_completed`, `companion_stranded`, `extraction_completed`, `emergency_return_requested` | B | A·C·D |

`player_downed`는 필드 출격에서만 나간다. 기지 맵(방어전)의 플레이어는 `field_rules = false`라 `Player.downed`만 보낸다(B-23, 이슈 #110).
C의 기지 신호(신뢰·입주·관계·아이·편견·고립·전초기지·방어전)는 EventBus가 아니라 `Colony` 오토로드에 있다. 아래 "공개 함수"의 Colony 항목.
| `resident_joined/left/died`, `building_completed/damaged`, `relationship_changed`, `night_event_started`, `raid_warning/started/resolved` | C | A·B·D |
| `resources_changed`, `item_added/removed`, `equipment_changed`, `bag_changed` | A | D |
| `notification_posted` | 누구나 | D |
| `radio_message`, `journal_entry_added` | A | D |
| `settings_changed`, `game_saved`, `game_loaded` | A | 전부 |
| `xp_gained`, `level_up`, `perk_chosen`, `mastery_level_up` | A | B·D |
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
  A-09: `preview_upgrade(uid, ctx)`(D-12 강화 화면), `upgrade(uid, ctx)`, `preview_transfer(from, to, ctx)`, `transfer_upgrade(from, to, ctx)`,
  `preview_repair(uid, ctx)`, `repair(uid, ctx)`, `set_auto_repair(on)`, `run_auto_repair(facility, scrap_budget, ctx)`(저녁 정산),
  `list_recipes(facility, by_worker)`, `get_recipe(id)`, `blueprint_flag(recipe_id)`, `preview_craft(recipe_id, ctx)`, `craft(recipe_id, ctx, rng)`,
  `craft_by_worker(recipe_id, count, stock)`(C 정산용: Economy를 바꾸지 않고 `changes`를 돌려줌). 시설 레벨·담당 주민 손재주는 Armory가 Colony에서 읽는다.
  막힌 이유는 `reason` StringName. 설계도 플래그는 `blueprint_<output_id>`. 자동 수리는 SceneRouter가 저녁 정산 때 정비소·재봉실 순서로 부르고
  결과를 정산 보고 `repairs`에 붙인다.
  A-10: `preview_engrave(uid, essence_id, slot, ctx)`(D-12 각인 화면), `engrave(uid, essence_id, slot, ctx)`(덮어쓰기 포함, 기존 정수 소멸),
  `preview_remove_engraving(uid, slot, ctx)`, `remove_engraving(uid, slot, ctx)`, `preview_open_slot(uid, ctx)`, `open_slot(uid, ctx)`,
  `preview_refine(essence_id, times, ctx)`, `refine(essence_id, times, ctx)`, `preview_disassemble(uid, ctx)`, `disassemble(uid, ctx, rng)`,
  `essence_slot_count(uid)`, `get_engravings(uid)`, `is_engravable(uid)`, `essence_context(ctx)`. 수치·효과 계산은 `EssenceRules`(`systems/essence_rules.gd`).
  `get_item_stats()`의 `element`(무기 공격 속성 = 첫 번째로 채워진 슬롯), `essence_effects`([{element, essence_ids, grade, mult, params}]),
  `combo`({id, name, elements, proc_rate, trigger(hit|kill), params} 또는 null), 장신구 `element_resist`. `get_owner_summary().element_resist`.
  B(B-15)는 같은 속성 2개가 이미 합쳐진 효과(`mult` 1.5)로 오므로 다시 곱하지 않고, `combo.proc_rate`도 정해진 값을 그대로 쓴다.
- **Bag**: 루팅(B-08)용 `try_add(id, n) -> 들어간 양`, `count_of(id)`, `remove_item(id, n) -> bool`(이슈 #6). `resize_for_player()`(출격 준비), `add_resource(id, n) -> 못 넣은 양`, `add_item(uid) -> entry_id`, `take_from_storage(id, n)`,
  `move(entry_id, pos, rotated, area)`, `remove(entry_id, amount)`, `consume(id, n)`, `count(id)`, `entries(area)`, `entry_at(cell, area)`,
  `can_place(size, pos, rotated, area)`, `is_cell(cell, area)`, `unload_to_base()`(탈출: 자원→Economy, 장비→무기고),
  `lose_contents()`(쓰러짐: 안전 주머니 제외 소실. 보호 모드 `keep_bag_on_down`이면 B가 호출하지 않음).
  방어전(이슈 #110 #121): C의 `DefenseBattle.start()`가 `load_for_defense()`를 불러 창고에서 가방으로 장착 총의 탄약(종류당 `Bag.DEFENSE_AMMO_MAX`)과
  `Bag.DEFENSE_CONSUMABLES`(각 한 묶음)를 들어가는 만큼 옮기고, 끝날 때(`_finish`) `unload_to_base()`로 남은 것을 창고에 돌려놓는다. 쓴 만큼만 줄어든다.
  영역은 `Bag.AREA_BAG` / `Bag.AREA_POCKET`(2칸). 가방 속 장비의 Armory 소유자는 `Armory.BAG_ID`.
- **Radio**: `say(trigger_id, context, priority) -> bool`(쿨다운·빈도·1회 제한에 막히면 false), `set_combat(active)`(B: 전투 중 한 줄),
  `morning_broadcast()`. 트리거 id는 `data/radio/`: B가 부르는 것 `low_ammo`, `low_health`, `noise_high`, `rescuee_low_health`,
  `no_progress {direction}`, `dusk {minutes}`. 아침 방송·습격 징후·60초 경보·낮 습격 예상(`Colony.predict_raid`)·같은 지역 3번 쓰러짐은
  Radio가 신호(`day_started`, `raid_warning`, `sortie_started`, `player_downed`)를 듣고 알아서 말한다. LLM 없음.
  목소리는 `RadioVoice`(`UI.radio_voice`)가 낸다. 완성된 문장마다 녹음 클립 `RadioVoice.clip_path(speaker_id, text)`
  (`res://assets/audio/voice/<speaker_id>/<문장 MD5 앞 12자>.mp3`)이 있으면 그것을, 없으면 OS TTS를 쓴다.
  **무전 문장을 고치면 그 문장의 클립이 안 맞게 되니 다시 녹음한다.** 방송실 지기 목소리: Higgsfield ElevenLabs v4, 프리셋 Gideon.
  자막을 직접 그리는 컷신은 `UI.radio_voice.say(speaker_id, text, interrupt := false)`로 목소리만 낸다(인트로 방송).
- **Settings**: `get_value(key)`, `set_value(key, value) -> bool`(모르는 키·틀린 타입 거부), `apply_preset(id, new_game)`, `matching_preset()`,
  `reset_to_defaults(include_difficulty)`. 키 목록은 `Settings.DEFAULTS`. 난이도 프리셋은 `story`·`normal`·`hard`·`hardcore`
  (`Settings.PRESETS`), 항목을 따로 바꾸면 `difficulty`가 `custom`이 된다. 하드코어는 새 게임에서만 고른다.
  접근성·소리 설정은 `user://settings.cfg`에 바로 저장되고, 난이도 항목은 게임 저장(`difficulty` provider)에도 들어간다.
- **SaveSystem**: `register_provider(key, provider)`, `save_slot(slot) -> bool`, `load_slot(slot) -> bool`, `has_slot(slot)`, `delete_slot(slot)`, `slot_info(slot)`(불러오기 화면용), `autosave()`, `save_suspend()`, `has_suspend()`, `load_suspend()`, `current_slot`
- **SceneRouter**: 하루 흐름의 유일한 진행자. `state()`, `stayed_today`(C: 머무르기 날 생산 +20%), `last_sortie_result`, `last_evening_report`.
  - D(화면): `start_new_game(slot, difficulty)`, `load_game(slot)`, `load_suspended()`, `quit_to_title()`, `open_sortie_prep()`,
    `cancel_sortie_prep()`, `go_to_field(loadout)`, `stay_at_base()`, `end_stay()`, `finish_result()`, `confirm_evening()`, `finish_night()`.
  - `start_new_game(slot, difficulty, with_intro := true)`: 기본은 인트로(`IntroCutscene`, 플래그 `intro_pending`)로 시작하고 권총은 집 안 상자에서 얻는다. `with_intro = false`(테스트)면 `STARTER_LOADOUT`(기본: MAIN에 `pistol`)을 만들어 `Armory.PLAYER_ID`에 장착한다. 무한 탄 처리는 B.
  - 임시 진행 프롬프트(`main.tscn`의 `FlowPrompts`, `core/flow_prompts.gd`, A): D 화면이 아직 없는 단계를 대신한다.
    TITLE(새 게임·이어하기·중단한 출격), BASE_STAY(하루 마치기), NIGHT(잠자기), Esc 일시정지(필드·기지, 열린 화면 없을 때).
    D가 `data/ui/screens/`에 화면 id `title` / `stay` / `night` / `pause_menu`를 등록하면 그 단계의 프롬프트는 자동으로 빠지고
    `UI.open(id)`가 대신 불린다. 화면은 위 라우터 함수를 부르면 된다.
    UI 화면이 하나라도 열려 있으면(밤 이벤트, 새 식구, 습격 결과 등) 프롬프트는 숨었다가 다 닫히면 다시 뜬다.
  - C(기지): `start_day_raid(raid)`, `end_day_raid()`, `start_night_event(event_id, participants)`, `end_night_event()`.
  - B(필드)는 라우터 함수를 부르지 않는다. 탈출·쓰러짐 결과를 `FieldState.last_sortie_result()`에 채우고(이슈 #27)
    `extraction_completed`를 보낸다. `player_downed`는 라우터가 그 프레임 끝에 처리하므로 B의 쓰러짐 처리(가방·유실물·결과)가 먼저 끝난다.
    `rescue_completed`, `companion_stranded`, `emergency_return_requested`도 듣는다. 결과 형식은 아래 "출격 결과".
  - 허용되지 않은 전환은 거부(false + 오류). 디버그·테스트용 `advance(region_id = &"")`가 기본 경로로 한 단계 진행. 출격 준비에서는 `region_id`, 비어 있으면 `default_region()`(맵이 있는 첫 지역)으로 출격. 콘솔 `next [region_id]`.
  - main.tscn의 `World` 아래에 기지/필드 씬을 바꿔 넣는다. 씬 파일이 아직 없으면 비워 둔다.
- **Colony**: `get_resident(id)`, `active_resident_ids()`, `base_noise()`, `threat`, `tier`,
  `population()`, `bed_count()`, `free_beds()`, `add_resident(profile) -> id`(구조자 입주도 이것), `assign_bed(resident_id, bed_id)`,
  `settle_day()`, `roll_raid(time)`, `resolve_raid(raid, mode)`, `predict_raid(raid)` (형식은 아래 "하루 정산과 습격").
  레인 C M2 (이슈 #121). 신호는 모두 `Colony`에 있다.
  - C-12 신뢰도: `add_trust`, `trust_stage`, `unlocked_story`, `trust_actions`, `talk`, `deep_talk`, `give_gift`, `gift_reaction`. 신호 `trust_changed(id, trust, stage, reason)`.
  - C-13 입주 의식: `pending_arrivals`, `arrival_info`, `set_nickname`, `set_appearance`, `appearance_for_look`, `choose_bed`, `complete_arrival`, `known_likes`.
    신호 `arrival_ready`, `arrival_completed`, `resident_profile_changed`.
  - C-14 관계·밤 이벤트: `relation`, `relation_stage`, `relation_flags`, `relations_of`, `partner_of`, `couples`, `add_relation`, `pending_night_events`,
    `next_night_event`, `resolve_night_event`, `wedding_status`, `prepare_wedding`, `is_festival_today`. 신호 `night_events_ready`
    (EventBus `relationship_changed`의 stage는 `friend`·`lover`·`married`·`separated`).
  - C-15 아이 맞이: `child_arrival_status`, `child_methods`, `child_wishes`, `answer_child_wish`, `orphans`, `guardians_of`, `children_of`, `is_pregnant`,
    `sortie_block_reason`, `name_child`. 신호 `child_wish`, `child_arrived`. 퀘스트 `rumor_lost_child`가 `data/quests/`에 있으면 입양 소문으로 자동 시작한다.
  - C-16 편견: `prejudice_chains`, `prejudice_chain`, `choose_prejudice_response`. 신호 `prejudice_rumor`, `prejudice_incident`, `prejudice_resolved`.
  - C-20 고립·추모: `stranded_residents`, `stranded_in`, `memorial_names`, `pending_funeral`, `end_funeral`, `visit_memorial`. 신호 `resident_missing`, `funeral_ready`, `guardian_changed`.
  - C-19 전초기지: `outpost_nodes`, `active_outposts`, `is_outpost_active`, `garrison_of`, `can_build_outpost`, `build_outpost`, `assign_garrison`,
    `outpost_repair_cost`, `repair_outpost`, `outpost_directions`. 신호 `outposts_changed`.
  - C-21 낮 습격: `field_day_raid`. `raid_warning` info에 `outpost_warned`, `target`이 더해진다.
  - C-17 직접 방어전: `start_raid(raid)`(`raid_started`), `begin_direct_defense(raid, first_wave, on_done)`, `direct_defense`, `finish_direct_defense`,
    `skip_direct_defense`, `damage_building`, `reinstall_trap`. 신호 `defense_requested(raid, first_wave)`. 밤 습격의 흐름은 아래 "하루 정산과 습격".
  - 주민 Dictionary의 필드(`gender`, `origin_tags`, `talked_day`, `gift_day`, `arrival_pending`, `known_likes`, `study_days`, `story_revealed`,
    `stranded_region`, `strand_days_left`, `grief_days`, `memorial_day` 등)는 [base/residents/resident_data.gd](../../base/residents/resident_data.gd) 맨 위 주석이 기준이다.
- **B 필드 컴포넌트 (B-23, 기지 방어전, 이슈 #110)**: `Player.field_rules`(false면 `player_downed`를 보내지 않고 `Player.downed`만), `FieldCompanion.setup()`,
  `field_rules`, `guard_post`, `Monster.raid_goal`, `is_raider()`, `drop_mult`, `died`, `attack_landed`. 구조물 그룹 `raid_structures`, `raid_gates`
  (`RaidMarch` 상수), 구조물과 주민의 `take_damage(amount, info)`, 구조물 info 키 `structure_damage_mult`, `charges_gates`, `monster_id`, `source`, `element`.
  자세한 사용법은 [field/README.md](../../field/README.md).
- **FieldState**: `in_sortie()`, `lost_gear`, `boss_ready(boss_id)`, `boss_kill_count(boss_id)`.
  보스 부활 날짜 `boss_respawn_day`는 **보스 id별**이다(한 지역에 보스가 여럿일 수 있다). 지역 id로 저장된 옛 세이브는 불러올 때 그 지역의 `boss_id`로 옮긴다.
- **보스 (B-19)**: `BossSpawner`가 `BossArena`마다 그 보스의 부활 날짜를 따로 본다. 보스마다의 공략 규칙은 `BossDef.mechanic`(`BossMechanic` 스크립트)에 둔다.
- **동행 주민 고유 스킬 (B-29)**: `ResidentTemplate.signature_skill`(SkillDef, 실행 id는 `CompanionSkill.RUNNERS` 중 하나)과 `signature_line`.
  `FieldCompanion.setup()`이 `ResidentPool.templates`에서 읽는다(Colony 주민 Dictionary에는 없음). 신호 `FieldCompanion.called_out(text, near)`는
  `RescueTarget.called_out`과 같은 모양이고 `WorldMarkers`가 말풍선으로 띄운다. `SkillDef.fx`, `fx_element`로 실행 id와 다른 이펙트를 쓴다.
  훅: `on_added`, `on_tick`, `can_use(pattern)`, `on_pattern_started(pattern, area)`, `land_pattern(pattern, area)`(true면 공통 범위 타격·소환 생략),
  `filter_damage(amount, info)`(0이면 무시), `on_phase_changed`, `on_reset`, `on_died`. `BossPattern.action`이 있는 패턴은 mechanic이 직접 처리하고
  숫자는 `BossPattern.params`에 둔다. mechanic이 쓰는 BossMonster 공개 함수: `hold(sec)`(AI와 패턴 정지, mechanic이 몸을 움직임), `is_held()`, `cancel_cast()`,
  `area_for(pattern, target_pos)`, `area_targets(area)`, `hit_area(pattern, area)`, `summon(pattern)`.
  보스 모델(`MonsterVisual`)은 `play_once(clip)`, `sink(on, sec, rise)`를 mechanic에 내준다.
- **Audio**: `play(event_id, position)`, `set_music_state(state)`
- **Fx**: `spawn(effect_id, position, params)`. 이펙트 id 표는 [vfx/README.md](../../vfx/README.md)(D).
  피격 흰 번쩍임과 피해 숫자는 `FxFeedback`이 신호를 듣고 띄운다(게임플레이가 부르지 않음): `Monster.damaged`, `Player.health_changed`,
  `FieldCompanion.damaged(amount, info)`, `RescueTarget.damaged(amount, info)`(`Monster.damaged`와 같은 모양, 상태 틱은 번쩍임 없음), `ResidentAgent.hurt`.
  몸이 하얗게 번쩍이면 "맞았다" 한 가지 뜻이다. 번쩍임은 기존 `material_overlay`(적 외곽선 등)를 `next_pass`로 걸었다가 되돌린다.
- **마물 모델과 이펙트 (D-17, 이슈 #148)**:
  - 신호 `Monster.attack_started(info)`(B): 공격이 맞기 `MonsterRules.ATTACK_WINDUP_SEC`(0.4초) 전마다 한 번. info 키 `monster_id`, `target`.
    D의 `MonsterVisual`이 여기서 공격 클립을 시작한다.
  - 모델 `art/monsters/<def.id>.tscn`(D 소유): 있으면 Monster가 `_ready`에서 `Visual` 자식으로 붙이고, 회색 상자 메시(직접 자식 MeshInstance3D)를 숨긴다.
    `WeakPoint/Core`는 그대로 둔다. `Visual`은 부모 몬스터의 공개 신호(`state_changed`, `attack_started`, `damaged`, `died`, 보스 `pattern_started`)와
    `velocity`, `state`, `hp`, `def`만 읽는다. 처치되면 `Visual`이 몬스터를 떠나 시체로 남았다가 스스로 사라진다.
  - 이펙트 id: `MonsterDef.attack_fx`(B 데이터)는 공격이 맞을 때 B가 `Fx.spawn`한다. 값은 `monster_claw`, `monster_slam`, `monster_bite`,
    `monster_splash`, `monster_cast`. 경보 비명은 `monster_scream`, 처치는 `monster_death`(D가 시체와 함께). 보스 패턴이 맞을 때 `boss_<pattern.id>`
    (`boss_slam`, `boss_root_burst`, `boss_summon_pods`).
- **UI**: `open(screen_id, args)`, `close(screen_id)`
- **DebugConsole**: `register(name, callable, help)`, `execute(line)`, `is_open()`, `godmode`(B가 읽음).
  기능마다 자기 스크립트에서 `register`로 명령을 추가한다. 같은 이름으로 다시 등록하면 교체된다.
  `raid`, `resident`는 C가, `give`는 A-07이 교체할 자리표시 명령이다. 출시 빌드에서는 등록·실행이 모두 무시된다.
- **Progression**: `level`, `xp`, `xp_needed()`, `xp_to_next(level)`, `max_hp()`(레벨 기본 체력. 장비 보너스 `Armory.get_owner_summary().max_hp`는 B가 더함),
  `award(action, count)`(A-13: `&"personal_request"` 등 `Progression.XP_TABLE`의 키), `add_xp(amount, reason)`,
  `pending_perks()`, `perk_choices()`, `choose_perk(id)`(D: 특기 선택 화면), `perk_stacks(id)`, `perk_bonus(stat)`
  (B·Bag이 읽음: `bag_cells`, `stamina`, `medkit_pct`, `escort_speed_pct`, `lockpick_time_pct`. 정의는 `Progression.PERKS`),
  `add_mastery(combat_class, xp) -> 새 숙련`(B: 숙련 경험치 계산 후 호출, 보조무기 50%도 B가 적용), `mastery_level(combat_class)`(1~10), `mastery_xp(combat_class)`.
  처치 경험치는 `monster_killed`의 monster_id로 `data/monsters/<id>.tres`의 `tier`를, 탈출 경험치는 `data/regions/<id>.tres`의 `danger`를 읽는다(없으면 일반·위험도 1).
  구조·탈출 경험치는 SceneRouter가 `finish_sortie()`로 주고, `sortie_ended` 결과의 `xp`는 그 출격에서 얻은 전부다.
- **ResidentPool**: `draw(filter) -> profile`(검수 완료·미사용 중 무작위, 없으면 `{}`), `get_profile(id)`(사용 여부 무관, 이야기에 고정된 구조자),
  `available_ids(filter)`, `reviewed_ids()`, `mark_used(id)`, `is_used(id)`. 프로필은 `Colony.add_resident(profile)`에 그대로 넣는 형식이고,
  주민이 들어오면(`resident_joined`, 주민 id = 풀 id) 자동으로 사용 표시된다. filter 키: `demo`, `age_stage`, `access_need`, `former_job`,
  `region_id`, `exclude`. 프로필의 `gender`(`female`/`male`, 비면 입주 때 반반)와 `origin_tags`(출신 태그, 예: `migrant`. B-20 숨은 경로가 소문자로 비교)는
  Colony가 그대로 보관한다. 추가 키 `contribution`, `first_line`, `rescue_lines`(호위 대사 3줄), `situation`은 Colony가 무시하고
  구조 연출·UI가 읽는다. `reviewed = true`이고 검증(`ResidentTemplate.validate`, 금지어 `tools/resident_banned_words.txt`)을 통과한 항목만 나온다.
- **Journal** (A-17): `record(kind, context) -> bool`(신호 없는 사건: C-16 `prejudice_resolved {resident_id, other_id}`. 개인 요청 완료는
  `quest_completed`를 듣고 스스로 기록), `days()`, `entries_for_day(day)`, `entries_for_resident(id)`, `all_entries()`, `people()`,
  `resident_name(id)`, `epilogue(ending)`(D: 일지 화면·엔딩). 하루 최대 `Journal.MAX_ENTRIES_PER_DAY`줄이고 더 중요한 사건이 낮은 줄을 대신하므로,
  D는 `journal_entry_added`를 받으면 그 날을 `entries_for_day()`로 다시 그린다. `relationship_changed`의 stage는
  `friend`·`lover`·`spouse`(또는 `married`)·`separated`를 읽는다(다르면 `Journal.STAGE_KINDS`에 별칭).
- **Quests** (A-13): `start(quest_id, giver_id)`, `advance(quest_id, objective_id, amount)`(C: 공동체 퀘스트), `complete(quest_id)`, `fail(quest_id, reason)`,
  `get_status(quest_id)`(-1 = 시작 전, `Quests.Status`), `is_active()`, `is_completed()`, `days_left()`, `get_def()`, `active_quests()`(D: 퀘스트 기록),
  `active_field_objectives(region_id)`(B: 필드 목표 `{"quest_id", "objective_id", "kind": &"visit"|&"recover"|&"rescue", "region_id", "marker", "target_id", "count", "remaining", "text", "marker_label"}`). 지도·미니맵은 marker 위치에 노란 이중 마름모와 marker_label(없으면 text)을 그린다.
  진행은 신호로만 한다: 지역 방문·데려가기(`sortie_ended` 탈출), 아이템 회수(`sortie_ended`의 loot), 사람 데려오기(`rescue_completed`의 profile `id`),
  기지 제작(`building_completed`), 특정 날 방어(`raid_resolved`). 유품은 `data/resources/`의 자원(예: `keepsake_plane`)이라 B는 `marker` 자리에 줍는 물건을 두고
  `Bag.try_add`로 넣기만 하면 된다. 보상의 신뢰도는 `Colony.add_trust(resident_id, amount)`(C에 요청)를 부른다. 무전 소문은 Radio 트리거 `quest_rumor`로 말한다.

새 공개 함수가 필요하면 그 오토로드에 바로 추가하고 여기에 한 줄 적는다.

## 하루 단계와 흐름 상태

- `Enums.Phase`(5개)는 기획 01 "데이터 정의"의 큰 단계이고 저장된다. 게임 규칙(생산, 습격 판정 등)은 이것만 본다.
- `Enums.FlowState`는 기획 01 "게임 상태" 표의 세부 상태다(출격 준비, 결과, 낮 습격, 밤 습격·이벤트 등).
  UI가 화면을 고를 때 쓴다. 바꾸는 쪽은 `SceneRouter`뿐이고, 각 FlowState가 어느 Phase에 속하는지는
  `GameState.PHASE_OF_FLOW`에 있다. 바뀔 때 `flow_state_changed`가 먼저, Phase가 바뀌면 `phase_changed`가 뒤따른다.

## 출격 결과 (`sortie_ended`, B ↔ A-05, 이슈 #27)

B가 `FieldState.last_sortie_result()`로 내놓는 Dictionary가 바탕이고, 라우터가 `xp`, `rescued_profiles`, `down`을 더하고
`loot`를 합쳐(B가 탈출 순간 `Bag.unload_to_base()`를 부르고, 라우터가 남은 것—쓰러진 뒤 안전 주머니—을 한 번 더 비움) 보낸다.
B의 결과가 없으면(디버그 진행) 라우터가 기본값으로 채운다. B는 출격 시작 때 이전 결과를 지워야 한다.
라우터는 `last_sortie_result`를 세이브에 넣는다(결과 화면에서 저장한 게임을 이어도 같은 결과가 보인다).

```
{
  "extracted": bool, "downed": bool,
  "region_id": StringName, "point_id": StringName,     # 탈출 못 하면 &""
  "loot": {"resources": {id: n}, "discarded": {id: n}, "items": [uid]},
  "kills": int, "kills_by_monster": {StringName: int},
  "blueprints": Array[StringName],                     # 이번 출격에 익힌 설계도의 결과물 id (상자, 2026-11-06)
  "rescued": Array[StringName],                        # 데리고 나온 구조자 id
  "rescued_profiles": Array[Dictionary],               # rescue_completed로 받은 프로필 (라우터)
  "companions": Array[StringName], "stranded": Array[StringName],
  "duration_sec": float,
  "down": Dictionary,                                  # FieldState.down_result(), 쓰러지지 않으면 {} (라우터)
  "xp": int                                            # Progression.finish_sortie (라우터)
}
```

loadout의 `"seed": int`는 라우터가 없으면 만들어 넣고 저장한다(활성 탈출 지점이 불러오기 후에도 같게).

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

밤 습격(이슈 #121): 라우터가 `roll_raid(NIGHT)`가 나면 `NIGHT_RAID`로 가서 `Colony.start_raid(raid)`, `Colony.begin_direct_defense(raid, 1, on_done)`을 부르고,
`on_done`에서 `NIGHT`로 돌아간다. 기지 씬이 떠 있으면 `DefenseBattle`이 3파를 진행한 뒤 `on_done`을 부르고, 없으면(헤드리스) 바로 플레이어 판정(+20%)으로 끝난다.
`NIGHT_RAID` 동안 `finish_night()`는 거부된다. 낮 습격(머무르기 날, 출격 중 긴급 귀환)은 C가 같은 함수로 처리한다.

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
- `progression`(A) provider: 레벨·경험치·특기·클래스 숙련.
- `resident_pool`(A): 생존자 풀에서 이미 구조한 항목 id 목록(`{"used": [...]}`).
- 키 `quests`(A, A-13): 퀘스트 상태·진행도·진행 중인 출격의 지역과 동행.
- `journal`(A, A-17): 일지 항목, 만난 주민과 그들의 순간, 마지막 날.

## 아이템 id 규칙

- 자원·소모품은 `data/resources/`의 id(`Economy.get_def`). 탄약은 `ammo_pistol`(권총·기관단총), `ammo_rifle`(소총·저격총),
  `ammo_shell`(산탄총). 총의 `get_item_stats()["ammo_id"]`가 어느 탄약을 쓰는지 알려준다. 소모품: `first_aid_kit`, `bandage`, `noise_lure`, `painkiller`, `flashbang`, `grenade`.
- 통조림은 따로 없다. 필드에서 나오는 식량은 `food`.
- 정수는 `essence_<element>_<grade>`(예: `essence_green_low`). 정의는 `data/essences/`(EssenceDef, `EssenceRules.make_id(element, grade)`).
  개수는 Economy에 같은 id로, 창고 한도 없음.
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
  buildings.tscn     B  (팩 꾸미기: 건물, 땅, 소품, 나무. 에셋이 있을 때만 <region_id>.gd가 붙임)
  ground_splat.res   B  (buildings.tscn 땅 셰이더가 읽는 혼합 지도, 생성기가 구움)
levels/base/base_school/
  base_school.tscn   C
  layout.tscn        C
  dressing.tscn      D
```

- `buildings.tscn`, `ground_splat.res`는 `field/build/layout_builder.gd`가 layout.tscn과 같이 생성한다(B-26, 이슈 #144). 손으로 고치지 않는다.
  `buildings.tscn`은 `assets/` 팩 파일을 경로로만 참조하고 메시 데이터는 넣지 않는다. 에셋이 없는 클론(CI)에서는 붙지 않고 회색 맵으로 돈다.
  팩 꾸미기가 켜지면 지역 씬이 layout의 회색 박스(그룹 `kit_greybox`)를 숨긴다. 숨긴 CSG도 충돌은 남고, D의 dressing은 그대로 동작한다.
- **필드 마커**(B-02, `field/markers/`): `PlayerSpawn`, `ExtractPoint`, `LootSpot`, `MonsterNest`, `RescueSpot`,
  `HiddenRoute`, `BossArena`, `Recording`.
- **기지 마커**(C-01, `base/markers/`): `BuildArea`, `ZoneMarker`, `ResourceNode`(나무·잔해), `RaidSpawnPoint`, `WorkSpot`, `OutpostNode`.
- dressing을 만들 때 layout을 인스턴스해서 본다. 마커 위치를 바꾸려면 layout을 고치고, 그 마커를 읽는 테스트·생성기도 같이 고친다.

## UI와 게임플레이의 경계 (구조 원칙)

- 게임플레이 코드(core·systems·field·base)는 `Control` 노드를 만들지 않는다. 필요한 정보는 신호와 getter로 내놓고, 화면은 `ui/`에 둔다.
- 샌드박스에서 쓰는 디버그 UI만 예외(`_sandbox/` 안, 출시 빌드에 안 들어감).
- 화면은 게임 규칙을 계산하지 않는다. 예: 강화 비용은 `Armory`에 묻고, 습격 예상 결과는 `Colony`에 묻는다.
- 색만으로 구분하는 정보는 없다(등급·속성·관계는 모양이나 글을 함께).

## 새 게임 인트로·튜토리얼 (2026-11-06)

- `IntroCutscene`(levels/base/intro/): 새 게임(`intro_pending`)이면 base_school이 붙인다. 플래그 `intro_talked`(방송실 지기 대화. 지기는 주민이 아니다), `intro_house_done`(집에서 나옴). `phase()` = `&"cinematic"`/`&"house"`/`&"done"`.
- `UI.tutorial: IntroTutorial` — 매 프레임 상태로 단계를 정한다. `current_step()`, `skip()`. 끝나면 `tutorial_done`.
  단계가 가리키는 화면(`SHOWS_OVER`: 가방, 출격 준비) 말고 다른 화면, 컷신 대화, 건물 놓기 중에는 안내를 숨긴다(`current_step()`은 그대로).
- `UI.spotlight: Spotlight` — `focus_world(node, text, keys, radius, lift)`, `focus_control(c, text, keys)`, `focus_rect(rect, text, keys)`, `clear()`.
- `UI.cinematic: CinematicOverlay` — `bars(on)`, `fade_to(a)`, `cut(black)`, `title(text, sub)`, `caption(text)`, `talk(lines)`(await), `film`, `skippable` + `skip_requested`.
- `Player.script_input`: 비어 있지 않으면 컷신이 그 입력으로 step()을 돌린다(`"world_move": Vector3` 가능).
- `LootContainer.add_gear(def_id, rarity)`: 장비 칸. 꺼내면 Armory.create_item + Bag.add_item.
- `Bag.equip_entry(entry_id, owner_id)`: 가방 장비를 장착(원래 장비는 가방으로, 자리 없으면 창고). 가방 화면 우클릭 "장착".
- `RescueSpawn.required_flag`: 그 플래그가 있을 때만 나온다(공원 의사 `intro_talked`).
- `QuestObjective.marker_label`: 지도·미니맵의 노란 이중 마름모 아래 문구.
- `BuildingDef.story_only`: 건설 목록에 안 나오고 지을 수 없음(낡은 집 `old_house`, 6×7).
- 의무실 `infirmary`는 `requires_former_job = &"doctor"`. `main_01_left_behind`는 `tutorial_doctor` 완료 뒤 시작.
- 구조 인원(2026-11-06): `RescueManager.max_per_sortie = 5`, `pool_count = 3` — 고정 spawns 뒤에 `ResidentPool`에서 안 쓴 생존자를 빈 RescueSpot에 더 놓는다(부상, 아이템 없이 F 일으켜 세우기). `profile_for`는 DemoProfiles 다음 ResidentPool을 찾는다. 공원 의사는 `doctor_office` 태그(관리사무소)에만 나온다.
- 진행 속도(2026-11-06): `WorkRules.pace`(1.5) — 건설 진행·직업 생산·성장 일수에 곱한다(`build_progress()`, `stay_build_progress()`, `days_per_skill()`, `days_per_stat()`). `Progression.xp_pace`(1.5)는 경험치. 기획 수치 테스트는 둘 다 1.0으로 돌린다.
