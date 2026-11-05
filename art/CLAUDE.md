# art/ — 아트·셰이더

셰이더·머티리얼·공개 가능한 자체 제작 아트만. **유료·라이선스 에셋은 assets/ 서브모듈에만** 넣는다.

## 공용 머티리얼 (D-03)

- `art/materials/toon_*.tres`: 툰 2~3단 명암 + 림라이트, 외곽선은 `next_pass`(outline.tres)로 붙어 있다.
  B·C의 그레이박스도 이걸 쓰면 최종 화면과 같은 명암이 나온다. 색만 바꾸려면 머티리얼을 복제해서 `albedo`를 바꾼다.
- `glow_<green|stone|water|light>.tres`: 마물 핵·각인 무기·정수 발광. 모양은 메시로 낸다(꽃잎·사각·물방울·번개).
- `roof_fade_concrete.tres` + `RoofFader`(art/roof_fader.gd): 실내 지붕이 플레이어 위에서 사라진다. dressing에 둔다.
- 외곽선은 법선이 매끈한 메시에서만 이어진다. 모서리가 각진 박스는 법선을 부드럽게 굽거나 외곽선 없이 쓴다.
- 미리보기: `art/_preview/shader_preview.tscn`.
