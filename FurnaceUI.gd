extends Panel

signal output_taken
signal close_requested

@onready var input_slot: Panel = $Margin/VBox/HBox/InputVBox/InputSlot
@onready var fuel_slot: Panel = $Margin/VBox/HBox/InputVBox/FuelSlot
@onready var output_slot: Panel = $Margin/VBox/HBox/OutputSlot
@onready var burn_progress: ProgressBar = $Margin/VBox/HBox/ProgressVBox/BurnProgress
@onready var cook_progress: ProgressBar = $Margin/VBox/HBox/ProgressVBox/CookProgress
@onready var close_button: Button = $Margin/VBox/CloseButton

var furnace_pos: Vector3i

func _ready():
	hide()
	output_slot.slot_clicked.connect(func(_slot): emit_signal("output_taken"))
	close_button.pressed.connect(func(): emit_signal("close_requested"))

func open_ui(pos: Vector3i, state: Dictionary):
	furnace_pos = pos
	update_state(state)
	show()

func update_state(state: Dictionary):
	# Update input slot
	if state.has("input") and not state.input.is_empty():
		input_slot.set_item(state.input)
	else:
		input_slot.clear_slot()

	# Update fuel slot
	if state.has("fuel") and not state.fuel.is_empty():
		fuel_slot.set_item(state.fuel)
	else:
		fuel_slot.clear_slot()

	# Update output slot
	if state.has("output") and not state.output.is_empty():
		output_slot.set_item(state.output)
	else:
		output_slot.clear_slot()
	
	# Update progress bars
	burn_progress.max_value = 80 # Max burn time of coal
	burn_progress.value = state.get("burn_time", 0)
	
	cook_progress.max_value = 10 # Most recipes take 10 ticks
	cook_progress.value = state.get("cook_time", 0)