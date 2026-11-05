# art/monsters/ (D-17, 레인 D)

마물 모델 씬. `<def.id>.tscn` = `MonsterVisual` + `assets/monsters/<계열>/<id>.glb`.
B의 `Monster`가 `_ready`에서 이 파일을 찾아 `Visual` 자식으로 붙이고 회색 상자(Body 등)를 숨긴다.
약점 핵(`WeakPoint/Core`)은 조준 표시라서 그대로 둔다. 모델 파일이 없으면(에셋 권한 없는 클론) 회색 상자가 남는다.

- 애니메이션은 몬스터의 공개 신호와 속도로만 고른다: 이동 속도 -> Idle/Walk/Run(추적 중), `attack_started` -> Attack(포자낭 Shoot),
  `damaged` -> Hit(공격 중이면 끊지 않음), `state_changed` CHASE -> Scream(포자낭)/Rise(물뱀), 보스 `pattern_started` -> `pattern_clips`.
- 석상은 조용히 서 있을 때 Freeze, 움직이기 시작하면 Wake 한 번.
- 처치(`died`, hp 0 이하): 모델이 몬스터를 떠나 시체로 남는다. `monster_death` 이펙트, Death 재생, 0.6초 뒤 땅으로 가라앉고 사라진다.
  `vanish()`(나방 자폭)는 시체를 남기지 않는다.
- 크기(`model_scale`)는 B 씬의 충돌 크기에 맞춘 가안. 나방은 `model_offset`으로 띄운다.
- 머티리얼은 `toon_default`를 복제해 모델 텍스처를 넣는다(외곽선 포함).
- 클립 목록과 원본 리깅 파일: `assets/monsters/README.md`, `assets/_source/monsters_rig/`.
- MonsterDef가 아직 없는 4종(방파제 골렘, 가라앉은 간판 물뱀, 수술등 망령, 네온 거상)도 씬은 있다.
- 테스트: `tests/ui/test_monster_visuals.gd`. 미리보기: `vfx/_preview/preview_vfx.tscn -- --view=monsters` / `--view=boss`.
