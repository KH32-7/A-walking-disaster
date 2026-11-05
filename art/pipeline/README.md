# 에셋 파이프라인 (D-02)

유료·라이선스 에셋을 비공개 `assets/` 서브모듈에 넣는 순서. 필요한 사람이 직접 넣는다(M2 이후 레인 구분 없음).
루트 `CLAUDE.md`의 "Committing asset changes"(서브모듈 먼저 커밋·푸시 → 메인 저장소 포인터)를 같이 따른다.

## 1. 사기 전에 라이선스 확인

기획 16 "에셋 조달"의 확인 항목 4개를 본다.

| 항목 | 확인할 것 |
|---|---|
| 다른 엔진 | Godot에서 써도 되는가. Unity Asset Store 표준 EULA는 허용한다(근거를 적는다). "Unity 전용"이면 사지 않는다 |
| 상업 이용 | 판매하는 게임에 넣어도 되는가 |
| 재배포 금지 | 원본 파일을 따로 공개·배포하면 안 되는가(대부분 그렇다 → 비공개 서브모듈에만) |
| AI 제한 | AI 학습·생성 입력 금지 조항이 있는가. 있으면 그 에셋을 AI 도구에 넣지 않는다 |

산 뒤 `assets/LICENSES.md`에 한 줄을 채운다. 4칸 중 하나라도 비어 있으면 `tests/ui/test_asset_licenses.gd`가 실패한다.

## 2. 원본 보관

받은 파일(`.unitypackage`, zip)은 `assets/_source/`에 둔다. `.gdignore`가 있어 Godot가 가져오지 않는다.
원본이 크면(수백 MB) 넣지 말고 `LICENSES.md` 메모에 다시 받는 곳만 적는다(LFS 용량 절약).

## 3. Unity 패키지에서 꺼내기

```sh
python -I art/pipeline/unitypackage_extract.py assets/_source/city_ruins.unitypackage \
    --out assets/environment/city/city_ruins --strip "Assets/CityRuins" --snake --dry-run
```

- FBX·OBJ·glTF·텍스처·오디오만 꺼낸다. `.mat`, `.prefab`, `.unity`, `.cs`, `.shader`는 버린다.
- `--dry-run`으로 목록을 먼저 보고, 맞으면 빼고 다시 실행한다. `--snake`는 이름을 소문자 스네이크로 바꾼다.
- `..`가 들어간 경로도 `--out` 밖으로는 쓰지 않는다.

## 4. Godot에서 가져오기

1. 에디터를 열어 한 번 가져오게 둔다(`.import` 파일이 생긴다).
2. `art/pipeline/apply_import_presets.gd`를 스크립트 편집기에서 열고 **File > Run**. 폴더 규칙대로 설정을 바꾸고 다시 가져온다.

| 종류 | 설정 |
|---|---|
| 텍스처 | VRAM 압축 + 밉맵. 이름이 `_normal`·`_n`·`_nrm`으로 끝나면 노멀 맵 |
| `ui/` 텍스처 | 무손실, 밉맵 없음 |
| 3D 씬 | LOD 생성, 그림자 메시, 탄젠트. 애니메이션은 `characters/`·`monsters/`만 |
| 오디오 | `audio/music/`·`audio/ambience/`는 반복, `audio/sfx/`는 반복 안 함 |

3. 머티리얼은 Unity 것을 쓰지 않는다. 메시에 `art/materials/toon_*.tres`를 복제해서 입힌다(텍스처는 `albedo_texture`).
   메시를 쓰는 씬(`.tscn`)도 `assets/` 안에 둔다. 메인 저장소 씬은 그 씬을 인스턴스한다.

## 5. 커밋

```sh
git -C assets switch main
git -C assets add -A
git -C assets commit -m "Add city_ruins pack"
git -C assets push
git add assets
git commit -m "[D-xx] Update assets: city_ruins"
```

- 메인 저장소의 `assets` 포인터는 누구나 올린다. 두 사람이 동시에 올리면 충돌하므로, 올리기 전에 `git pull`로 main의 포인터를 받는다.
- 메인 저장소에는 유료 파일이 하나도 없어야 한다. `tests/ui/test_no_paid_assets.gd`가
  `assets/`·`addons/`·`art/`·`ui/theme/fonts/` 밖의 모델·텍스처·오디오·`.unitypackage`를 찾으면 실패한다.
