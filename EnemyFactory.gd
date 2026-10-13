class_name EnemyFactory
extends RefCounted

static func create(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Enemy"
	if kind == "skeleton":
		box(root, Vector3(0, 1.05, 0), Vector3(0.55, 0.78, 0.32), Color("e3dfca"))
		box(root, Vector3(0, 1.76, 0.1), Vector3(0.58, 0.58, 0.52), Color("f3efdc"))
		for x in [-0.37, 0.37]:
			box(root, Vector3(x, 1.06, 0), Vector3(0.15, 0.82, 0.18), Color("d9d4bf"))
			box(root, Vector3(x * 0.53, 0.36, 0), Vector3(0.16, 0.7, 0.18), Color("d9d4bf"))
		for x in [-0.17, 0.17]:
			box(root, Vector3(x, 1.84, 0.38), Vector3(0.13, 0.16, 0.07), Color("242733"))
		box(root, Vector3(0, 1.57, 0.4), Vector3(0.22, 0.08, 0.07), Color("282a30"))
	elif kind == "bat":
		box(root, Vector3(0, 0, 0), Vector3(0.75, 0.35, 0.44), Color("343340"))
		for side in [-1.0, 1.0]:
			var wing := box(root, Vector3(side * 0.67, 0.03, 0), Vector3(0.9, 0.08, 0.55), Color("4b4359"))
			wing.rotation.z = side * 0.17
			box(root, Vector3(side * 0.18, 0.16, 0.31), Vector3(0.1, 0.1, 0.06), Color("ff6666"))
			box(root, Vector3(side * 0.23, 0.37, 0.05), Vector3(0.13, 0.24, 0.12), Color("343340"))
		box(root, Vector3(0, -0.18, 0.32), Vector3(0.18, 0.17, 0.07), Color("eee8de"))
	elif kind == "polar_bear":
		box(root, Vector3(0, 1.0, 0), Vector3(1.55, 1.3, 2.35), Color("f0f0e9"))
		box(root, Vector3(0, 1.38, 1.1), Vector3(1.05, 0.9, 0.85), Color("f3f3ec"))
		box(root, Vector3(0, 1.13, 1.57), Vector3(0.54, 0.35, 0.32), Color("e6e5dc"))
		box(root, Vector3(0, 1.23, 1.76), Vector3(0.25, 0.17, 0.12), Color("2c3641"))
		for x in [-0.55, 0.55]:
			for z in [-0.7, 0.7]: box(root, Vector3(x, 0.3, z), Vector3(0.34, 0.65, 0.4), Color("e6e7df"))
			box(root, Vector3(x * 0.55, 1.55, 1.5), Vector3(0.14, 0.14, 0.1), Color("26313a"))
	elif kind == "sasquatch":
		box(root, Vector3(0, 1.35, 0), Vector3(1.15, 1.55, 0.7), Color("6b4d36"))
		box(root, Vector3(0, 2.45, 0.1), Vector3(0.8, 0.75, 0.65), Color("72513a"))
		box(root, Vector3(0, 2.26, 0.47), Vector3(0.5, 0.32, 0.15), Color("ad8565"))
		for x in [-0.78, 0.78]:
			box(root, Vector3(x, 1.2, 0), Vector3(0.3, 1.55, 0.36), Color("60442f"))
			box(root, Vector3(x * 0.45, 0.38, 0), Vector3(0.38, 0.75, 0.42), Color("60442f"))
		for x in [-0.2, 0.2]: box(root, Vector3(x, 2.53, 0.49), Vector3(0.1, 0.1, 0.06), Color("d9ac79"))
	elif kind == "shark":
		box(root, Vector3(0, 0.15, 0), Vector3(0.9, 0.5, 2.1), Color("607f91"))
		box(root, Vector3(0, 0.48, -0.2), Vector3(0.18, 0.75, 0.62), Color("4b6c80"))
		box(root, Vector3(0, 0.13, 1.18), Vector3(1.0, 0.12, 0.45), Color("4b6c80"))
		for x in [-0.32, 0.32]: box(root, Vector3(x, 0.24, -0.72), Vector3(0.08, 0.08, 0.08), Color("f0d7bb"))
	add_health_bar(root, 3.0 if kind == "sasquatch" else 2.36 if kind == "skeleton" else 2.15 if kind == "polar_bear" else 1.1 if kind == "shark" else 0.77)
	return root


static func add_health_bar(root: Node3D, height: float) -> void:
	var bar := Node3D.new()
	bar.name = "HealthBar"
	bar.position.y = height
	root.add_child(bar)
	box(bar, Vector3.ZERO, Vector3(1.12, 0.16, 0.06), Color("302c34"))
	var fill := box(bar, Vector3(0, 0, 0.045), Vector3(1.0, 0.11, 0.07), Color("7fe276"))
	fill.name = "Fill"


static func set_health(root: Node3D, health: int, maximum: int) -> void:
	var fill := root.get_node_or_null("HealthBar/Fill") as MeshInstance3D
	if not fill: return
	var fraction := clampf(float(health) / float(maximum), 0.0, 1.0)
	fill.scale.x = maxf(0.001, fraction)
	fill.position.x = -0.5 * (1.0 - fraction)
	var paint := fill.material_override as StandardMaterial3D
	paint.albedo_color = Color("7fe276") if fraction > 0.5 else Color("efc46a") if fraction > 0.25 else Color("ed7268")


static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = pos
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	part.material_override = surface
	parent.add_child(part)
	return part
