class_name LossRules
## 고립·실종·사망·추모 (C-20). Refs: docs/design/02-field.md "고립과 유실물",
## 08-relations-population.md "사망과 추모", 07-residents.md "사기 요인", 12 "고립 기한".
## All numbers are 가안 and live here.

## 고립: Settings strand_days (보통 5일, 어려움 3일, 0 = 보호 모드, 기한 없음). 끝나면 실종.
const STRAND_SETTING := &"strand_days"
## 실종되면 장착 장비도 함께 사라진다 (07 "유실").

## 사망 원인 (08): 습격 패배(확률, RaidRules), 질병 방치.
## 질병 방치: 치료받지 못한 채 앓는 기간이 끝났는데 굶주리고 있으면 이 확률로 사망 (영구 사망 설정일 때).
const NEGLECT_DEATH_CHANCE := 0.1

## 동료 사망 사기 −10 ~ −30 (관계 0 → −10, 관계 100 → −30).
const DEATH_MORALE_MIN := -10
const DEATH_MORALE_MAX := -30

## 슬픔: 가까운 주민(친구 이상) 5일, 배우자 10일. 슬픔 중 작업 효율 −20%.
const GRIEF_CLOSE_AT := RelationRules.FRIEND_AT
const GRIEF_DAYS := 5
const GRIEF_SPOUSE_DAYS := 10
const GRIEF_WORK_MULT := 0.8

## 추모비: 밤에 찾아가면 슬픔 기간 −1일 (건물 효과 grief_recovery), 사기 +3. 하루 한 번.
const MEMORIAL := &"memorial"
const MEMORIAL_VISIT_MORALE := 3
## 첫 사망이 추모비 건설을 연다 (data/buildings/memorial.tres requires_flags).
const FIRST_DEATH_FLAG := &"first_death"
