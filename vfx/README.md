# vfx/ (D-18)

게임플레이는 `Fx.spawn(effect_id, position, params)`만 부른다. 이펙트 노드를 직접 만들지 않는다.
그림은 전부 VFX 팩(`res://assets/vfx/`, Magic Arsenal, Elemental Spells, Stylized Shoot & Hit)의
텍스처와 메시를 `GPUParticles3D` + `vfx/shaders/fx_*.gdshader`로 다시 조립한 것이다. 유니티 프리팹은 없다.

## 구조

| 파일 | 하는 일 |
|---|---|
| `fx.gd` | 오토로드 `Fx`. 정의 로드, id별 동시 개수 상한(`max_alive`), 효과음 재생, `clear()` (흐름 상태가 바뀌면 자동) |
| `fx_node.gd` | 살아 있는 이펙트 하나. 레이어를 조립하고 수명이 끝나면 스스로 지운다 |
| `defs/fx_def.gd`, `defs/fx_layer.gd` | 데이터 스키마. 정의는 `data/ui/effects/<id>.tres` |
| `shaders/fx_common.gdshaderinc` | 빌보드, 속도 방향 늘이기, 플립북, 채널 모드(RGBA, 빨강=알파 마스크, 슛힛 묶음 채널 R 모양/G 디졸브/A 알파) |
| `fx_feedback.gd` | 피해 숫자와 흰색 피격 번쩍임. 게임플레이가 부르지 않는다(`Monster.damaged`, `Player.health_changed`, `FieldCompanion.damaged`, `RescueTarget.damaged`, `ResidentAgent.hurt`를 듣는다). 적 외곽선 위에서도 번쩍인다 |
| `_preview/preview_fx.tscn` | 모든 id 미리보기 |

레이어 종류: `PARTICLES`, `MESH`(팩 메시 + 텍스처, 방향을 따라 돈다), `GROUND`(바닥 원판), `BEAM`(두 점 사이 띠,
`travel_speed`면 날아가는 줄기), `LIGHT`(짧은 점광원, 폭발 같은 큰 순간에만).

## 에셋이 없을 때 (CI, 권한 없는 클론)

텍스처와 메시는 `.tres`에 **경로 문자열**로만 들어 있다(`ext_resource` 아님). 그래서 임포트와 로드가 깨끗하다.
`FxNode`가 `ResourceLoader.exists`로 보고 파일이 없는 레이어를 빼고, 남는 레이어가 없으면 노드를 만들지 않는다.
경고는 없다. 효과음은 그대로 난다(오디오는 합성음으로 대체된다).

## 이펙트 id

