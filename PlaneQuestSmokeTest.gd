extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var manager := root.get_node("GameManager")
	manager.network_mode = "host"
	manager.network_port = 24572
	manager.character_data = {"username": "plane-test", "animal_type": "rabbit", "body_color": Color.CYAN}
	change_scene_to_file("res://Main.tscn")
	await process_frame
	await process_frame
	var game := current_scene
	if game.material_nodes.size() != 8 or game.balloon_stations.size() != 16:
		push_error("Nine-world plane quest did not initialize")
	for island in ["CrystalCavernsIsland", "VolcanoIsland", "GoldenDunesIsland", "JungleRuinsIsland"]:
		if not game.get_node_or_null(island): push_error("Missing new world: %s" % island)
	for id in game.PLANE_PARTS:
		var pos: Vector3 = game.PLANE_PARTS[id].position
		for zone in game.obstacle_zones:
			if zone.has_point(Vector2(pos.x, pos.z)):
				push_error("Plane material blocked by obstacle: %s" % id)
	game.process_workshop(0)
	if game.owned_items[0].has("plane"):
		push_error("Plane built without blueprint or parts")
	game.scores[0] = 20
	game.process_shop_action(0, "blueprint")
	if not game.owned_items[0].has("blueprint") or not game.blueprint_text.text.contains("Crystal Caverns"):
		push_error("Purchasable blueprint did not open instructions")
	game.process_workshop(0)
	if game.owned_items[0].has("plane"):
		push_error("Plane built before finding materials")
	for id in game.PLANE_PARTS:
		game.collect_plane_material(0, id)
	if game.found_parts[0].size() != 8:
		push_error("Plane part inventory did not fill")
	for id in game.material_nodes:
		if game.material_nodes[id].visible: push_error("Collected part remains visible: %s" % id)
	game.process_workshop(0)
	if not game.owned_items[0].has("plane") or game.active_vehicle[0] != "plane":
		push_error("Plane assembly failed")
	if not game.players[0].get_node_or_null("Vehicle"):
		push_error("Plane model missing")
	game.players[0].position = Vector3(61, 10, 0)
	Input.action_press("move_right")
	await physics_frame
	await physics_frame
	await physics_frame
	Input.action_release("move_right")
	if game.players[0].position.x <= 61.0 or game.players[0].position.y < 9.8:
		push_error("Plane failed to fly over the gap")
	var altitude: float = game.players[0].position.y
	Input.action_press("jump")
	for frame in 4: await physics_frame
	Input.action_release("jump")
	if game.players[0].position.y <= altitude + 0.3:
		push_error("Plane climb control failed")
	altitude = game.players[0].position.y
	Input.action_press("plane_descend")
	for frame in 4: await physics_frame
	Input.action_release("plane_descend")
	if game.players[0].position.y >= altitude - 0.3:
		push_error("Plane descend control failed")
	game.players[0].position = Vector3(0, 2.8, 2)
	game.process_workshop(0)
	if game.active_vehicle[0] != "":
		push_error("Plane could not be parked")
	print("PLANE_QUEST_SMOKE_OK")
	quit()
