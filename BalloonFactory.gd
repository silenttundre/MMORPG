class_name BalloonFactory
extends RefCounted

static func create() -> Node3D:
	var root := Node3D.new()
	root.name = "HotAirBalloon"
	_add_box(root, Vector3(0, 0.48, 0), Vector3(1.8, 0.8, 1.5), Color("9b6a3f"))
	_add_box(root, Vector3(0, 0.08, 0), Vector3(2.0, 0.16, 1.7), Color("67452c"))
	for x in [-0.75, 0.75]:
		for z in [-0.6, 0.6]:
			_add_box(root, Vector3(x, 2.1, z), Vector3(0.07, 3.2, 0.07), Color("ede1c2"))
	var canopy := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.15
	sphere.height = 3.4
	canopy.mesh = sphere
	canopy.position.y = 4.45
	var fabric := StandardMaterial3D.new()
	fabric.albedo_color = Color("e87554")
	fabric.roughness = 0.9
	canopy.material_override = fabric
	root.add_child(canopy)
	_add_box(root, Vector3(0, 4.35, 1.88), Vector3(0.55, 2.35, 0.09), Color("ffd073"))
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
