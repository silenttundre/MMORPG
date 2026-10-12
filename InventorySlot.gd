extends Panel

signal slot_clicked(slot)
signal swap_requested(source_slot, target_slot)

@onready var icon: TextureRect = $Icon
@onready var quantity_label: Label = $QuantityLabel

var item_data: Dictionary = {}

func _ready():
	gui_input.connect(_on_gui_input)
	clear_slot()

func set_item(data: Dictionary):
	item_data = data
	if item_data.is_empty():
		clear_slot()
		return
	
	var item_id = item_data.get("item_id", 0)
	
	# This assumes you have item icons in 'res://assets/icons/items/' named like '1.png', '2.png', etc.
	var icon_path = "res://assets/icons/items/%s.png" % item_id
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
		icon.visible = true
	else:
		icon.texture = null
		icon.visible = false
	
	var quantity = item_data.get("quantity", 1)
	if quantity > 1:
		quantity_label.text = str(quantity)
		quantity_label.visible = true
	else:
		quantity_label.visible = false

func clear_slot():
	item_data = {}
	icon.visible = false
	quantity_label.visible = false

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		emit_signal("slot_clicked", self)

func _get_drag_data(at_position: Vector2):
	if item_data.is_empty():
		return null

	# Create a preview that looks like the slot's icon
	var preview_icon = TextureRect.new()
	preview_icon.texture = icon.texture
	preview_icon.size = Vector2(48, 48)
	preview_icon.expand_mode = 1 # Keep aspect ratio
	set_drag_preview(preview_icon)

	# The payload of the drag is a reference to this slot node itself
	return self

func _can_drop_data(at_position: Vector2, data) -> bool:
	# We can only drop data if it's from another node with the same script.
	return data is Panel and data.get_script() == get_script()

func _drop_data(at_position: Vector2, data):
	# When an item is dropped on this slot, 'data' is the source slot node.
	# We emit a signal to the parent UI to handle the swap logic.
	# 'data' is the source_slot, 'self' is the target_slot.
	emit_signal("swap_requested", data, self)