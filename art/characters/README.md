# 캐릭터 파이프라인 (D-09)

플레이어·동행·주민은 모두 `art/characters/character.tscn` 하나를 인스턴스하고, 외형은
`CharacterLook.apply(appearance)`로만 바꾼다. B(플레이어·동행)와 C(주민)는 메시를 직접 건드리지 않는다.

```gdscript
var look := preload("res://art/characters/character.tscn").instantiate()
add_child(look)
look.age_stage = resident.age_stage
look.apply(resident.appearance)   # {"preset", "hair", "hair_color", "outfit_color", "skin"} 모두 선택
```

- 외형 프리셋은 `data/ui/appearance/*.tres`(`AppearancePreset`)에 7종이 있다: 구조대원, 작업복, 단발, 긴 머리 우비, 간호복, 노년, 아이.
  입주 의식(D-13)에서 프리셋을 고르고 머리·옷 색을 바꾸면 그 값이 주민 `appearance`에 들어간다(저장은 C).
- 지금은 VRoid 모델이 없어서 툰 머티리얼로 만든 임시 인형이 나온다. 키는 약 1.6m이고, 나이대에 따라 크기가 바뀐다.
  프리셋의 `base_model`에 모델 경로를 넣으면 그 모델로 바뀐다.

## 팩 모델 (`ResidentModel`)

구조 대상, 동행, 기지 주민은 `art/characters/resident_model.gd`(`ResidentModel`)가 City People Free Samples와
People with Disabilities 팩 모델을 고른다. 주민 데이터(나이, 성별, 이동 조건, 전직)와 필드의 걷는 방식(휠체어, 부축)으로 고르고,
장애 모델은 그 조건이 데이터에 있는 사람에게만 입힌다. 에셋이 없으면 아무것도 안 하고 원래 그레이박스나 `CharacterLook` 인형이 보인다.
팩 텍스처는 팔레트 한 장을 같이 써서 입주 의식에서 고른 색은 팩 모델에 안 칠해진다.

## VRoid → Godot

1. **VRoid Studio**에서 만든다. 머리·옷 색은 흰색이나 연한 기본색으로 두고, 게임에서 칠한다.
2. **내보내기**: VRM 1.0, 폴리곤 줄이기 "중간", 텍스처 아틀라스 2048, 머티리얼 수 줄이기 켬, 블렌드셰이프는 표정만 남김.
   머티리얼 이름(`…_HAIR`, `…_SKIN`, `…_CLOTH`)은 그대로 둔다. `CharacterLook`이 이 이름으로 색을 칠한다.
3. **넣을 곳**: `assets/characters/vroid/<이름>.vrm`(비공개 서브모듈). `assets/LICENSES.md`에 VRoid 이용 약관
   (상업 이용 가능, 아바타 사용 조건)을 적는다. 순서는 `art/pipeline/README.md`를 따른다.
4. **가져오기**: `godot-vrm` 애드온이 필요하다(`addons/`에 들어 있고 `project.godot`에서 켜져 있다, A-52).
   MToon 셰이더는 애드온에 들어 있다. 툰 명암은 우리 `toon.gdshader`와 비슷하게 맞춘다(그림자 색 `#6B7F8C`).
5. **프리셋 연결**: `data/ui/appearance/<id>.tres`의 `base_model`에 경로를 넣는다.

## 애니메이션 공유

- 원본 애니메이션은 `assets/characters/anims/`(FBX·GLB, 휴머노이드)에 둔다.
- 가져오기 창에서 **Skeleton → Retarget → Bone Map**에 `SkeletonProfileHumanoid`를 지정한다. VRoid 모델도 같은 프로필을 쓴다.
- 모든 동작은 `AnimationLibrary` 하나(`assets/characters/anims/humanoid.res`)로 묶는다. 이름은 B·C와 맞춘다:
  `idle`, `walk`, `run`, `crouch_walk`, `dodge`, `aim_rifle`, `shoot_rifle`, `melee_swing`, `reload`, `carry`, `downed`,
  `interact`, `work_chop`, `work_mine`, `sit`, `talk`, `wave`.
- B·C는 `AnimationPlayer`에 이 라이브러리를 붙이고 이름으로 재생한다. 모델이 바뀌어도 코드는 그대로다.
