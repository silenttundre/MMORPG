extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var manager := root.get_node("GameManager")
	manager.network_mode = "host"
	manager.network_port = 24569
	manager.character_data = {"username": "combat-test", "animal_type": "rabbit", "body_color": Color.CYAN}
	change_scene_to_file("res://Main.tscn")
	await process_frame
	await process_frame
	var game := current_scene
	if game.enemy_states.size() != 23 or game.health_bars.size() != 2:
		push_error("Enemy or player health UI setup failed")
		quit()
		return
	var skeleton: Dictionary = game.enemy_states[0]
	game.players[0].position = skeleton.position + Vector3(0, 0, -1)
	game.players[0].rotation.y = 0.0
	game.attack_nearest_enemy(0)
	if skeleton.health != 30:
		push_error("Unarmed attack failed")
	game.owned_items[0]["sword"] = true
	game.attack_cooldown[0] = 0.0
	game.attack_nearest_enemy(0)
	if skeleton.health != 6:
		push_error("Sword attack failed")
	game.attack_cooldown[0] = 0.0
	game.attack_nearest_enemy(0)
	if skeleton.alive or game.scores[0] != 1:
		push_error("Enemy defeat or crystal reward failed")
	game.active_vehicle[0] = "bicycle"
	game.players[0].position = game.enemy_states[1].position + Vector3(0.5, 0, 0)
	game.players[0].velocity = Vector3(5, 0, 0)
	game.resolve_enemy_contact(1, 0)
	if game.player_health[0] != 96 or game.enemy_states[1].health != 28:
		push_error("Bicycle collision damage failed")
	game.active_vehicle[0] = "car"
	game.players[0].position = game.enemy_states[2].position + Vector3(0.5, 0, 0)
	game.resolve_enemy_contact(2, 0)
	if game.enemy_states[2].alive or game.player_health[0] != 96:
		push_error("Car did not safely run over enemy")
	game.scores[0] = 2
	game.process_shop_action(0, "food")
	if game.player_health[0] != 100 or game.scores[0] != 0 or game.food_time[0] < 19.0:
		push_error("Snack healing failed")
	game.active_vehicle[0] = ""
	game.players[0].velocity = Vector3.ZERO
	game.players[0].position = game.enemy_states[3].position + Vector3(0.5, 0, 0)
	game.resolve_enemy_contact(3, 0)
	if game.player_health[0] != 88:
		push_error("Skeleton bite damage failed")
	game.players[0].position = game.enemy_states[4].position + Vector3(0.5, 0, 0)
	game.resolve_enemy_contact(4, 0)
	if game.player_health[0] != 80:
		push_error("Bat bite damage failed")
	game.player_health[0] = 5
	game.damage_player(0, 12)
	if game.player_health[0] != 100 or game.players[0].position.x != -2.0:
		push_error("Player respawn failed")
	print("COMBAT_SMOKE_OK")
	quit()
