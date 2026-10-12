extends Control

signal hotbar_selection_changed(item_data)
signal inventory_item_clicked_for_interaction(inventory_key)

const InventorySlot = preload("res://InventorySlot.tscn")

@onready var inventory_grid: GridContainer = $CenterContainer/Panel/Margin/InventoryGrid
@onready var hotbar_grid: GridContainer = $HotbarPanel/Margin/HotbarGrid

var hotbar_slots: Array[Node] = []
var inventory_slots: Array[Node] = []
var all_slots: Array[Node] = []
var inventory_order: Array = [] # Stores the inventory_keys in display order
var interaction_mode: String = "none" # "none" or "furnace"

var selected_hotbar_index = 0

func _ready():
	# Create hotbar slots
	for i in range(9):
		var slot = InventorySlot.instantiate()
		hotbar_grid.add_child(slot)
		hotbar_slots.append(slot)
		slot.slot_clicked.connect(_on_slot_clicked.bind(slot))
		slot.swap_requested.connect(_on_swap_requested)

	# Create main inventory slots
	for i in range(27):
		var slot = InventorySlot.instantiate()
		inventory_grid.add_child(slot)
		inventory_slots.append(slot)
		slot.slot_clicked.connect(_on_slot_clicked.bind(slot))
		slot.swap_requested.connect(_on_swap_requested)
		
	all_slots = hotbar_slots + inventory_slots
	
	# Initial selection highlight
	select_hotbar_slot(0)

func update_inventory(data: Dictionary):
	var server_inventory = data.get("inventory", {})
	var server_keys = server_inventory.keys()

	# Check if the set of keys has changed. If so, rebuild the order.
	# This handles items being added or removed from the inventory.
	var current_keys_sorted = inventory_order.filter(func(k): return k != null)
	current_keys_sorted.sort()
	var server_keys_sorted = server_keys.duplicate()
	server_keys_sorted.sort()

	if current_keys_sorted != server_keys_sorted:
		# Rebuild the order, trying to preserve existing positions.
		var new_order = all_slots.map(func(s): return s.item_data.get("inventory_key"))
		var new_server_keys = server_keys.filter(func(k): return not k in new_order)
		
		# Add brand new items to the first available empty slots.
		for key in new_server_keys:
			var empty_idx = new_order.find(null)
			if empty_idx != -1:
				new_order[empty_idx] = key
		
		inventory_order = new_order

	rerender_all_slots(server_inventory)

func rerender_all_slots(full_inventory_data: Dictionary):
	"""Renders all slots based on the current inventory_order and data."""
	for i in range(all_slots.size()):
		var slot = all_slots[i]
		var item_key = inventory_order[i] if i < inventory_order.size() else null

		if item_key == null or not full_inventory_data.has(item_key):
			slot.clear_slot()
		else:
			var item_info = full_inventory_data[item_key]
			var slot_data = item_info.duplicate()
			slot_data["inventory_key"] = item_key

			if "quantity" in slot_data and not "item_id" in slot_data:
				slot_data["item_id"] = int(item_key)
			
			slot.set_item(slot_data)
	
	# After re-rendering, ensure the hotbar selection is still correct
	select_hotbar_slot(selected_hotbar_index)

func _on_slot_clicked(slot_node):
	if interaction_mode == "furnace":
		if not slot_node.item_data.is_empty():
			emit_signal("inventory_item_clicked_for_interaction", slot_node.item_data.inventory_key)
	else: # Default behavior
		var index = hotbar_slots.find(slot_node)
		if index != -1:
			select_hotbar_slot(index)

func set_interaction_mode(mode: String):
	interaction_mode = mode
	print("Inventory interaction mode set to: ", mode)

func _on_swap_requested(source_slot: Node, target_slot: Node):
	"""Handles the visual swapping of items in the UI by reordering them."""
	var source_index = all_slots.find(source_slot)
	var target_index = all_slots.find(target_slot)

	if source_index == -1 or target_index == -1: return

	# Swap the keys in our ordering array
	var temp_key = inventory_order[source_index]
	inventory_order[source_index] = inventory_order[target_index]
	inventory_order[target_index] = temp_key

	# Optimistically swap the data in the slots for immediate visual feedback
	var source_data = source_slot.item_data
	var target_data = target_slot.item_data
	source_slot.set_item(target_data)
	target_slot.set_item(source_data)
	
	# If the swap involved the selected hotbar slot, update the 'held item'
	if source_index < 9 or target_index < 9:
		select_hotbar_slot(selected_hotbar_index)

func select_hotbar_slot(index: int):
	# Remove highlight from old slot
	hotbar_slots[selected_hotbar_index].modulate = Color.WHITE
	
	selected_hotbar_index = index
	# Add highlight to new slot
	hotbar_slots[selected_hotbar_index].modulate = Color(1.5, 1.5, 1.0) # Yellowish tint
	
	var selected_item_data = hotbar_slots[selected_hotbar_index].item_data
	emit_signal("hotbar_selection_changed", selected_item_data)