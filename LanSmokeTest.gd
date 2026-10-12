extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "join" if args.has("join") else "host"
	var manager := root.get_node("GameManager")
	manager.network_mode = mode
	manager.host_address = "127.0.0.1"
	manager.network_port = 24568
	manager.character_data = {"username": mode, "animal_type": "rabbit", "body_color": Color.CYAN}
	change_scene_to_file("res://Main.tscn")
	await process_frame
	await process_frame
	var game := current_scene
	if not game.minimap_panel.visible or game.minimap_view.size.x < 200.0:
		push_error("Minimap did not initialize")
	var map_key := InputEventKey.new()
	map_key.physical_keycode = KEY_M
	map_key.pressed = true
	game._unhandled_input(map_key)
	if game.minimap_panel.visible:
		push_error("M did not hide the minimap")
	game._unhandled_input(map_key)
	if not game.minimap_panel.visible:
		push_error("M did not show the minimap")
	if mode == "host":
		if game.obstacle_zones.size() < 80:
			push_error("Expanded terrain did not generate")
		if game.balloon_stations.size() != 4 or game.animals.size() != 17:
			push_error("Remote places, balloons, or wildlife did not generate")
		game.add_creation(Vector3i(6, 0, 6), Color.RED)
		game.scores[0] = 20
		game.scores[1] = 15
		game.process_shop_action(0, "car")
		game.process_shop_action(0, "food")
		game.players[0].position = Vector3(42, 1, -2)
		game.begin_balloon_flight(0, 0)
		await create_timer(16.0).timeout
		if game.creations.has(Vector3i(4, 0, 4)):
			print("LAN_SMOKE_HOST_OK")
		else:
			push_error("Host did not receive client's block")
		if game.active_vehicle[0] != "car" or game.scores[0] != 6:
			push_error("Host purchases failed")
		if game.active_vehicle[1] != "motorbike" or game.scores[1] != 6:
			push_error("Guest purchase did not reach host")
		if not game.balloon_flights[0].is_empty() or absf(game.players[0].position.x - 86.0) > 2.0:
			push_error("Host balloon did not arrive in the mountains")
	else:
		await create_timer(6.0).timeout
		if game.crystal_nodes.size() != 36:
			push_error("Client did not receive initial crystals")
		if game.obstacle_zones.size() < 80:
			push_error("Client terrain did not generate")
		if game.balloon_stations.size() != 4 or game.animals.size() != 17:
			push_error("Client remote places or wildlife did not generate")
		if game.balloon_flights[0].is_empty() or not game.players[0].get_node_or_null("HotAirBalloon"):
			push_error("Client did not see host's balloon flight")
		if not game.creations.has(Vector3i(6, 0, 6)):
			push_error("Client did not receive existing blocks")
		if game.active_vehicle[0] != "car" or game.scores[0] != 6:
			push_error("Client did not receive host purchases")
		game.request_build_on_host.rpc_id(1, true, Vector2i(4, 4))
		game.request_shop_action.rpc_id(1, "motorbike")
		await create_timer(1.0).timeout
		if game.creations.has(Vector3i(4, 0, 4)):
			print("LAN_SMOKE_CLIENT_OK")
		else:
			push_error("Client did not receive shared block")
		if game.active_vehicle[1] != "motorbike" or game.scores[1] != 6:
			push_error("Client purchase failed")
	quit()
