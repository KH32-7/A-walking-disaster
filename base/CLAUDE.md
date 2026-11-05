# base/ — 레인 C 소유

건설·주민·관계·인구·습격·방어. 개발은 base/_sandbox/ 씬에서 한다.
- 주민 데이터는 Colony만 수정한다. 자원 변경은 Economy.apply, 장비는 Armory.
- 방어전 전투는 B의 컴포넌트를 인스턴스해서 쓴다(field/ 파일은 고치지 않음).
- UI(Control)를 만들지 않는다. 정보는 신호와 getter로 내놓는다.
작업 목록: docs/dev/lane-c-base.md
