class_name MonsterDef
extends Resource
## One monster kind (B-07). Data lives in data/monsters/<id>.tres.
## Fields follow docs/design/04-monsters.md "데이터 정의" MonsterDef.
## Extra runtime fields (not in the design table) are grouped under "Runtime".

enum WeakPointShape { PETAL, SQUARE, DROPLET, BOLT }

@export var id: StringName = &""
@export var name: String = ""
@export var family: Enums.Element = Enums.Element.GREEN
@export var tier: Enums.MonsterTier = Enums.MonsterTier.NORMAL
@export var hp: float = 40.0
@export var defense: float = 0.0
@export var attack: float = 8.0
## m/s. 0 means the monster never moves (spore pod).
@export var move_speed: float = 4.0
@export var hearing_mult: float = 1.0
## Meters. 0 means blind (statue).
@export var sight_range: float = 8.0
## Full cone angle in degrees (design: 90 to 120).
@export var sight_angle: float = 110.0
## Ids from Monster.BEHAVIORS, for example &"bind", &"alarm", &"split".
@export var behaviors: Array[StringName] = []
@export var weak_point_shape: WeakPointShape = WeakPointShape.PETAL
@export var drop_table_id: StringName = &""
@export var regions: Array[StringName] = []
@export var group_min: int = 1
@export var group_max: int = 1

@export_group("Runtime")
## Scene to spawn. Its root is a Monster; the spawner assigns this def to it.
@export var scene: PackedScene
## Meters from which the monster can hit its target.
@export var attack_range: float = 1.5
## Seconds between attacks.
@export var attack_interval: float = 1.2
## Extra behaviors an elite gets on top of `behaviors` (04 "정예": 패턴 1개 추가, B-18).
@export var elite_behaviors: Array[StringName] = []
## Fx id spawned where the attack lands (D-17 data/ui/effects/monster_*.tres). Empty: none.
@export var attack_fx: StringName = &""

@export_group("Siege (C-17)")
## Raid-only monsters (tier SIEGE). Lane C's defense battle reads these; field code ignores them.
## Damage multiplier against walls and palisades (root crusher x3).
@export var structure_damage_mult: float = 1.0
## Rushes at doors and barricades first (debris ram).
@export var charges_gates: bool = false
