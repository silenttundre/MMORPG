extends Control

@onready var health_bar: ProgressBar = $MarginContainer/VBox/HealthBar
@onready var hunger_bar: ProgressBar = $MarginContainer/VBox/HungerBar

func _ready():
	health_bar.max_value = 100
	hunger_bar.max_value = 20

func update_stats(stats: Dictionary):
	if stats.has("health"):
		health_bar.value = stats.health
	if stats.has("hunger"):
		hunger_bar.value = stats.hunger
