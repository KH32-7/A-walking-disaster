# vfx/ — 이펙트 (D-18, 레인 D)

게임플레이는 `Fx.spawn(effect_id, position, params)`만 부른다. 이펙트 씬을 직접 인스턴스하지 않는다.

- 이펙트 정의: `data/ui/effects/<id>.tres` (`EffectDef`: 씬 + `base_params` + 효과음 + 동시 개수 상한).
  `base_params`는 기본값이고 호출 쪽 params가 이긴다. 조합 이펙트는 `combo_id`로 A의 `data/essences/combos/<id>.tres`
  `effect_params`(반경·시간)를 읽어서 그림이 규칙과 같은 크기가 된다.
- 효과음은 `EffectDef.sound`(D-11 `data/ui/audio_events`)로 Fx가 위치에 재생한다. `params.silent = true`면 끈다.
- 모양 + 색: 속성은 꽃잎(초록)·사각(돌)·물방울(물)·번개(빛), 색은 `UiTokens`. 색만으로 구분하는 이펙트는 없다.
- `Settings.reduce_flash`: 흰 번쩍임을 줄이고(`FxEffect.flash_k`) 피격 번쩍임은 약한 단색으로. Fx는 카메라를 흔들지 않는다
  (히트스톱·카메라 흔들림·넉백은 레인 B).
- 미리보기: `vfx/_preview/preview_vfx.tscn` (`-- --view=combat|elements|combos|release|blast|telegraph --shot=user://x.png --t=0.05,0.15,0.4 [--reduce_flash]`).
  키 1~6 화면, R 다시, F 번쩍임 줄이기. 테스트: `tests/ui/test_vfx.gd`.

## 타격감 (게임플레이가 부르지 않아도 되는 것)

`HitFeedback`(Fx 자식)이 신호를 듣는다. D-05 마물 표시와 같은 방식(그룹 + 신호 이름, duck typing).

| 듣는 것 | 보여 주는 것 |
|---|---|
| `field_monsters` 그룹의 `damaged(amount, info)` | 피해 숫자(`info.position`, 없으면 머리 위), 흰 피격 번쩍임. `info.status_tick`이면 작은 속성색 숫자, 번쩍임 없음 |
| `player` 그룹의 `health_changed(current, max)` | 줄면 빨강 `-N` + 붉은 번쩍임 + `player_hurt` 소리, 늘면 초록 `+N` |

피해 숫자: 0.7초 동안 위로 뜨며 흐려진다(UI_RULES §6). 치명타는 `ACCENT` + 크게 + 튀어나옴 + `!`, 약점은 `◆`.
숫자는 B가 준 최종 피해(약점·속성·방어 반영 후)를 그대로 쓴다. D는 계산하지 않는다.

## 이펙트 id

| id | params | 쓰는 곳 |
|---|---|---|
| `muzzle_flash` | `direction` | B weapon_holder |
| `bullet_tracer` | `to`, `speed`(기본 120 m/s) | B weapon_holder, companion |
| `bullet_impact` | `normal` | B weapon_holder (벽·바닥) |
| `hit_spark` | `element`, `crit`, `weak_point` | B weapon_holder, companion. 소리 `hit_impact` / 치명타 `hit_crit` |
| `perfect_block` | — | B weapon_holder |
| `neon_moth_blast` | `radius`(기본 2) | B self_destruct_behavior |
| `melee_swing` | `direction`, `arc_deg`, `range`, `element`, `combo_step` | **B 아직 안 부름** (요청) |
| `element_green` / `_stone` / `_water` / `_light` | `scale` | 정수 발동·상태 부여 (B-15) |
| `combo_thorn_bush`, `combo_swamp`, `combo_mud` | `zone_radius`/`zone_sec`/`duration_sec` (ComboDef 기본) | B-15 조합 발동 |
| `combo_photosynthesis`, `combo_shard_burst` | `radius` (ComboDef 기본) | B-15 처치 시 조합 |
| `combo_shock_puddle` | `radius`(1.5), `chain: Array[Vector3]` 연쇄 대상 위치 | B-15 |
| `release_gun` / `release_blade` / `release_blunt` | `element`, `direction`(총), `radius`·`hits`·`rounds`(기획 기본값) | B-15 정수 해방. 소리 `essence_release` |
| `explosion` | `radius`(3), `element` | 폭발물·보스 |
| `noise_lure` | `fuse_sec`(4), `radius` | 소음 미끼가 떨어진 자리. 소음 15 m 자체는 B의 `noise_emitted` |
| `boss_telegraph` | `shape`(`circle`·`cone`·`line`·`ring`), `radius`, `inner`, `angle_deg`, `length`, `width`, `direction`, `duration`(1초), `kind`(`danger` 빨강 / `warn` 주황) | B 보스. 소리 `boss_warning` |
| `damage_number` | `amount`, `kind`(`hit`·`tick`·`player`·`heal`), `crit`, `weak_point`, `element` | HitFeedback (B가 직접 불러도 됨) |
| `monster_claw` | `direction`, `range`(1.6), `element` | B-28 마물 근접 공격 (덩굴촉수, 뿌리 분쇄자) |
| `monster_slam` | `radius`(1.6), `element` | B-28 내려찍기 (석상, 잔해 돌진자) |
| `monster_bite` | `direction`, `element` | B-28 잔해 벌레 |
| `monster_splash` | `radius`(1.4) | B-28 물 마물 공격, split 분열 |
| `monster_scream` | `height`(1.3), `element` | B-28 alarm 경보 (포자낭) |
| `monster_cast` | `direction`, `height`(1.4), `element` | B-28 shock_orb 발사 (신호 망령) |
| `monster_death` | `radius`(0.9), `element` | B-28 모든 마물 사망 |
| `boss_slam` / `boss_root_burst` / `boss_summon_pods` | `radius`, `direction`, `length`, `element` | B-28 보스 패턴 발동(`boss_<pattern.id>`), 예고는 `boss_telegraph` |

## 새 이펙트 추가

1. `vfx/effects/<이름>.gd` (`extends FxEffect`, `_build()`에서 `sprite()`·`ground()`·`ribbon()`으로 조각을 만든다) + 같은 이름 `.tscn`.
2. `data/ui/effects/<id>.tres`에 `EffectDef` (씬, 기본 params, 소리).
3. 미리보기 화면에 넣고 스크린샷으로 확인한다.
