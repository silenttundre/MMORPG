class_name AnimalFactory
extends RefCounted

static func create(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "WildAnimal"
	var fur := Color("aa754c") if kind == "deer" else Color("dad6c5") if kind == "goat" else Color("d3b595")
	var scale_factor := 0.65 if kind == "rabbit" else 1.0
	_add_box(root, Vector3(0, 0.85, 0), Vector3(0.85, 0.7, 1.3) * scale_factor, fur)
	_add_box(root, Vector3(0, 1.12, 0.62 * scale_factor), Vector3(0.54, 0.55, 0.55) * scale_factor, fur.lightened(0.06))
	for x in [-0.3, 0.3]:
		for z in [-0.42, 0.42]:
			_add_box(root, Vector3(x * scale_factor, 0.35, z * scale_factor), Vector3(0.15, 0.65, 0.16) * scale_factor, fur.darkened(0.2))
	if kind == "rabbit":
		for x in [-0.18, 0.18]:
			_add_box(root, Vector3(x, 1.65, 0.37), Vector3(0.13, 0.6, 0.14), fur)
	elif kind == "goat":
		for x in [-0.2, 0.2]:
			_add_box(root, Vector3(x, 1.6, 0.7), Vector3(0.1, 0.4, 0.1), Color("cfc9ab"))
	else:
		for x in [-0.25, 0.25]:
			_add_box(root, Vector3(x, 1.54, 0.6), Vector3(0.1, 0.55, 0.1), Color("a08965"))
	return root


static func _add_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = pos
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	visual.material_override = surface
	parent.add_child(visual)
