extends Node3D

@onready var progress_bar: ProgressBar = $SubViewportContainer/SubViewport/VBoxContainer/ProgressBar
@onready var name_label: Label = $SubViewportContainer/SubViewport/VBoxContainer/NameLabel

func _process(delta):
	# Billboard effect to always face the camera
	var cam = get_viewport().get_camera_3d()
	if cam:
		look_at(global_position + cam.global_transform.basis.z, cam.global_transform.basis.y)

func set_entity_name(entity_name: String):
	name_label.text = entity_name

func update_health(current_health: float, max_health: float):
	if max_health > 0:
		progress_bar.max_value = max_health
		progress_bar.value = current_health
		visible = current_health < max_health and current_health > 0
	else:
		visible = false
