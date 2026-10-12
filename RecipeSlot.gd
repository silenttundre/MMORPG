extends PanelContainer

signal craft_requested(item_id)

@onready var item_icon: TextureRect = $HBox/ItemIcon
@onready var item_name: Label = $HBox/VBox/ItemName
@onready var ingredients_container: HBoxContainer = $HBox/VBox/IngredientsContainer
@onready var craft_button: Button = $HBox/CraftButton

const InventorySlotScene = preload("res://InventorySlot.tscn")

var item_id_to_craft: String

func _ready():
	craft_button.pressed.connect(_on_craft_button_pressed)

func set_data(item_id: String, recipe_data: Dictionary, item_definitions: Dictionary):
	item_id_to_craft = item_id
	
	var item_name_str = "Unknown"
	for key in item_definitions:
		if str(item_definitions[key]) == item_id:
			item_name_str = key.capitalize().replace("_", " ")
			break
	item_name.text = item_name_str

	var icon_path = "res://assets/icons/items/%s.png" % item_id
	if ResourceLoader.exists(icon_path):
		item_icon.texture = load(icon_path)
	
	for child in ingredients_container.get_children():
		child.queue_free()
		
	var ingredients = recipe_data.get("ingredients", {})
	for ingredient_id in ingredients:
		var required_qty = ingredients[ingredient_id]
		var ingredient_slot = InventorySlotScene.instantiate()
		ingredient_slot.custom_minimum_size = Vector2(24, 24)
		ingredient_slot.set_item({"item_id": int(ingredient_id), "quantity": required_qty})
		ingredients_container.add_child(ingredient_slot)

func _on_craft_button_pressed():
	emit_signal("craft_requested", item_id_to_craft)