class_name PrejudiceRules
## 편견 이벤트 체인 (C-16, docs/design/08-relations-population.md "편견과 갈등").
## 소문 → 선택 3가지 → 사건(5~10일 뒤) → 해소(편견을 가진 주민과의 대화).
## 이야기 안에서 흔적이 있는 사람은 실제로 마물이 되지 않는다: no rule here ever changes the
## target into anything; the chain only shows the rumor was groundless. Numbers are 가안.

## Who the rumor is about, and who holds the prejudice (RelationRules.PREJUDICE_TARGET_TRAITS).
const TARGET_TRAIT := &"monster_mark"
const HOLDER_TRAIT := &"prejudiced"

const STEP_RUMOR := &"rumor"        # 소문이 돌았고 플레이어의 선택을 기다림
const STEP_WAITING := &"waiting"    # 선택했고 사건을 기다림
const STEP_INCIDENT := &"incident"  # 사건이 일어났고 해소 대화를 기다림 (밤 이벤트 prejudice_talk)
const STEP_RESOLVED := &"resolved"

## 1. 소문: 흔적이 있는 주민이 기지에 3일 이상 있고 편견을 가진 주민이 있으면 매일 20%.
const RUMOR_AFTER_DAYS := 3
const RUMOR_CHANCE := 0.2
const RUMOR_MORALE := -5            # 기지 전체

## 2. 선택
const CHOICE_DEFEND := &"defend"    # 공개적으로 감싼다
const CHOICE_WATCH := &"watch"      # 지켜본다
const CHOICE_SEPARATE := &"separate"  # 따로 지내게 한다
const CHOICES: Array[StringName] = [CHOICE_DEFEND, CHOICE_WATCH, CHOICE_SEPARATE]
const DEFEND_TRUST := 10            # 감싸면 그 주민 신뢰 +10, 사기 +5
const DEFEND_MORALE := 5
const SEPARATE_MORALE := -20        # 따로 지내게 하면 사기 −20, 임시 거처로
const SEPARATE_EXTRA_DAYS := 5      # 이야기가 더 늦게 풀림

## 3. 사건: 선택 5~10일 뒤. 정수 공방에서 일하면 기지의 위기를 해결, 아니면 누군가를 구함.
const INCIDENT_DAYS := Vector2i(5, 10)
const INCIDENT_WORKSHOP := &"workshop_crisis"
const INCIDENT_RESCUE := &"rescue"
const WORKSHOP := &"essence_workshop"
const WORKSHOP_MORALE := 5          # 기지 전체
const RESCUE_RELATION := 15         # 구해 준 사람과 (RelationRules.SAVED_PARTNER)

## 4. 해소: 편견 특성이 사라지고 관계 +20, 사연 공개.
const RESOLVE_RELATION := 20
const RESOLVE_EVENT := &"prejudice_talk"

## 같은 작업장: 편견을 가진 주민은 대상과 같은 작업장이면 사기 −3.
const SAME_WORKPLACE_MORALE := -3
