extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var mode := "guest" if OS.get_cmdline_user_args().has("guest") else "host"
	var manager := root.get_node("GameManager")
	manager.network_mode = "host" if mode == "host" else "join"
	manager.host_address = "127.0.0.1"
	manager.network_port = 24573
	manager.character_data = {"username": mode, "animal_type": "rabbit", "body_color": Color.CYAN}
	change_scene_to_file("res://Main.tscn")
	await process_frame
	await process_frame
	var game := current_scene
	if mode == "host":
		for attempt in 250:
			if game.peer_slots.size() == 1: break
			await create_timer(0.1).timeout
		game.scores[1] = 20
		game.sync_shop_state.rpc(game.scores, game.owned_items, game.active_vehicle, game.food_time)
		var part_pos: Vector3 = game.PLANE_PARTS["timber"].position
		game.players[1].position = part_pos
		game.respawn_player_remote.rpc(1, part_pos)
		for attempt in 250:
			if game.found_parts[1].has("timber"): break
			await create_timer(0.1).timeout
		if not game.found_parts[1].has("timber"):
			push_error("Guest did not collect plane material")
		for attempt in 250:
			if game.owned_items[1].has("blueprint"): break
			await create_timer(0.1).timeout
		if not game.owned_items[1].has("blueprint"):
			push_error("Guest could not buy blueprint")
		for id in game.PLANE_PARTS:
			game.collect_plane_material(1, id)
		game.players[1].position = Vector3(0, 1, 2)
		game.respawn_player_remote.rpc(1, game.players[1].position)
		for attempt in 250:
			if game.owned_items[1].has("plane"): break
			await create_timer(0.1).timeout
		if not game.owned_items[1].has("plane") or game.active_vehicle[1] != "plane":
			push_error("Guest could not assemble plane")
		await create_timer(1.0).timeout
		print("PLANE_LAN_HOST_OK")
	else:
		for attempt in 250:
			if game.local_index() == 1 and game.found_parts[1].has("timber"): break
			await create_timer(0.1).timeout
		if not game.found_parts[1].has("timber") or game.material_nodes["timber"].visible:
			push_error("Guest material pickup not synchronized")
		game.request_shop_action.rpc_id(1, "blueprint")
		for attempt in 250:
			if game.found_parts[1].size() == 8 and game.owned_items[1].has("blueprint") and game.nearby_workshop(1): break
			await create_timer(0.1).timeout
		game.request_workshop.rpc_id(1, game.players[1].position)
		for attempt in 250:
			if game.owned_items[1].has("plane"): break
			await create_timer(0.1).timeout
		if game.active_vehicle[1] != "plane":
			push_error("Guest did not receive assembled plane")
		print("PLANE_LAN_GUEST_OK")
	quit()
