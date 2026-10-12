class_name ProceduralCharacter
extends RefCounted

const FUR_COLORS := {
	"rabbit": Color(0.92, 0.92, 0.96),
	"dog": Color(0.62, 0.38, 0.18),
	"cat": Color(0.45, 0.48, 0.52),
	"cow": Color(0.94, 0.91, 0.82),
	"fox": Color(0.9, 0.28, 0.06),
	"wolf": Color(0.3, 0.34, 0.4),
	"bear": Color(0.25, 0.12, 0.055),
	"panda": Color(0.92, 0.92, 0.88),
}

static func create(
	body_shape: String,
	animal_type: String,
	body_color: Color,
	shirt_type: String = "none",
	pants_type: String = "none",
	shoes_type: String = "none"
) -> Node3D:
	var root := Node3D.new()
	root.name = "ProceduralCharacter"

	var torso_scale := Vector3(0.72, 1.05, 0.45)
	if body_shape == "male":
		torso_scale = Vector3(0.84, 1.08, 0.48)
	elif body_shape == "female":
		torso_scale = Vector3(0.68, 1.02, 0.43)

	_add_capsule(root, Vector3(0, 1.08, 0), torso_scale, body_color)
	_add_leg(root, "LeftLeg", -0.27, body_color, pants_type, shoes_type)
	_add_leg(root, "RightLeg", 0.27, body_color, pants_type, shoes_type)
	_add_limb(root, Vector3(-0.52, 1.1, 0), Vector3(0.17, 0.78, 0.18), body_color)
	_add_limb(root, Vector3(0.52, 1.1, 0), Vector3(0.17, 0.78, 0.18), body_color)

	_add_clothes(root, torso_scale, shirt_type)
	_add_animal_head(root, animal_type)
	return root

static func _add_animal_head(root: Node3D, animal_type: String) -> void:
	var fur: Color = FUR_COLORS.get(animal_type, Color.WHITE)
	_add_sphere(root, Vector3(0, 2.05, 0), Vector3(0.58, 0.52, 0.52), fur)

	var ear_color := fur.darkened(0.08)
	match animal_type:
		"rabbit":
			_add_ear(root, Vector3(-0.25, 2.72, 0), Vector3(0.18, 0.65, 0.16), ear_color)
			_add_ear(root, Vector3(0.25, 2.72, 0), Vector3(0.18, 0.65, 0.16), ear_color)
		"dog":
			_add_ear(root, Vector3(-0.48, 2.2, 0), Vector3(0.23, 0.42, 0.15), ear_color, -0.45)
			_add_ear(root, Vector3(0.48, 2.2, 0), Vector3(0.23, 0.42, 0.15), ear_color, 0.45)
		"bear", "panda":
			var round_color := Color(0.06, 0.06, 0.07) if animal_type == "panda" else ear_color
			_add_sphere(root, Vector3(-0.42, 2.43, 0), Vector3(0.22, 0.22, 0.15), round_color)
			_add_sphere(root, Vector3(0.42, 2.43, 0), Vector3(0.22, 0.22, 0.15), round_color)
		"cow":
			_add_ear(root, Vector3(-0.48, 2.32, 0), Vector3(0.28, 0.16, 0.13), ear_color, -0.7)
			_add_ear(root, Vector3(0.48, 2.32, 0), Vector3(0.28, 0.16, 0.13), ear_color, 0.7)
			_add_horn(root, Vector3(-0.27, 2.52, 0), -0.15)
			_add_horn(root, Vector3(0.27, 2.52, 0), 0.15)
		_:
			_add_ear(root, Vector3(-0.34, 2.5, 0), Vector3(0.25, 0.4, 0.16), ear_color, -0.18)
			_add_ear(root, Vector3(0.34, 2.5, 0), Vector3(0.25, 0.4, 0.16), ear_color, 0.18)

	var muzzle_color := fur.lightened(0.18)
	if animal_type == "cow":
		muzzle_color = Color(0.78, 0.48, 0.5)
	_add_sphere(root, Vector3(0, 1.94, 0.45), Vector3(0.34, 0.22, 0.22), muzzle_color)

	if animal_type == "panda":
		_add_sphere(root, Vector3(-0.2, 2.12, 0.43), Vector3(0.17, 0.14, 0.07), Color(0.03, 0.03, 0.035))
		_add_sphere(root, Vector3(0.2, 2.12, 0.43), Vector3(0.17, 0.14, 0.07), Color(0.03, 0.03, 0.035))
	_add_sphere(root, Vector3(-0.2, 2.13, 0.49), Vector3(0.075, 0.09, 0.055), Color(0.04, 0.04, 0.045))
	_add_sphere(root, Vector3(0.2, 2.13, 0.49), Vector3(0.075, 0.09, 0.055), Color(0.04, 0.04, 0.045))
	_add_sphere(root, Vector3(0, 2.0, 0.65), Vector3(0.09, 0.07, 0.06), Color(0.04, 0.025, 0.02))

