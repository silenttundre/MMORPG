class_name VehicleFactory
extends RefCounted

# Lightweight vehicles assembled from meshes so both LAN clients can create
# the same visual without downloading any extra assets.
static func create(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Vehicle"
	match kind:
		"car":
			box(root, Vector3(0, 0.43, 0.15), Vector3(1.65, 0.42, 2.45), Color("ed554a"))
			box(root, Vector3(0, 0.77, -0.42), Vector3(1.48, 0.26, 0.85), Color("ec7469"))
			box(root, Vector3(0, 0.92, -0.85), Vector3(1.25, 0.45, 0.08), Color("9ed9f5"))
			for x in [-0.83, 0.83]:
				for z in [-0.67, 0.97]:
					wheel(root, Vector3(x, 0.25, z), 0.3, false)
			box(root, Vector3(-0.5, 0.52, 1.41), Vector3(0.25, 0.14, 0.08), Color("fff0a1"))
			box(root, Vector3(0.5, 0.52, 1.41), Vector3(0.25, 0.14, 0.08), Color("fff0a1"))
		"motorbike":
			box(root, Vector3(0, 0.7, 0.15), Vector3(0.55, 0.34, 1.0), Color("f28b31"))
			box(root, Vector3(0, 0.91, -0.23), Vector3(0.45, 0.1, 0.62), Color("222b39"))
			box(root, Vector3(0, 1.05, 0.86), Vector3(1.0, 0.08, 0.08), Color("c8d1dc"))
			for z in [-0.73, 0.9]:
				wheel(root, Vector3(0, 0.37, z), 0.37, true)
			box(root, Vector3(0, 0.72, 1.07), Vector3(0.23, 0.18, 0.08), Color("fff0a1"))
		"bicycle":
			for z in [-0.78, 0.82]:
				wheel(root, Vector3(0, 0.38, z), 0.38, true)
			box(root, Vector3(0, 0.66, 0), Vector3(0.08, 0.08, 1.3), Color("55c2e3"))
			box(root, Vector3(0, 0.86, -0.24), Vector3(0.38, 0.08, 0.28), Color("253044"))
			box(root, Vector3(0, 1.02, 0.82), Vector3(0.78, 0.08, 0.08), Color("253044"))
		"rowboat":
			box(root, Vector3(0, 0.2, 0), Vector3(1.8, 0.35, 3.0), Color("805438"))
			box(root, Vector3(0, 0.38, -0.65), Vector3(1.45, 0.18, 0.22), Color("a67547"))
			box(root, Vector3(0, 0.38, 0.7), Vector3(1.45, 0.18, 0.22), Color("a67547"))
			for side in [-1.0, 1.0]:
				box(root, Vector3(side * 0.9, 0.36, 0), Vector3(0.14, 0.25, 2.7), Color("a67547"))
				box(root, Vector3(side * 1.25, 0.5, 0.15), Vector3(0.85, 0.08, 0.12), Color("d2b18c"))
		"speedboat":
			box(root, Vector3(0, 0.23, 0), Vector3(2.1, 0.38, 3.7), Color("e9eced"))
			box(root, Vector3(0, 0.46, -0.35), Vector3(1.65, 0.16, 1.5), Color("e2544f"))
			box(root, Vector3(0, 0.75, 0.55), Vector3(1.45, 0.5, 0.09), Color("96dbea"))
			box(root, Vector3(0, 0.5, -2.0), Vector3(0.55, 0.45, 0.42), Color("303c49"))
		"plane":
			box(root, Vector3(0, 0.42, 0), Vector3(0.92, 0.55, 3.8), Color("e9f0e9"))
			box(root, Vector3(0, 0.52, 0.1), Vector3(5.2, 0.18, 1.1), Color("e3d18a"))
			box(root, Vector3(0, 0.78, -1.45), Vector3(2.0, 0.12, 0.55), Color("d7b968"))
			box(root, Vector3(0, 1.0, -1.48), Vector3(0.12, 0.7, 0.5), Color("d7b968"))
			box(root, Vector3(0, 0.72, 1.0), Vector3(0.75, 0.35, 0.7), Color("8fc4d5"))
			box(root, Vector3(0, 0.44, 2.05), Vector3(0.18, 1.8, 0.12), Color("323c48"))
			for x in [-0.9, 0.9]:
				wheel(root, Vector3(x, 0.1, 0.25), 0.18, true)
	return root


static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	part.mesh = shape
	part.position = pos
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	paint.roughness = 0.65
	part.material_override = paint
	parent.add_child(part)


static func wheel(parent: Node3D, pos: Vector3, radius: float, narrow: bool) -> void:
	var part := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = 0.12 if narrow else 0.2
	part.mesh = shape
	part.position = pos
	part.rotation.z = PI * 0.5
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color("20242b")
	part.material_override = rubber
	parent.add_child(part)
