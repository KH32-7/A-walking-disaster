# base/ — 기지

건설·주민·관계·인구·습격·방어·전초기지. 샌드박스는 base/_sandbox/ 씬.
- 주민·건물 데이터는 Colony(base/colony.gd) 함수로 바꾼다. 자원 변경은 Economy.apply, 장비는 Armory.
- 방어전 전투는 field/의 B-23 컴포넌트를 쓴다(field/README.md).
- 화면(Control)은 ui/에 둔다. 기지 쪽은 정보를 신호와 getter로 내놓는다.
작업 목록(기록): docs/dev/lane-c-base.md
