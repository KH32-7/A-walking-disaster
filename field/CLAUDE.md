# field/ — 레인 B 소유

플레이어·카메라·전투·클래스·소음·마물·루팅·구조·탈출. 개발은 field/_sandbox/ 씬에서 한다.
- 아이템 스탯은 Armory.get_item_stats()로만 읽는다. 자원은 Economy, 주민은 Colony getter로.
- UI(Control)를 만들지 않는다(샌드박스 디버그 UI만 예외). 소리는 Audio.play, 이펙트는 Fx.spawn.
- 마커 씬(field/markers/)은 D와 맵 작업의 계약이다. 이름·속성을 바꾸면 D에게 알린다.
작업 목록: docs/dev/lane-b-field.md
