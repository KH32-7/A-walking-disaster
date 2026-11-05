# field/ — 필드

플레이어·카메라·전투·클래스·소음·마물·루팅·구조·탈출. 샌드박스는 field/_sandbox/ 씬.
- 아이템 스탯은 Armory.get_item_stats()로 읽는다. 자원은 Economy, 주민은 Colony getter로.
- 화면(Control)은 ui/에 둔다(샌드박스 디버그 UI만 예외). 소리는 Audio.play, 이펙트는 Fx.spawn.
- 마커 씬(field/markers/)은 맵·dressing이 같이 쓴다. 이름·속성을 바꾸면 쓰는 곳을 같이 고친다.
- 기지 방어전에서 쓰는 법은 field/README.md (B-23).
작업 목록(기록): docs/dev/lane-b-field.md
