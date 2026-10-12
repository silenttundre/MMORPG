extends Panel

signal craft_item_requested(item_id)

@onready var recipe_list: VBoxContainer = $Margin/VBox/ScrollContainer/RecipeList

const RecipeSlot = preload("res://RecipeSlot.tscn")

func _ready():
	hide()

func populate_recipes(recipes: Dictionary, item_definitions: Dictionary):
	for child in recipe_list.get_children():
		child.queue_free()
		
	for item_id in recipes:
		var recipe_data = recipes[item_id]
		var slot = RecipeSlot.instantiate()
		slot.set_data(item_id, recipe_data, item_definitions)
		slot.craft_requested.connect(_on_craft_requested)
		recipe_list.add_child(slot)

func _on_craft_requested(item_id: String):
	emit_signal("craft_item_requested", item_id)