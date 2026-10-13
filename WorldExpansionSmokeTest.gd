extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var manager := root.get_node("GameManager")
	manager.network_mode = "host"
	manager.network_port = 24571
	manager.character_data = {"username": "world-test", "animal_type": "rabbit", "body_color": Color.CYAN}
	change_scene_to_file("res://Main.tscn")
	await process_frame
	await process_frame
	var game := current_scene
	if game.score_panel.color.a < 0.95 or game.location_panel.color.a < 0.95 or game.health_panel.color.a < 0.95:
		push_error("HUD contrast panels missing")
	if game.score_label.get_parent() != game.score_panel or game.location_label.get_parent() != game.location_panel:
		push_error("Crystal or location display has no contrast backing")
	if game.balloon_stations.size() != 16 or game.enemy_states.size() != 23 or game.animals.size() != 25:
		push_error("Expanded worlds, wildlife, or balloon routes missing")
	if not game.animal_kinds.has("whale") or not game.animal_kinds.has("fish"):
		push_error("Peaceful lake animals missing")
	if game.enemy_states[10].maximum != 100 or game.enemy_states[14].maximum != 160 or game.enemy_states[16].maximum != 75:
		push_error("Arctic or shark enemy strength missing")
	if not game.is_lake_water(Vector3(0, 1, 112)) or game.is_lake_water(Vector3(0, 1, 80)):
		push_error("Lake water bounds incorrect")
	game.scores[0] = 30
	game.process_shop_action(0, "rowboat")
	if game.active_vehicle[0] != "rowboat" or not game.players[0].get_node_or_null("Vehicle"):
		push_error("Rowboat purchase failed")
	game.process_shop_action(0, "speedboat")
	if game.active_vehicle[0] != "speedboat":
		push_error("Speedboat purchase failed")
	var shark: Dictionary = game.enemy_states[16]
	game.players[0].position = shark.position
	game.remote_walk_speed[0] = 0.0
	game.resolve_enemy_contact(16, 0)
	if game.player_health[0] != 95:
		push_error("Speedboat shark protection failed")
	shark.attack_timer = 0.0
	game.active_vehicle[0] = "rowboat"
	game.resolve_enemy_contact(16, 0)
	if game.player_health[0] != 77:
		push_error("Rowboat shark protection failed")
	shark.attack_timer = 0.0
	game.active_vehicle[0] = ""
	game.resolve_enemy_contact(16, 0)
	if game.player_health[0] != 100 or game.players[0].position.z != 2.0:
		push_error("Unprotected shark attack did not defeat player")
	print("WORLD_EXPANSION_SMOKE_OK")
	quit()