| id | params | 부르는 곳 |
|---|---|---|
| `hit_spark` | `element`, `crit`, `weak_point` | B weapon_holder, companion. 소리 `hit_impact`, 치명타 `hit_crit` |
| `muzzle_flash` | `direction` | B weapon_holder |
| `melee_swing` | `direction`, `radius`(무기 사거리), `element`, `combat_class`, `finisher` | B weapon_holder 근접 휘두르기. 마무리타면 큰 호가 하나 더 |
| `bullet_tracer` | `to`, `speed`(기본 120 m/s) | B weapon_holder, companion, companion_skill |
| `bullet_impact` | `normal` | B weapon_holder (벽, 바닥) |
| `perfect_block` | | B weapon_holder |
| `neon_moth_blast` | `radius`(기본 2) | B self_destruct_behavior. 소리 `explosion` |
| `consumable_grenade` / `_flashbang` / `_noise_lure` | `radius` | B thrown_consumable |
| `essence_release` | `element`, `combat_class`, `radius` | B magic_weapon (소리는 B가 냄) |
| `essence_chain` | `to` | B magic_weapon (빛 연쇄) |
| `essence_combo` | `id`, `radius`, `duration` | B magic_weapon, magic_zone. `essence_combo_<id>.tres`로 갈라진다 |
| `brace`, `dash_slash`, `precision_shot`, `shadow_step`, `slam`, `suppressive_fire` | `direction`, `radius` | B class_skills, companion_skill (소리는 B가 냄) |
| `boss_telegraph` | `shape`(`circle`, `ring`, `cone`, `line`), `radius`, `inner`, `angle_deg`, `length`, `width`, `direction`, `duration`, `kind`(`danger` 빨강 / `warn` 주황) | B boss_monster (B-19). 소리 `boss_warning`. 판정 모양 그대로를 `fx_telegraph.gdshader`로 그려서 **에셋 없어도 보인다**. 채움이 바깥으로 차오르면 그때 터진다 |
| `monster_claw` / `monster_bite` | `direction`, `element` | B monster_base (`MonsterDef.attack_fx`, 공격이 맞을 때). 덩굴촉수와 뿌리 분쇄자 / 잔해 벌레 |
| `monster_slam` / `monster_splash` | `radius`(기본 1.6 / 1.4), `element` | B monster_base. 석상과 잔해 돌진자 / 늪 덩어리와 안개 |
| `monster_cast` | `element` | B monster_base. 신호 망령, 포자낭 (머리 위에서 모였다 터짐) |
| `monster_scream` | `element` | B alarm_behavior. 바닥 고리가 경보가 닿는 거리 쪽으로 퍼진다 |
| `monster_death` | `element`, `radius`(기본 0.9) | D MonsterVisual (처치 때 시체와 함께, 모델 크기로 radius) |
| `boss_slam` / `boss_summon_pods` | `radius`(3 / 1.2), `element` | B boss_monster `boss_<pattern.id>`. 패턴이 맞을 때 / 소환한 자리마다 |
| `boss_root_burst` | `to`, `direction`, `element` | B boss_monster. 직선 예고를 따라 금이 달리고 흙이 솟는다 (`to` 없으면 금 줄기 없이 흙만) |
| `boss_dive` / `boss_splash` / `boss_tail_swing` | `to`, `direction` / `radius`(7) / `direction` | B serpent_mechanic (가라앉은 간판뱀). 잠수 돌진 줄기 / 둔화 물보라(주황 예고) / 간판 꼬리 휘두르기 |
| `boss_scalpels` / `boss_flash` / `boss_clones` / `boss_decoy_pop` | `to` / `radius`(9) / - / - | B wraith_mechanic (수술등 망령). 메스 줄기 / 섬광(실명, 깜빡임 줄이기 따름) / 분신 연기 / 분신이 맞아 사라짐 |
| `boss_laser` / `boss_shock_floor` / `boss_summon_moths` | `to` / `radius`(2.5), `duration` / - | B 네온 거신. 전광판 레이저(직선 공통 패턴) / 감전 장판(남는 바닥) / 나방 소환 자리 |
| `boss_cable_cut` / `boss_overload` | - | B colossus_mechanic. 전원 케이블이 끊김 / 셋 다 끊겨 무력화 |
| `boss_wave_slam` / `boss_rock_throw` | `to` / `radius`(3) | B 방파제 골렘. 파도 내리치기(직선 공통 패턴) / 바위 투척(원 공통 패턴, 위에서 떨어짐) |
| `boss_guard` / `boss_guard_break` | `duration` / - | B golem_mechanic. 방어 태세 돌 방패(일찍 풀리면 지움) / 둔기에 깨짐 |

속성 4종(초록, 돌, 물, 빛)은 따로 id가 없다. `params.element`를 받는 레이어가 `element_textures`로 텍스처를 바꾸고
`tint_element`로 `UiTokens.ELEMENT_COLORS` 색을 곱한다.

## 새 이펙트 추가

1. `data/ui/effects/<id>.tres`에 `FxDef`를 만들고 레이어를 넣는다(에디터 인스펙터에서 바로 조절 가능).
2. 미리보기 `_preview/preview_fx.gd`의 id 목록에 넣고 눈으로 확인한다.
3. `tests/ui/test_fx.gd`의 `GAMEPLAY_IDS`에 넣는다(게임플레이가 부르는 id면).

`Settings.reduce_flash`: `flash = true` 레이어와 점광원, 피격 번쩍임이 약해진다. Fx는 카메라를 움직이지 않는다
(히트스톱, 카메라 흔들림, 넉백은 field/ 쪽 코드).
