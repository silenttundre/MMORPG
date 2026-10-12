extends Control

# Character creation UI
@onready var animal_option_button: OptionButton = %AnimalOptionButton
@onready var body_color_picker: ColorPicker = %BodyColorPicker
@onready var username_input: LineEdit = %UsernameInput
@onready var body_shape_option_button: OptionButton = %BodyShapeOptionButton
@onready var shirt_option_button: OptionButton = %ShirtOptionButton
@onready var pants_option_button: OptionButton = %PantsOptionButton
@onready var shoes_option_button: OptionButton = %ShoesOptionButton
@onready var preview_viewport: SubViewport = %PreviewViewport
@onready var character_preview: Node3D = %CharacterPreview
@onready var create_button: Button = %CreateButton

# Available animal heads
var animal_heads = {
	"rabbit": {
		"name": "Rabbit",
		"ear_type": "long_upright",
		"nose_type": "small_pink",
		"eye_type": "large_brown",
		"fur_color": Color.WHITE
	},
	"dog": {
		"name": "Dog", 
		"ear_type": "floppy",
		"nose_type": "black_wet",
		"eye_type": "loyal_brown",
		"fur_color": Color(0.8, 0.6, 0.4)
	},
	"cat": {
		"name": "Cat",
		"ear_type": "pointed_upright", 
		"nose_type": "small_pink",
		"eye_type": "green_slit",
		"fur_color": Color(0.7, 0.7, 0.7)
	},
	"cow": {
		"name": "Cow",
		"ear_type": "large_floppy",
		"nose_type": "large_black",
		"eye_type": "large_brown",
		"fur_color": Color.WHITE,
		"spots": true
	},
	"fox": {
		"name": "Fox",
		"ear_type": "pointed_upright",
		"nose_type": "black_pointed",
		"eye_type": "amber_clever",
		"fur_color": Color(0.9, 0.4, 0.1)
	},
	"wolf": {
		"name": "Wolf",
		"ear_type": "pointed_upright",
		"nose_type": "black_wet",
		"eye_type": "yellow_intense",
		"fur_color": Color(0.4, 0.4, 0.4)
	},
	"bear": {
		"name": "Bear",
		"ear_type": "small_round",
		"nose_type": "large_black",
		"eye_type": "small_dark",
		"fur_color": Color(0.3, 0.2, 0.1)
	},
	"panda": {
		"name": "Panda",
		"ear_type": "round",
		"nose_type": "black",
		"eye_type": "black_ringed",
		"fur_color": Color.WHITE,
		"markings": "panda"
	}
}

# --- Character Model Scenes ---
# These are the same models used in the main game scene to ensure consistency.
# NOTE: Preloading of 3D models has been replaced with `null` because the files do not exist.
# To re-enable this, create the 3D models and restore the `preload()` calls.
const body_scene = null #preload("res://assets/models/character/body.tscn")
const ProceduralCharacterModel = preload("res://ProceduralCharacter.gd")
const animal_head_scenes = {
	"rabbit": null, #preload("res://assets/models/character/heads/rabbit_head.tscn"),
	"dog": null, #preload("res://assets/models/character/heads/dog_head.tscn"),
	"cat": null, #preload("res://assets/models/character/heads/cat_head.tscn"),
	"cow": null, #preload("res://assets/models/character/heads/cow_head.tscn"),
	"fox": null, #preload("res://assets/models/character/heads/fox_head.tscn"),
	"wolf": null, #preload("res://assets/models/character/heads/wolf_head.tscn"),
	"bear": null, #preload("res://assets/models/character/heads/bear_head.tscn"),
	"panda": null, #preload("res://assets/models/character/heads/panda_head.tscn"),
}

const body_shape_scenes = {
	"default": null, #preload("res://assets/models/character/body_default.tscn"), # A generic base body
	"male": null, #preload("res://assets/models/character/body_male.tscn"),
	"female": null, #preload("res://assets/models/character/body_female.tscn"),
}

const shirt_scenes = {
	"none": null, # Option for no shirt
	"basic_tshirt": null, #preload("res://assets/models/character/clothing/shirt_basic_tshirt.tscn"),
	"hoodie": null, #preload("res://assets/models/character/clothing/shirt_hoodie.tscn"),
}

const pants_scenes = {
	"none": null, # Option for no pants
	"jeans": null, #preload("res://assets/models/character/clothing/pants_jeans.tscn"),
	"shorts": null, #preload("res://assets/models/character/clothing/pants_shorts.tscn"),
}

const shoes_scenes = {
	"none": null, # Option for no shoes
	"sneakers": null, #preload("res://assets/models/character/clothing/shoes_sneakers.tscn"),
	"boots": null, #preload("res://assets/models/character/clothing/shoes_boots.tscn"),
}



signal character_created(character_data: Dictionary)

func _ready():
	make_layout_scrollable()
	UIManager.visible = false
	populate_options()
	update_character_preview()
	create_network_options()

func create_network_options() -> void:
	var content: VBoxContainer = $CreatorScroll/VBoxContainer
	var create_index := create_button.get_index()
	var row := HBoxContainer.new()
	row.name = "NetworkOptions"
	content.add_child(row)
	content.move_child(row, create_index)
	var host_button := Button.new()
	host_button.text = "Host game"
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "Join game"
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(join_button)
	var address := LineEdit.new()
	address.placeholder_text = "Host computer IP address (for Join)"
	address.text = "127.0.0.1"
	content.add_child(address)
	content.move_child(address, create_index + 1)
	var help := Label.new()
	help.text = "Choose Host on one computer, Join on the other, then Create Character."
	content.add_child(help)
	content.move_child(help, create_index + 2)
	host_button.pressed.connect(func():
		GameManager.network_mode = "host"
		host_button.disabled = true
		join_button.disabled = false)
	join_button.pressed.connect(func():
		GameManager.network_mode = "join"
		join_button.disabled = true
		host_button.disabled = false)
	address.text_changed.connect(func(value: String): GameManager.host_address = value.strip_edges())
	host_button.disabled = true

