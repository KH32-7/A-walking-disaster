class_name BossPattern
extends Resource
## One boss attack pattern (B-19). Lives inside a BossDef (data/monsters/bosses/<monster_id>.tres).
## An area pattern marks its shape on the ground for windup_sec (design 04: 1 s, shape + colour),
## then hits everyone still inside. A summon pattern spawns monsters after the windup instead.
## Design: docs/design/04-monsters.md "보스"

enum Anchor {
	SELF,    ## Area starts at the boss (ring around it, line or cone toward the target).
	FRONT,   ## Circle centered `offset` meters in front of the boss, toward the target.
	TARGET,  ## Circle centered on the target's position when the windup starts.
}

@export var id: StringName = &""
## Empty: the common area hit (shape) or summon (summon_id). Set: BossDef.mechanic runs it
## (dive, flash, clones...) from the same windup and telegraph; `params` holds its own numbers.
@export var action: StringName = &""
@export var params: Dictionary = {}

@export_group("Use")
## Picked only while the target is this far from the boss (flat meters).
@export var range_min: float = 0.0
@export var range_max: float = 5.0
@export var cooldown_sec: float = 5.0
## Ground warning time. Design 04: 1 s.
@export var windup_sec: float = 1.0

@export_group("Area")
## Fx boss_telegraph shapes: &"circle", &"cone", &"line", &"ring". Empty = no area (summon).
@export var shape: StringName = &"circle"
@export var anchor: Anchor = Anchor.FRONT
@export var offset: float = 0.0
@export var radius: float = 3.0
## Ring only: no hit inside this radius.
@export var inner: float = 0.0
## Cone only: full angle.
@export var angle_deg: float = 70.0
## Line only.
@export var length: float = 8.0
@export var width: float = 1.6
## &"danger" (damage) or &"warn" (no damage, slow only). Same meaning as Fx boss_telegraph.
@export var kind: StringName = &"danger"

@export_group("Hit")
## Damage = MonsterDef.attack x this.
@export var damage_mult: float = 1.0
## StatusHolder entries put on the hit, for example [{"id": &"bind", "duration": 1.0}].
@export var status: Array[Dictionary] = []

@export_group("Summon")
## data/monsters/<id>.tres to spawn. Empty = not a summon.
@export var summon_id: StringName = &""
@export var summon_count: int = 0
## This boss's summons alive at once.
@export var summon_max_alive: int = 0
## Summons appear this far from the target, inside the arena.
@export var summon_dist_min: float = 4.0
@export var summon_dist_max: float = 8.0


func is_summon() -> bool:
	return summon_id != &""
