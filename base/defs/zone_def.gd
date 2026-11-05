class_name ZoneDef
extends Resource
## One base zone (docs/design/09-base-building.md "구역과 개간"). Data: data/buildings/zones/<id>.tres.
## The map's ZoneMarker / BuildArea with the same zone_id give its shape; the rules live here so
## clearing works during the evening settlement even while the player is in the field.

@export var id: StringName = &""
@export var display_name: String = ""
## Size in cells (1 cell = 2 m), for screens. The map's BuildArea is the real footprint.
@export var size: Vector2i = Vector2i.ONE
## Work to clear (진행도). 0 with starts_cleared.
@export var clear_work := 0
## Resources gained when cleared.
@export var clear_yield: Dictionary[StringName, int] = {}
## Paid once when clearing starts (북쪽 숲: 비탈 계단 목재판 10).
@export var clear_cost: Dictionary[StringName, int] = {}
## Base tier needed before clearing can start (09 "해금").
@export var unlock_tier: Enums.BaseTier = Enums.BaseTier.CAMP
@export var starts_cleared := false
@export var indoor := false
## 0 = ground. Upper floors need an elevator for everyone to reach (C-11).
@export var floor_index := 0
## 이동 조건 (07 "참여 조건", C-11): what lets a wheelchair user reach work in this zone.
##   &"open" = flat ground, always reachable; &"ramp" = needs a working 경사로 in `ramp_zone`
##   (empty = this zone); &"elevator" = an upper floor, needs a working 승강기 somewhere in the base.
@export_enum("open", "ramp", "elevator") var mobility_access: String = "open"
@export var ramp_zone: StringName = &""
## Raid damage on buildings here is halved (실내 구역 −50%).
@export var raid_damage_mult := 1.0
@export var note: String = ""
