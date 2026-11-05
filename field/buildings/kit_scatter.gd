extends Node3D
## Ground cover for the B-26 kit (grass, ferns, leaves, small rocks). Owner: Lane B.
## One MultiMeshInstance3D per pack mesh, built in _ready from the pack scenes, so the saved scene
## only holds paths and placements and never a copy of the pack's (paid) mesh data.
## Without the pack (CI) nothing is built.

## Pack scene paths.
@export var scenes: PackedStringArray
## Per scene: x, y, z, yaw, scale for each instance.
@export var instances: Array[PackedFloat32Array] = []


func _ready() -> void:
	for i in mini(scenes.size(), instances.size()):
		if ResourceLoader.exists(scenes[i]):
			_build(scenes[i], instances[i])


func _build(path: String, data: PackedFloat32Array) -> void:
	var source := (load(path) as PackedScene).instantiate() as Node3D
	var offset := (source.get_child(0) as Node3D).position
	var count := data.size() / 5
	for mi: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		var local := Transform3D.IDENTITY
		var n: Node = mi
		while n != source:
			local = (n as Node3D).transform * local
			n = n.get_parent()
		local.origin -= offset
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = count
		for k in count:
			var at := Vector3(data[k * 5], data[k * 5 + 1], data[k * 5 + 2])
			var basis := Basis(Vector3.UP, data[k * 5 + 3]).scaled(Vector3.ONE * data[k * 5 + 4])
			mm.set_instance_transform(k, Transform3D(basis, at) * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = path.get_file().get_basename().to_pascal_case()
		mmi.multimesh = mm
		mmi.material_override = mi.material_override
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	source.free()