func make_layout_scrollable():
	# A fixed centered container clips controls on short displays or when OS
	# scaling reduces the usable client area. Reparent the content into a
	# full-window ScrollContainer so every creator field stays reachable.
	var content: VBoxContainer = $VBoxContainer
	remove_child(content)

	var scroll := ScrollContainer.new()
	scroll.name = "CreatorScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	content.set_anchors_preset(Control.PRESET_TOP_WIDE)
	content.offset_left = 0.0
	content.offset_top = 16.0
	content.offset_right = 0.0
	content.offset_bottom = 0.0
	content.custom_minimum_size.x = 500.0
	content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(content)

func setup_ui():
	"""Setup the character creation UI"""
	# Main container
	var main_container = VBoxContainer.new()

func populate_options():
	"""Add all customization options to the dropdowns"""
	# Animal Heads
	for animal_id in animal_heads.keys():
		animal_option_button.add_item(animal_heads[animal_id]["name"])
	
	# Body Shapes
	for body_shape_id in body_shape_scenes.keys():
		body_shape_option_button.add_item(body_shape_id.capitalize())

	# Shirts
	for shirt_id in shirt_scenes.keys():
		shirt_option_button.add_item(shirt_id.capitalize().replace("_", " "))

	# Pants
	for pants_id in pants_scenes.keys():
		pants_option_button.add_item(pants_id.capitalize().replace("_", " "))

	# Shoes
	for shoes_id in shoes_scenes.keys():
		shoes_option_button.add_item(shoes_id.capitalize().replace("_", " "))

func _on_any_option_changed(_value):
	# This single function can be connected to all selection signals
	update_character_preview()

func _on_color_changed(color: Color):
	"""Handle body color change"""
	update_character_preview()

func update_character_preview():
	"""Update the 3D character preview"""
	# Clear existing character
	for child in character_preview.get_children():
		if child.name == "Character":
			child.queue_free()
	
	# Get selected animal
	var selected_index = animal_option_button.selected
	if selected_index == -1:
		selected_index = 0
	
	var animal_keys = animal_heads.keys()
	var selected_animal_type = animal_keys[selected_index]

	var selected_body_shape = body_shape_scenes.keys()[body_shape_option_button.selected]
	var selected_shirt_type = shirt_scenes.keys()[shirt_option_button.selected]
	var selected_pants_type = pants_scenes.keys()[pants_option_button.selected]
	var selected_shoes_type = shoes_scenes.keys()[shoes_option_button.selected]
	
	# Create new character
	var character = create_character_model(
		selected_body_shape,
		selected_animal_type,
		body_color_picker.color,
		selected_shirt_type,
		selected_pants_type,
		selected_shoes_type
	)
	character.name = "Character"
	character_preview.add_child(character)

func create_character_model(
	body_shape_type: String,
	animal_type: String,
	body_color: Color,
	shirt_type: String = "none",
	pants_type: String = "none",
	shoes_type: String = "none"
) -> Node3D:
	return ProceduralCharacterModel.create(body_shape_type, animal_type, body_color, shirt_type, pants_type, shoes_type)

func _on_create_character():
	"""Handle character creation"""
	if username_input.text.strip_edges().length() == 0:
		# Show error
		return
	
	var selected_index = animal_option_button.selected
	if selected_index == -1:
		selected_index = 0
	
	var animal_keys = animal_heads.keys()
	var selected_animal_type = animal_keys[selected_index]

	var selected_body_shape = body_shape_scenes.keys()[body_shape_option_button.selected]
	var selected_shirt_type = shirt_scenes.keys()[shirt_option_button.selected]
	var selected_pants_type = pants_scenes.keys()[pants_option_button.selected]
	var selected_shoes_type = shoes_scenes.keys()[shoes_option_button.selected]
	
	var character_data = {
		"username": username_input.text.strip_edges(),
		"body_shape": selected_body_shape,
		"animal_type": selected_animal_type,
		"animal_name": animal_heads[selected_animal_type]["name"],
		"body_color": body_color_picker.color,
		"shirt_type": selected_shirt_type,
		"pants_type": selected_pants_type,
		"shoes_type": selected_shoes_type,
		"fur_color": animal_heads[selected_animal_type]["fur_color"] # Still useful for other logic
	}
	
	# Store data in the global game manager and switch to the main scene
	GameManager.character_data = character_data
	GameManager.go_to_main_scene()

func get_character_data() -> Dictionary:
	"""Get current character configuration"""
	var selected_index = animal_option_button.selected
	if selected_index == -1:
		selected_index = 0
	
	var animal_keys = animal_heads.keys()
	var selected_animal_type = animal_keys[selected_index]

	var selected_body_shape = body_shape_scenes.keys()[body_shape_option_button.selected]
	var selected_shirt_type = shirt_scenes.keys()[shirt_option_button.selected]
	var selected_pants_type = pants_scenes.keys()[pants_option_button.selected]
	var selected_shoes_type = shoes_scenes.keys()[shoes_option_button.selected]
	
	return {
		"username": username_input.text.strip_edges(),
		"body_shape": selected_body_shape,
		"animal_type": selected_animal_type,
		"animal_name": animal_heads[selected_animal_type]["name"],
		"body_color": body_color_picker.color,
		"shirt_type": selected_shirt_type,
		"pants_type": selected_pants_type,
		"shoes_type": selected_shoes_type,
		"fur_color": animal_heads[selected_animal_type]["fur_color"]
	}
