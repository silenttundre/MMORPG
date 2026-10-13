extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var args := OS.get_cmdline_user_args()
	var role := "host" if args.is_empty() else args[0]
	var manager := root.get_node("GameManager")
	manager.network_mode = "host" if role == "host" else "join"
	manager.host_address = "127.0.0.1"
	manager.network_port = 24570
	manager.character_data = {"username": role, "animal_type": "rabbit", "body_color": Color.CYAN}
	change_scene_to_file("res://Main.tscn")
	await process_frame
	await process_frame
	var game := current_scene
	if game.balloon_stations.size() != 16 or game.enemy_states.size() != 23 or game.animals.size() != 25:
		push_error("New worlds did not initialize across LAN")
	if role == "host":
		game.add_crystal(1000, Vector3(8, 1, 2))
		for attempt in 250:
			if game.peer_slots.size() == 2: break
			await create_timer(0.1).timeout
		if game.players.size() < 3 or game.peer_slots.size() != 2:
			push_error("Two guests did not join")
		for attempt in 250:
			if not game.crystal_nodes.has(1000): break
			await create_timer(0.1).timeout
		game.players[1].position = Vector3(42, 1, -2)
		game.relay_position.rpc(1, game.players[1].position, 0.0, 0.0)
		for attempt in 250:
			if not game.balloon_flights[1].is_empty(): break
			await create_timer(0.1).timeout
		if game.crystal_nodes.has(1000) or game.scores[1] < 1:
			push_error("Player 2 did not collect crystal")
		if game.balloon_flights[1].is_empty():
			push_error("Player 2 did not board balloon")
		print("MULTI_LAN_HOST_OK")
	elif role == "first":
		for attempt in 250:
			if game.local_index() == 1 and game.crystal_nodes.has(1000): break
			await create_timer(0.1).timeout
		if game.local_index() != 1 or not game.crystal_nodes.has(1000):
			push_error("Player 2 did not receive slot or crystal")
		game.request_crystal.rpc_id(1, 1000, Vector3(8, 1, 2))
		for attempt in 250:
			if game.scores[1] >= 1: break
			await create_timer(0.1).timeout
		await create_timer(1.0).timeout
		game.players[1].position = Vector3(42, 1, -2)
		game.request_balloon.rpc_id(1, 0, game.players[1].position)
		for attempt in 250:
			if not game.balloon_flights[1].is_empty(): break
			await create_timer(0.1).timeout
		if game.balloon_flights[1].is_empty() or game.scores[1] < 1:
			push_error("Player 2 pickup or balloon state failed")
		print("MULTI_LAN_FIRST_OK")
	else:
		for attempt in 250:
			if game.local_index() == 2 and game.scores[1] >= 1: break
			await create_timer(0.1).timeout
		if game.local_index() != 2 or game.players.size() < 3:
			push_error("Player 3 did not receive unique slot")
		if game.crystal_nodes.has(1000) or game.scores[1] < 1:
			push_error("Player 3 did not receive shared crystal state")
		print("MULTI_LAN_SECOND_OK")
	quit()