static func _add_leg(root: Node3D, name: String, x: float, body_color: Color, pants: String, shoes: String) -> void:
	# Rotate the whole leg at the hip so trousers and shoes follow the stride.
	var pivot := Node3D.new()
	pivot.name = name
	pivot.position = Vector3(x, 0.7, 0)
	root.add_child(pivot)
	_add_limb(pivot, Vector3(0, -0.35, 0), Vector3(0.2, 0.7, 0.22), body_color)
	if pants != "none":
		var color := Color(0.08, 0.18, 0.38) if pants == "jeans" else Color(0.35, 0.32, 0.22)
		var height := 0.52 if pants == "jeans" else 0.3
		_add_box(pivot, Vector3(0, -0.22, 0), Vector3(0.25, height, 0.27), color)
	if shoes != "none":
		var color := Color(0.9, 0.9, 0.92) if shoes == "sneakers" else Color(0.16, 0.08, 0.035)
		_add_box(pivot, Vector3(0, -0.62, 0.09), Vector3(0.28, 0.18, 0.42), color)

static func _add_clothes(root: Node3D, torso_scale: Vector3, shirt: String) -> void:
	if shirt != "none":
		var color := Color(0.12, 0.42, 0.78) if shirt == "basic_tshirt" else Color(0.32, 0.16, 0.48)
		_add_box(root, Vector3(0, 1.18, 0), Vector3(torso_scale.x + 0.08, 0.64, torso_scale.z + 0.08), color)
		if shirt == "hoodie":
			_add_torus(root, Vector3(0, 1.66, -0.05), color)

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

static func _add_mesh(root: Node3D, mesh: PrimitiveMesh, position: Vector3, scale_value: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position
	node.scale = scale_value
	node.material_override = _material(color)
	root.add_child(node)
	return node

static func _add_sphere(root: Node3D, position: Vector3, scale_value: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 16
	mesh.rings = 8
	_add_mesh(root, mesh, position, scale_value, color)

static func _add_capsule(root: Node3D, position: Vector3, scale_value: Vector3, color: Color) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radial_segments = 16
	mesh.rings = 6
	_add_mesh(root, mesh, position, scale_value, color)

static func _add_limb(root: Node3D, position: Vector3, size: Vector3, color: Color) -> void:
	_add_capsule(root, position, size, color)

static func _add_box(root: Node3D, position: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	_add_mesh(root, mesh, position, size, color)

static func _add_ear(root: Node3D, position: Vector3, size: Vector3, color: Color, rotation_z: float = 0.0) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 12
	mesh.rings = 6
	var ear := _add_mesh(root, mesh, position, size, color)
	ear.rotation.z = rotation_z

static func _add_horn(root: Node3D, position: Vector3, rotation_z: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.11
	mesh.height = 0.32
	var horn := _add_mesh(root, mesh, position, Vector3.ONE, Color(0.82, 0.72, 0.48))
	horn.rotation.z = rotation_z

static func _add_torus(root: Node3D, position: Vector3, color: Color) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.22
	mesh.outer_radius = 0.34
	var hood := _add_mesh(root, mesh, position, Vector3(1.0, 1.0, 0.65), color.darkened(0.08))
	hood.rotation.x = PI * 0.5
