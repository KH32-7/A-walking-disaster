# levels/ — 파일 단위로 소유가 나뉜다

- levels/field/<id>/<id>.tscn, layout.tscn → 레인 B
- levels/base/<id>/<id>.tscn, layout.tscn → 레인 C
- 모든 dressing.tscn → 레인 D
- levels/test/ → 만든 레인이 소유(파일 이름 앞에 레인 글자: b_combat_test.tscn)
남의 파일은 인스턴스해서 보기만 하고 저장하지 않는다. 자세한 규칙: docs/dev/contracts.md "맵 파일과 마커"
