# art/music — 자체 제작 음악

KH32-7이 Suno로 만든 곡이고 저작권은 KH32-7에게 있다(2026-11-06). 공개 저장소에 두어도 되는 자체 제작물이라
`assets/`가 아니라 여기에 둔다. `.import`는 반복 재생(`loop=true`).
음량은 `data/ui/music_layers/<id>.tres`의 `volume_db`로 맞춘다(원본은 약 -15.5 LUFS, 지금 값은 효과음 아래로 작게).

| 파일 | 원래 이름 | 쓰는 곳 (MusicLayerDef id) |
|---|---|---|
| `title_theme.mp3` | `title (1).mp3` | 타이틀 (`title_theme`) |
| `base_theme.mp3` | `title (2).mp3` | 기지 (`base_theme`) |
| `city_park.mp3` | `공원.mp3` | 공원 필드 (`field_city_park`) |
| `city_park_battle.mp3` | `공원 전투.mp3` | 공원 추격·전투 (`chase_city_park`) |
| `flooded_mall.mp3` | `침수 상가.mp3` | 침수상가 필드 (`field_flooded_mall`) |
| `flooded_mall_battle.mp3` | `침수 상가 전투.mp3` | 침수상가 추격·전투 (`chase_flooded_mall`) |
