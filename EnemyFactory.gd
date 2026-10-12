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
	else:
		box(root, Vector3(0, 0, 0), Vector3(0.75, 0.35, 0.44), Color("343340"))
		for side in [-1.0, 1.0]:
			var wing := box(root, Vector3(side * 0.67, 0.03, 0), Vector3(0.9, 0.08, 0.55), Color("4b4359"))
			wing.rotation.z = side * 0.17
			box(root, Vector3(side * 0.18, 0.16, 0.31), Vector3(0.1, 0.1, 0.06), Color("ff6666"))
			box(root, Vector3(side * 0.23, 0.37, 0.05), Vector3(0.13, 0.24, 0.12), Color("343340"))
		box(root, Vector3(0, -0.18, 0.32), Vector3(0.18, 0.17, 0.07), Color("eee8de"))
	add_health_bar(root, 2.36 if kind == "skeleton" else 0.77)
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
