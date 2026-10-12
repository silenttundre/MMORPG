extends CanvasLayer

const PlayerStatsUI = preload("res://PlayerStatsUI.tscn")
const InventoryUI = preload("res://InventoryUI.tscn")
const CraftingUI = preload("res://CraftingUI.tscn")
const FurnaceUI = preload("res://FurnaceUI.tscn")

var player_stats_ui
var inventory_ui
var crafting_ui
var furnace_ui

func _ready():
	# Instantiate and add UI scenes as children of this CanvasLayer
	player_stats_ui = PlayerStatsUI.instantiate()
	add_child(player_stats_ui)
	
	inventory_ui = InventoryUI.instantiate()
	add_child(inventory_ui)

	crafting_ui = CraftingUI.instantiate()
	add_child(crafting_ui)
	crafting_ui.hide()

	furnace_ui = FurnaceUI.instantiate()
	add_child(furnace_ui)

func update_player_stats(stats: Dictionary):
	if player_stats_ui:
		player_stats_ui.update_stats(stats)

func update_inventory(data: Dictionary):
	if inventory_ui:
		inventory_ui.update_inventory(data)

func set_crafting_recipes(recipes: Dictionary, item_definitions: Dictionary):
	if crafting_ui:
		crafting_ui.populate_recipes(recipes, item_definitions)

func toggle_crafting_window():
	if crafting_ui:
		crafting_ui.visible = not crafting_ui.visible

func open_furnace_window(pos: Vector3i, state: Dictionary):
	if furnace_ui:
		furnace_ui.open_ui(pos, state)
		inventory_ui.set_interaction_mode("furnace")

func update_furnace_window(state: Dictionary):
	if furnace_ui and furnace_ui.visible:
		furnace_ui.update_state(state)

func close_furnace_window():
	if furnace_ui and furnace_ui.visible:
		furnace_ui.hide()
		inventory_ui.set_interaction_mode("none")

func is_ui_open() -> bool:
	return (crafting_ui and crafting_ui.visible) or (furnace_ui and furnace_ui.visible)