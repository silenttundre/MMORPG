extends Node3D

# LAN creative playground. The host owns shared world state.
const CharacterFactory = preload("res://ProceduralCharacter.gd")
const VehicleVisuals = preload("res://VehicleFactory.gd")
const MinimapView = preload("res://Minimap.gd")
const BalloonVisuals = preload("res://BalloonFactory.gd")
const AnimalVisuals = preload("res://AnimalFactory.gd")
const EnemyVisuals = preload("res://EnemyFactory.gd")
const MAIN_HALF := Vector2i(56, 45)
const WORLD_HALF := Vector2i(190, 190)
const LAKE_WATER := Rect2(-42, 83, 84, 58)
const CRYSTALS_PER_ROUND := 36
const BALLOON_TRAVEL_TIME := 14.0
const SPEED := 7.0
const JUMP_SPEED := 8.5
const GRAVITY := 22.0
const MAX_HEALTH := 100
const MAX_PLAYERS := 32
const WORKSHOP_POS := Vector3(0, 1, 0)
const PLANE_PARTS := {
	"timber": {"label": "Wing timber", "world": "Wildwood", "position": Vector3(-155, 0.75, 36), "color": Color("91dfa5")},
	"engine": {"label": "Engine core", "world": "Mountains", "position": Vector3(155, 0.75, 36), "color": Color("a4d8f4")},
	"propeller": {"label": "Propeller", "world": "Arctic", "position": Vector3(-55, 0.75, -149), "color": Color("c7ebf2")},
	"alloy": {"label": "Light alloy", "world": "Lake", "position": Vector3(55, 0.75, 150), "color": Color("90d6da")},
	"lens": {"label": "Navigation lens", "world": "Crystal Caverns", "position": Vector3(-157, 0.75, -148), "color": Color("d2afff")},
	"fuel": {"label": "Fuel cell", "world": "Volcano", "position": Vector3(157, 0.75, -148), "color": Color("ffab76")},
	"fabric": {"label": "Wing fabric", "world": "Golden Dunes", "position": Vector3(-157, 0.75, 148), "color": Color("ffe2a1")},
	"compass": {"label": "Compass", "world": "Jungle Ruins", "position": Vector3(157, 0.75, 148), "color": Color("b1f2b2")}
}
const SHOP_ITEMS := {
	"food": {"label": "Snack - heal 30 HP + speed boost", "cost": 2},
	"lantern": {"label": "Lantern - portable light", "cost": 3},
	"boots": {"label": "Speed boots - permanent boost", "cost": 5},
	"sword": {"label": "Sword - stronger attacks", "cost": 4},
	"bicycle": {"label": "Bicycle - faster travel", "cost": 6},
	"motorbike": {"label": "Motorbike - quick travel", "cost": 9},
	"car": {"label": "Car - fastest travel", "cost": 12},
	"rowboat": {"label": "Rowboat - cross the lake", "cost": 7},
	"speedboat": {"label": "Speedboat - fast lake travel", "cost": 13},
	"blueprint": {"label": "Plane blueprint - assembly guide [P]", "cost": 8}
}

var players: Array[CharacterBody3D] = []
var facing: Array[Vector3] = [Vector3.FORWARD, Vector3.FORWARD]
var cooldowns: Array[float] = [0.0, 0.0]
var creations: Dictionary = {}
var scores: Array[int] = [0, 0]
var crystals_collected := 0
var owned_items: Array[Dictionary] = [{}, {}]
var active_vehicle: Array[String] = ["", ""]
var food_time: Array[float] = [0.0, 0.0]
var player_health: Array[int] = [MAX_HEALTH, MAX_HEALTH]
var health_bars: Array[ProgressBar] = []
var attack_cooldown: Array[float] = [0.0, 0.0]
var camera: Camera3D
var score_label: Label
var score_panel: ColorRect
var message_label: Label
var message_time := 0.0
var rng := RandomNumberGenerator.new()
var obstacle_zones: Array[Rect2] = []
var location_label: Label
var location_panel: ColorRect
var palette := [Color("ef6f6c"), Color("ffd166"), Color("61d095"), Color("5aa9e6"), Color("b388eb"), Color("ff9f1c")]
var crystal_nodes: Dictionary = {}
var material_nodes: Dictionary = {}
var found_parts: Array[Dictionary] = [{}, {}]
var next_crystal_id := 0
var connected := false
var peer_slots: Dictionary = {}
var my_slot := 0
var appearances: Array[Dictionary] = []
var health_panel: ColorRect
var health_scroll: ScrollContainer
var health_list: Control
var position_timer := 0.0
var pickup_timer := 0.0
var walk_phase: Array[float] = [0.0, 0.0]
var walk_amount: Array[float] = [0.0, 0.0]
var remote_walk_speed: Array[float] = [0.0, 0.0]
var last_safe_position: Array[Vector3] = [Vector3(-2, 1, 2), Vector3(2, 1, 2)]
var balloon_flights: Array[Dictionary] = [{}, {}]
var balloon_stations: Array[Dictionary] = []
var animals: Array[Node3D] = []
var animal_origins: Array[Vector3] = []
var animal_kinds: Array[String] = []
var enemy_states: Dictionary = {}
var enemy_nodes: Dictionary = {}
var enemy_targets: Dictionary = {}
var enemy_sync_timer := 0.0
var world_clock := 0.0
var shop_panel: PanelContainer
var shop_buttons: Dictionary = {}
var shop_status: Label
var blueprint_panel: PanelContainer
var blueprint_text: Label
var minimap_panel: PanelContainer
var minimap_view: Control
var minimap_timer := 0.0


func _ready() -> void:
	rng.seed = 481516
	UIManager.visible = false
	setup_plane_input()
	make_world()
	make_players()
	appearances = [GameManager.character_data.duplicate(), {}]
	make_camera()
	make_hud()
	setup_network()
	if GameManager.network_mode == "host":
		spawn_crystals(CRYSTALS_PER_ROUND)
		show_message("Hosting on UDP port %d. Waiting for friends..." % GameManager.network_port, 8.0)
	else:
		show_message("Connecting to %s..." % GameManager.host_address, 8.0)


func setup_plane_input() -> void:
	if InputMap.has_action("plane_descend"): return
	InputMap.add_action("plane_descend")
	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	InputMap.action_add_event("plane_descend", shift)


func setup_network() -> void:
	print("LAN setup: ", GameManager.network_mode, " port ", GameManager.network_port)
	var peer := ENetMultiplayerPeer.new()
	var error := OK
	if GameManager.network_mode == "host":
		error = peer.create_server(GameManager.network_port, MAX_PLAYERS - 1)
	else:
		error = peer.create_client(GameManager.host_address, GameManager.network_port)
	if error != OK:
		show_message("Network error %d. Check the address and port %d." % [error, GameManager.network_port], 30.0)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(on_peer_connected)
	multiplayer.peer_disconnected.connect(on_peer_disconnected)
	multiplayer.connected_to_server.connect(on_connected_to_server)
	multiplayer.connection_failed.connect(on_connection_failed)
	multiplayer.server_disconnected.connect(on_server_disconnected)
	if GameManager.network_mode == "host":
		connected = true


func on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server(): return
	var index := 1
	while peer_slots.values().has(index): index += 1
	peer_slots[peer_id] = index
	ensure_player_slot(index)
	players[index].visible = true
	assign_player_slot.rpc_id(peer_id, index)
	show_message("Player %d joined!" % (index + 1), 4.0)


@rpc("authority", "reliable")
func assign_player_slot(index: int) -> void:
	my_slot = index
	ensure_player_slot(index)
	connected = true
	if health_scroll: health_scroll.scroll_vertical = index * 31
	set_player_appearance(index, GameManager.character_data)
	send_appearance.rpc_id(1, GameManager.character_data)
	request_world.rpc_id(1)


func slot_for_sender() -> int:
	return int(peer_slots.get(multiplayer.get_remote_sender_id(), -1))


func ensure_player_slot(index: int) -> void:
	while players.size() <= index:
		var slot := players.size()
		var spawn := Vector3(-2.0 + float(slot % 6) * 2.0, 1.0, 2.0 + float(slot / 6) * 2.0)
		players.append(make_player("Player %d" % (slot + 1), spawn, Color("ff9b9b"), "fox"))
		facing.append(Vector3.FORWARD)
		cooldowns.append(0.0)
		scores.append(0)
		owned_items.append({})
		found_parts.append({})
		active_vehicle.append("")
		food_time.append(0.0)
		player_health.append(MAX_HEALTH)
		attack_cooldown.append(0.0)
		walk_phase.append(0.0)
		walk_amount.append(0.0)
		remote_walk_speed.append(0.0)
		last_safe_position.append(spawn)
		balloon_flights.append({})
		appearances.append({})
		add_health_bar(slot)
	update_score()


@rpc("any_peer", "reliable")
func request_world() -> void:
	if not multiplayer.is_server() or slot_for_sender() < 0: return
	var peer_id := multiplayer.get_remote_sender_id()
	var snapshot: Array = []
	for key in creations:
		snapshot.append([key, (creations[key] as StaticBody3D).get_child(0).material_override.albedo_color])
	var crystals: Array = []
	for id in crystal_nodes:
		crystals.append([id, crystal_nodes[id].position])
	var positions: Array = []
	var rotations: Array = []
	for body in players:
		positions.append(body.position)
		rotations.append(body.rotation.y)
	receive_world.rpc_id(peer_id, snapshot, crystals, scores, owned_items, active_vehicle, food_time, player_health, enemy_states, positions, rotations, appearances, world_clock, balloon_flights, found_parts)


func on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server() and peer_slots.has(peer_id):
		var index: int = peer_slots[peer_id]
		peer_slots.erase(peer_id)
		players[index].visible = false
		player_left.rpc(index)
		show_message("Player %d disconnected." % (index + 1), 5.0)


@rpc("authority", "reliable")
func player_left(index: int) -> void:
	if index < players.size(): players[index].visible = false


func on_connected_to_server() -> void:
	print("LAN client: connected")
	show_message("Connected; joining world...", 4.0)


func on_connection_failed() -> void:
	connected = false
	show_message("Could not connect. Check the host IP and Windows firewall (UDP %d)." % GameManager.network_port, 30.0)


func on_server_disconnected() -> void:
	connected = false
	show_message("Disconnected from host. Return to menu to reconnect.", 30.0)


@rpc("authority", "reliable")
func receive_world(snapshot: Array, crystals: Array, new_scores: Array, new_owned: Array, new_vehicles: Array, new_food_time: Array, new_health: Array, new_enemies: Dictionary, positions: Array, rotations: Array, new_appearances: Array, host_clock: float, flights: Array, new_found_parts: Array) -> void:
	print("LAN client: received world with ", crystals.size(), " crystals")
	if multiplayer.is_server(): return
	for item in snapshot:
		add_creation(item[0], item[1])
	for item in crystals:
		add_crystal(item[0], item[1])
	ensure_player_slot(new_scores.size() - 1)
	for i in new_scores.size():
		scores[i] = int(new_scores[i])
		player_health[i] = int(new_health[i])
		found_parts[i] = new_found_parts[i].duplicate()
	update_local_material_visibility()
	update_health_ui()
	for id in new_enemies:
		if not enemy_states.has(id): continue
		enemy_states[id] = new_enemies[id].duplicate()
		enemy_targets[id] = enemy_states[id].position
		update_enemy_visual(id)
	apply_shop_state(new_owned, new_vehicles, new_food_time)
	for i in positions.size():
		if i != local_index(): players[i].position = positions[i]
		players[i].rotation.y = rotations[i]
		set_player_appearance(i, new_appearances[i])
		if i == 0 or i == local_index() or not new_appearances[i].is_empty(): players[i].visible = true
	world_clock = host_clock
	for i in flights.size():
		if not flights[i].is_empty(): start_balloon_visual(i)
		balloon_flights[i] = flights[i].duplicate()
	update_score()


@rpc("any_peer", "reliable")
func send_appearance(data: Dictionary) -> void:
	if not multiplayer.is_server() or slot_for_sender() < 0: return
	var index := slot_for_sender()
	set_player_appearance(index, data)
	apply_appearance.rpc(index, data)


@rpc("authority", "reliable")
func apply_appearance(index: int, data: Dictionary) -> void:
	ensure_player_slot(index)
	set_player_appearance(index, data)
	players[index].visible = true


func set_player_appearance(index: int, data: Dictionary) -> void:
	if data.is_empty(): return
	appearances[index] = data.duplicate()
	var old := players[index].get_node_or_null("CharacterModel")
	if old:
		old.name = "OldCharacterModel"
		old.queue_free()
	var model: Node3D = CharacterFactory.create(data.get("body_shape", "default"), data.get("animal_type", "rabbit"), data.get("body_color", Color.WHITE), data.get("shirt_type", "basic_tshirt"), data.get("pants_type", "jeans"), data.get("shoes_type", "sneakers"))
	model.name = "CharacterModel"
	model.position.y = 0.75 if active_vehicle[index] == "plane" else 0.55 if active_vehicle[index] in ["car", "rowboat", "speedboat"] else 0.05
	players[index].add_child(model)


@rpc("any_peer", "unreliable")
func submit_position(pos: Vector3, rotation_y: float, speed: float) -> void:
	if not multiplayer.is_server() or slot_for_sender() < 0: return
	var index := slot_for_sender()
	if pos.distance_to(players[index].position) > 8.0: return
	if is_lake_water(pos) and not active_vehicle[index] in ["rowboat", "speedboat", "plane"]: return
	players[index].position = pos
	players[index].rotation.y = rotation_y
	remote_walk_speed[index] = speed
	relay_position.rpc(index, pos, rotation_y, speed)


@rpc("authority", "unreliable")
func relay_position(index: int, pos: Vector3, rotation_y: float, speed: float) -> void:
	ensure_player_slot(index)
	if index == local_index(): return
	players[index].position = pos
	players[index].rotation.y = rotation_y
	remote_walk_speed[index] = speed


func local_index() -> int:
	return my_slot


func make_world() -> void:
	add_island_ground("Mainland", Vector2.ZERO, Vector2(MAIN_HALF * 2), Color("65a765"))
	# Four large, visually distinct areas surrounding the grass spawn clearing.
	add_ground_patch(Vector2(-26, -19), Vector2(36, 27), Color("478c57"))
	add_ground_patch(Vector2(26, -19), Vector2(36, 27), Color("85877f"))
	add_ground_patch(Vector2(-26, 19), Vector2(36, 27), Color("90bb62"))
	add_ground_patch(Vector2(26, 19), Vector2(36, 27), Color("dec47c"))
	add_ground_patch(Vector2.ZERO, Vector2(12, 60), Color("b5a77b"))
	add_ground_patch(Vector2.ZERO, Vector2(86, 7), Color("b5a77b"))
	for x in range(-MAIN_HALF.x, MAIN_HALF.x):
		if x % 4 == 0:
			add_scenery(Vector3i(x, 0, -MAIN_HALF.y), Color("49764b"))
			add_scenery(Vector3i(x, 0, MAIN_HALF.y - 1), Color("49764b"))
	for z in range(-MAIN_HALF.y + 2, MAIN_HALF.y - 2):
		if z % 4 == 0:
			add_scenery(Vector3i(-MAIN_HALF.x, 0, z), Color("49764b"))
			add_scenery(Vector3i(MAIN_HALF.x - 1, 0, z), Color("49764b"))
	# Fixed seed keeps the layout identical on the host and joining computer.
	for i in 30:
		add_tree(Vector2(rng.randi_range(-42, -11), rng.randi_range(-30, -8)), "pine")
	for i in 14:
		add_tree(Vector2(rng.randi_range(-41, -10), rng.randi_range(9, 30)), "oak")
	for i in 10:
		add_cactus(Vector2(rng.randi_range(12, 42), rng.randi_range(9, 30)))
	for i in 24:
		var point := Vector2(rng.randi_range(11, 42), rng.randi_range(-30, -8))
		if point.distance_to(Vector2(26, -19)) > 14.0:
			add_rock(point, rng.randf_range(0.7, 1.6))
	for center in [Vector2(13, -13), Vector2(39, -27)]:
		add_hill(center, Color("8b9577"), Color("9da68c"))
	add_hill(Vector2(-26, 22), Color("79a45e"), Color("a8c779"))
	for center in [Vector2(26, 21), Vector2(38, 28)]:
		add_hill(center, Color("cfaa69"), Color("e5c987"))
	for center in [Vector2(-19, -6), Vector2(-34, -16), Vector2(-24, 16)]:
		add_fallen_log(center)
	for i in 35:
		add_flower(Vector2(rng.randi_range(-42, -9), rng.randi_range(8, 30)), palette[i % palette.size()])
	for i in 25:
		add_ground_detail(Vector2(rng.randi_range(10, 42), rng.randi_range(8, 30)), Color("edd496"))
	for i in 18:
		add_ground_detail(Vector2(rng.randi_range(10, 42), rng.randi_range(-30, -8)), Color("656e73"))
	for point in [Vector2(-49, -38), Vector2(-50, 35), Vector2(49, -36), Vector2(49, 35)]:
		if point.distance_to(Vector2(-48, 38)) > 6.0 and point.distance_to(Vector2(48, 38)) > 6.0:
			add_tree(point, "pine" if point.y < 0 else "oak")
	for point in [Vector2(-52, 12), Vector2(52, -13), Vector2(-30, 39), Vector2(31, 40)]:
		add_rock(point, 0.9)
	var landing_clearances := [Vector2(42, -2), Vector2(-42, 2), Vector2(0, -30), Vector2(0, 30), Vector2(-47, -37), Vector2(47, -37), Vector2(-47, 37), Vector2(47, 37)]
	for i in 48:
		var edge := Vector2(rng.randf_range(-52, 52), rng.randf_range(-41, 41))
		if absf(edge.x) < 43.0 and absf(edge.y) < 32.0: continue
		var clear := true
		for landing in landing_clearances:
			if edge.distance_to(landing) < 7.0: clear = false
		if not clear: continue
		if edge.x < 0.0: add_tree(edge, "pine" if edge.y < 0.0 else "oak")
		elif edge.y > 0.0: add_cactus(edge)
		else: add_rock(edge, rng.randf_range(0.6, 1.1))
	add_cemetery()
	make_remote_places()
	add_workshop()
	make_plane_materials()


func add_cemetery() -> void:
	add_ground_patch(Vector2(26, -19), Vector2(22, 20), Color("454a51"))
	for x in [19, 24, 29, 34]:
		for z in [-25, -21, -17, -13]:
			static_box("Gravestone", Vector3(x, 0.52, z), Vector3(0.75, 1.05, 0.32), Color("a2a7a6"))
			mark_obstacle(Vector2(x, z), 0.8)
	for point in [Vector2(21, -15), Vector2(32, -15), Vector2(21, -27), Vector2(32, -27)]:
		add_enemy("skeleton", point, Rect2(16, -29, 21, 19))


func add_cave(center: Vector2) -> void:
	add_ground_patch(center, Vector2(18, 17), Color("292d35"))
	for side in [-1.0, 1.0]:
		var wall_point := center + Vector2(side * 8.3, 0)
		static_box("CaveWall", Vector3(wall_point.x, 1.5, wall_point.y), Vector3(1.8, 3.0, 17), Color("454a50"))
		mark_obstacle(wall_point, 1.3)
	static_box("CaveBack", Vector3(center.x, 1.6, center.y + 8.2), Vector3(17, 3.2, 1.8), Color("3a3e44"))
	static_box("CaveArch", Vector3(center.x, 3.0, center.y - 8.0), Vector3(17, 1.2, 1.4), Color("454a50"))
	for offset in [Vector2(-3, -2), Vector2(3, 1), Vector2(0, 5)]:
		add_enemy("bat", center + offset, Rect2(center - Vector2(7, 7), Vector2(14, 14)))


func add_enemy(kind: String, point: Vector2, arena: Rect2) -> void:
	var id := enemy_states.size()
	var pos := Vector3(point.x, 2.2 if kind == "bat" else 0.0, point.y)
	var maximum := 24 if kind == "bat" else 100 if kind == "polar_bear" else 160 if kind == "sasquatch" else 75 if kind == "shark" else 40
	enemy_states[id] = {"kind": kind, "position": pos, "spawn": pos, "health": maximum, "maximum": maximum, "alive": true, "arena": arena, "attack_timer": 0.0, "impact_timer": 0.0, "respawn_timer": 0.0}
	var enemy: Node3D = EnemyVisuals.create(kind)
	enemy.name = "%s_%d" % [kind, id]
	enemy.position = pos
	add_child(enemy)
	enemy_nodes[id] = enemy
	enemy_targets[id] = pos


func add_island_ground(label: String, center: Vector2, size: Vector2, color: Color) -> void:
	var ground := StaticBody3D.new()
	ground.name = label
	ground.position = Vector3(center.x, -0.25, center.y)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.5, size.y)
	visual.mesh = mesh
	visual.material_override = material(color, 0.92)
	ground.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	collision.shape = shape
	ground.add_child(collision)
	add_child(ground)


func make_remote_places() -> void:
	add_island_ground("MountainIsland", Vector2(115, 0), Vector2(92, 84), Color("777b78"))
	add_island_ground("WildwoodIsland", Vector2(-115, 0), Vector2(92, 84), Color("407c4e"))
	for center in [Vector2(112, -17), Vector2(132, 14), Vector2(139, -19)]:
		static_box("MountainBase", Vector3(center.x, 1.0, center.y), Vector3(18, 2.0, 18), Color("656c6d"))
		static_box("MountainSlope", Vector3(center.x, 3.0, center.y), Vector3(13, 2.0, 13), Color("81898a"))
		static_box("MountainPeak", Vector3(center.x, 5.0, center.y), Vector3(9, 2.0, 9), Color("aeb6b4"))
		static_box("Snowcap", Vector3(center.x, 6.4, center.y), Vector3(5, 0.8, 5), Color("eef4ef"))
		mark_obstacle(center, 10.0)
	for i in 28:
		var rock_point := Vector2(rng.randi_range(94, 146), rng.randi_range(-29, 29))
		if rock_point.distance_to(Vector2(86, -2)) > 8.0 and rock_point.distance_to(Vector2(100, 18)) > 11.0 and rock_point.distance_to(Vector2(130, -3)) > 11.0:
			add_rock(rock_point, rng.randf_range(0.8, 1.8))
	add_cave(Vector2(100, 18))
	add_cave(Vector2(130, -3))
	for i in 52:
		var tree_point := Vector2(rng.randi_range(-147, -91), rng.randi_range(-29, 29))
		if tree_point.distance_to(Vector2(-86, 2)) > 8.0:
			add_tree(tree_point, "pine" if i % 3 else "oak")
	for i in 11:
		add_animal("deer" if i % 3 else "rabbit", Vector2(-144, -94), Vector2(-28, 28))
	for i in 6:
		add_animal("goat", Vector2(95, 145), Vector2(-28, 28))
	for point in [Vector2(155, -33), Vector2(156, 23), Vector2(81, 31)]:
		if point.distance_to(Vector2(155, 36)) > 5.0: add_rock(point, 1.2)
	for point in [Vector2(-154, -31), Vector2(-153, 16), Vector2(-78, -25), Vector2(-80, 34)]:
		if point.distance_to(Vector2(-155, 36)) > 5.0: add_tree(point, "pine")
	for i in 22:
		var remote_edge := Vector2(rng.randf_range(72, 158), rng.randf_range(-39, 39))
		if remote_edge.distance_to(Vector2(86, -2)) > 8.0 and remote_edge.distance_to(Vector2(155, 36)) > 6.0 and (remote_edge.x < 94.0 or remote_edge.x > 146.0 or absf(remote_edge.y) > 29.0):
			add_rock(remote_edge, rng.randf_range(0.5, 1.0))
	for i in 22:
		var forest_edge := Vector2(rng.randf_range(-158, -72), rng.randf_range(-39, 39))
		if forest_edge.distance_to(Vector2(-86, 2)) > 8.0 and forest_edge.distance_to(Vector2(-155, 36)) > 6.0 and (forest_edge.x < -147.0 or forest_edge.x > -91.0 or absf(forest_edge.y) > 29.0):
			add_tree(forest_edge, "pine" if i % 3 else "oak")
	add_balloon_station(Vector3(42, 1, -2), Vector3(86, 1, -2), "Mountains")
	add_balloon_station(Vector3(86, 1, -2), Vector3(42, 1, -2), "Mainland")
	add_balloon_station(Vector3(-42, 1, 2), Vector3(-86, 1, 2), "Wildwood")
	add_balloon_station(Vector3(-86, 1, 2), Vector3(-42, 1, 2), "Mainland")
	make_arctic_place()
	make_lake_place()
	add_balloon_station(Vector3(0, 1, -30), Vector3(0, 1, -80), "Arctic")
	add_balloon_station(Vector3(0, 1, -80), Vector3(0, 1, -30), "Mainland")
	add_balloon_station(Vector3(0, 1, 30), Vector3(0, 1, 80), "Lake")
	add_balloon_station(Vector3(0, 1, 80), Vector3(0, 1, 30), "Mainland")
	make_new_places()
	for route in [
		[Vector3(-47, 1, -37), Vector3(-90, 1, -82), "Crystal Caverns"],
		[Vector3(47, 1, -37), Vector3(90, 1, -82), "Volcano"],
		[Vector3(-47, 1, 37), Vector3(-90, 1, 82), "Golden Dunes"],
		[Vector3(47, 1, 37), Vector3(90, 1, 82), "Jungle Ruins"]
	]:
		add_balloon_station(route[0], route[1], route[2])
		add_balloon_station(route[1], route[0], "Mainland")


func make_arctic_place() -> void:
	add_island_ground("ArcticIsland", Vector2(0, -112), Vector2(128, 90), Color("e2eef0"))
	for center in [Vector2(-32, -127), Vector2(31, -121), Vector2(-25, -92), Vector2(27, -98)]:
		static_box("IceRidge", Vector3(center.x, 1.3, center.y), Vector3(13, 2.6, 9), Color("c6e0e6"))
		mark_obstacle(center, 7.0)
	for i in 17:
		var point := Vector2(rng.randf_range(-46, 46), rng.randf_range(-141, -85))
		if point.distance_to(Vector2(0, -80)) > 8.0: add_rock(point, rng.randf_range(0.5, 1.2))
	for point in [Vector2(-15, -111), Vector2(17, -116), Vector2(-13, -132), Vector2(19, -92)]:
		add_enemy("polar_bear", point, Rect2(-48, -143, 96, 61))
	for point in [Vector2(0, -128), Vector2(30, -135)]:
		add_enemy("sasquatch", point, Rect2(-48, -143, 96, 61))
	for point in [Vector2(54, -126), Vector2(-52, -105), Vector2(22, -151)]:
		if point.distance_to(Vector2(-55, -149)) > 6.0: add_rock(point, 1.1)


func make_lake_place() -> void:
	add_island_ground("LakeIsland", Vector2(0, 112), Vector2(126, 94), Color("70a864"))
	add_ground_patch(Vector2(0, 112), Vector2(84, 58), Color("2983a9"))
	var water := StaticBody3D.new()
	water.name = "LakeWater"
	water.position = Vector3(0, 0.04, 112)
	var surface := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(84, 0.08, 58)
	surface.mesh = plane
	surface.material_override = material(Color("38a6c9"), 0.2)
	water.add_child(surface)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = plane.size
	shape.shape = box_shape
	water.add_child(shape)
	add_child(water)
	for point in [Vector2(-42, 95), Vector2(43, 102), Vector2(-44, 132), Vector2(42, 130)]:
		add_tree(point, "oak")
	for point in [Vector2(-16, 105), Vector2(17, 113), Vector2(0, 127)]:
		add_enemy("shark", point, LAKE_WATER)
	for kind_and_point in [["whale", Vector2(-17, 119)], ["whale", Vector2(19, 99)], ["fish", Vector2(-27, 99)], ["fish", Vector2(25, 124)], ["fish", Vector2(5, 107)]]:
		add_animal_at(kind_and_point[0], kind_and_point[1])
	for point in [Vector2(-55, 143), Vector2(52, 76), Vector2(-52, 77)]:
		if point.distance_to(Vector2(55, 150)) > 6.0: add_tree(point, "oak")


func make_new_places() -> void:
	var caverns := Vector2(-125, -115)
	var volcano := Vector2(125, -115)
	var dunes := Vector2(-125, 115)
	var jungle := Vector2(125, 115)
	add_island_ground("CrystalCavernsIsland", caverns, Vector2(84, 80), Color("45445e"))
	add_island_ground("VolcanoIsland", volcano, Vector2(84, 80), Color("714a40"))
	add_island_ground("GoldenDunesIsland", dunes, Vector2(84, 80), Color("d8b970"))
	add_island_ground("JungleRuinsIsland", jungle, Vector2(84, 80), Color("397b50"))
	add_ground_patch(caverns + Vector2(-12, -12), Vector2(30, 27), Color("5d527c"))
	add_ground_patch(volcano + Vector2(12, -11), Vector2(29, 25), Color("9a4b3d"))
	add_ground_patch(dunes + Vector2(-9, 9), Vector2(34, 30), Color("e8cf86"))
	add_ground_patch(jungle + Vector2(10, 8), Vector2(30, 28), Color("2e6849"))
	for center in [caverns + Vector2(-14, 7), caverns + Vector2(17, -12), caverns + Vector2(10, 19)]:
		static_box("CrystalSpire", Vector3(center.x, 2.4, center.y), Vector3(2.2, 4.8, 2.2), Color("9c80c3"))
		mark_obstacle(center, 2.0)
	for center in [volcano + Vector2(-17, -18), volcano + Vector2(15, 10), volcano + Vector2(22, -21)]:
		add_hill(center, Color("75463c"), Color("bd5b3d"))
	for center in [dunes + Vector2(-20, -15), dunes + Vector2(17, 14)]:
		add_hill(center, Color("c7a35f"), Color("e9d18b"))
	for center in [jungle + Vector2(-16, -12), jungle + Vector2(15, 19)]:
		static_box("RuinsPillar", Vector3(center.x, 1.5, center.y), Vector3(2.5, 3.0, 2.5), Color("9a9f78"))
		mark_obstacle(center, 2.2)
	for i in 24:
		var jungle_point := jungle + Vector2(rng.randf_range(-35, 35), rng.randf_range(-32, 32))
		if jungle_point.distance_to(Vector2(90, 82)) > 9.0 and jungle_point.distance_to(Vector2(157, 148)) > 7.0:
			add_tree(jungle_point, "oak")
	for i in 13:
		var dune_point := dunes + Vector2(rng.randf_range(-34, 34), rng.randf_range(-31, 31))
		if dune_point.distance_to(Vector2(-90, 82)) > 8.0 and dune_point.distance_to(Vector2(-157, 148)) > 7.0:
			add_cactus(dune_point)
	for i in 12:
		var lava_rock := volcano + Vector2(rng.randf_range(-34, 34), rng.randf_range(-31, 31))
		if lava_rock.distance_to(Vector2(90, -82)) > 8.0 and lava_rock.distance_to(Vector2(157, -148)) > 7.0:
			add_rock(lava_rock, rng.randf_range(0.7, 1.5))
	for point in [caverns + Vector2(-3, -7), caverns + Vector2(13, 8)]:
		add_enemy("bat", point, Rect2(caverns - Vector2(35, 33), Vector2(70, 66)))
	for point in [jungle + Vector2(-7, 12), jungle + Vector2(17, -5)]:
		add_enemy("skeleton", point, Rect2(jungle - Vector2(35, 33), Vector2(70, 66)))
	for i in 3:
		add_animal("deer" if i % 2 else "rabbit", Vector2(101, 146), Vector2(91, 145))


func add_workshop() -> void:
	add_ground_patch(Vector2.ZERO, Vector2(7, 7), Color("8d8066"))
	static_box("PlaneWorkbench", Vector3(0, 0.55, 0), Vector3(2.2, 1.1, 1.3), Color("755c43"))
	var sign := MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(2.5, 0.8, 0.12)
	sign.mesh = sign_mesh
	sign.position = Vector3(0, 2.1, 0)
	sign.material_override = material(Color("e8c581"), 0.8)
	add_child(sign)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.5, 0)
	light.light_color = Color("ffe3a7")
	light.light_energy = 0.45
	light.omni_range = 5.0
	add_child(light)


func make_plane_materials() -> void:
	for id in PLANE_PARTS:
		var definition: Dictionary = PLANE_PARTS[id]
		var root := Node3D.new()
		root.name = "PlanePart_%s" % id
		root.position = definition.position
		var item := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.28
		mesh.height = 0.56
		item.mesh = mesh
		var glow := material(definition.color, 0.2)
		glow.emission_enabled = true
		glow.emission = definition.color
		glow.emission_energy_multiplier = 0.85
		item.material_override = glow
		root.add_child(item)
		var base := MeshInstance3D.new()
		var base_mesh := CylinderMesh.new()
		base_mesh.top_radius = 0.36
		base_mesh.bottom_radius = 0.41
		base_mesh.height = 0.12
		base.mesh = base_mesh
		base.position.y = -0.38
		base.material_override = material(Color("313a4a"), 0.8)
		root.add_child(base)
		var light := OmniLight3D.new()
		light.light_color = definition.color
		light.light_energy = 0.2
		light.omni_range = 2.6
		root.add_child(light)
		add_child(root)
		material_nodes[id] = root


func update_material_visuals(delta: float) -> void:
	for id in material_nodes:
		var node: Node3D = material_nodes[id]
		node.rotation.y += delta * 0.7
		node.position.y = float(PLANE_PARTS[id].position.y) + sin(world_clock * 2.2 + float(PLANE_PARTS.keys().find(id))) * 0.09


func add_animal_at(kind: String, point: Vector2) -> void:
	var creature: Node3D = AnimalVisuals.create(kind)
	creature.position = Vector3(point.x, 0.25, point.y)
	add_child(creature)
	animals.append(creature)
	animal_origins.append(creature.position)
	animal_kinds.append(kind)


func add_animal(kind: String, x_range: Vector2, z_range: Vector2) -> void:
	var point := Vector2.ZERO
	for attempt in 50:
		point = Vector2(rng.randf_range(x_range.x, x_range.y), rng.randf_range(z_range.x, z_range.y))
		if crystal_spot_clear(point): break
	var creature: Node3D = AnimalVisuals.create(kind)
	creature.position = Vector3(point.x, 0, point.y)
	add_child(creature)
	animals.append(creature)
	animal_origins.append(creature.position)
	animal_kinds.append(kind)


func add_balloon_station(from: Vector3, to: Vector3, destination: String) -> void:
	balloon_stations.append({"from": from, "to": to, "destination": destination})
	mark_obstacle(Vector2(from.x, from.z), 3.0)
	var platform := MeshInstance3D.new()
	platform.name = "BalloonLanding"
	var disk := CylinderMesh.new()
	disk.top_radius = 2.7
	disk.bottom_radius = 2.7
	disk.height = 0.08
	platform.mesh = disk
	platform.position = Vector3(from.x, 0.05, from.z)
	platform.material_override = material(Color("e1c78f"), 0.9)
	add_child(platform)
	var balloon: Node3D = BalloonVisuals.create()
	balloon.name = "StationBalloon"
	balloon.position = Vector3(from.x, 0, from.z)
	add_child(balloon)


func add_ground_patch(center: Vector2, size: Vector2, color: Color) -> void:
	var patch := MeshInstance3D.new()
	patch.name = "TerrainPatch"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.025, size.y)
	patch.mesh = mesh
	patch.position = Vector3(center.x, 0.013, center.y)
	patch.material_override = material(color, 0.95)
	add_child(patch)


func add_tree(point: Vector2, kind: String) -> void:
	var height := rng.randf_range(2.4, 3.8)
	var tree := static_box("Tree", Vector3(point.x, height * 0.5, point.y), Vector3(0.65, height, 0.65), Color("805536"))
	var crown := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.8, 2.2, 2.8) if kind == "pine" else Vector3(3.2, 2.3, 3.2)
	crown.mesh = mesh
	crown.position.y = height * 0.5 + 0.55
	crown.material_override = material(Color("286f4b") if kind == "pine" else Color("4da65b"), 0.9)
	tree.add_child(crown)
	if kind == "pine":
		var top := MeshInstance3D.new()
		var top_mesh := BoxMesh.new()
		top_mesh.size = Vector3(1.9, 1.5, 1.9)
		top.mesh = top_mesh
		top.position.y = height * 0.5 + 2.0
		top.material_override = crown.material_override
		tree.add_child(top)
	mark_obstacle(point, 1.7)


func add_cactus(point: Vector2) -> void:
	var cactus := static_box("Cactus", Vector3(point.x, 1.15, point.y), Vector3(0.75, 2.3, 0.75), Color("3c9a62"))
	var arm := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.65, 0.4, 0.4)
	arm.mesh = mesh
	arm.position = Vector3(0.52, 0.15, 0)
	arm.material_override = material(Color("3c9a62"), 0.95)
	cactus.add_child(arm)
	mark_obstacle(point, 1.2)


func add_rock(point: Vector2, radius: float) -> void:
	var rock := StaticBody3D.new()
	rock.name = "Boulder"
	rock.position = Vector3(point.x, radius * 0.48, point.y)
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.35
	visual.mesh = mesh
	visual.material_override = material(Color("787f86"), 0.95)
	rock.add_child(visual)
	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius * 0.8
	collider.shape = shape
	rock.add_child(collider)
	rock.add_to_group("world_obstacles")
	add_child(rock)
	mark_obstacle(point, radius + 0.5)


func add_hill(center: Vector2, base_color: Color, top_color: Color) -> void:
	static_box("LowHill", Vector3(center.x, 0.35, center.y), Vector3(8, 0.7, 7), base_color)
	static_box("Hilltop", Vector3(center.x, 1.0, center.y), Vector3(4.5, 0.6, 4), top_color)
	mark_obstacle(center, 5.0)


func add_fallen_log(center: Vector2) -> void:
	var log := static_box("FallenLog", Vector3(center.x, 0.35, center.y), Vector3(4.0, 0.7, 0.75), Color("895938"))
	log.rotation.y = rng.randf_range(-0.6, 0.6)
	mark_obstacle(center, 2.5)


func static_box(label: String, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material(color, 0.9)
	body.add_child(visual)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	body.add_to_group("world_obstacles")
	add_child(body)
	return body


func mark_obstacle(point: Vector2, radius: float) -> void:
	obstacle_zones.append(Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))


func add_flower(point: Vector2, color: Color) -> void:
	var flower := MeshInstance3D.new()
	flower.name = "MeadowFlower"
	var mesh := SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.25
	flower.mesh = mesh
	flower.position = Vector3(point.x, 0.13, point.y)
	flower.material_override = material(color, 0.8)
	add_child(flower)


func add_ground_detail(point: Vector2, color: Color) -> void:
	var detail := MeshInstance3D.new()
	detail.name = "GroundDetail"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(rng.randf_range(0.8, 2.1), 0.02, rng.randf_range(0.8, 2.1))
	detail.mesh = mesh
	detail.position = Vector3(point.x, 0.042, point.y)
	detail.material_override = material(color, 0.95)
	add_child(detail)


func make_players() -> void:
	var chosen := GameManager.character_data
	players.append(make_player("Player 1", Vector3(-2, 1, 2), chosen.get("body_color", Color("78c6ff")), chosen.get("animal_type", "rabbit")))
	players.append(make_player("Player 2", Vector3(2, 1, 2), Color("ff9b9b"), "fox"))
	players[1].visible = false


func make_player(label: String, spawn: Vector3, color: Color, animal: String) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = label
	body.position = spawn
	body.collision_layer = 2
	body.collision_mask = 1
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.7
	collision.shape = capsule
	collision.position.y = 0.85
	body.add_child(collision)
	var model: Node3D = CharacterFactory.create("default", animal, color, "basic_tshirt", "jeans", "sneakers")
	model.name = "CharacterModel"
	model.position.y = 0.05
	body.add_child(model)
	add_child(body)
	return body


func make_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 56.0
	add_child(camera)
	update_camera(1.0)


func make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.025, 0.04, 0.075, 0.96)
	panel.position = Vector2(18, 18)
	panel.size = Vector2(690, 112)
	layer.add_child(panel)
	var title := Label.new()
	title.position = Vector2(20, 10)
	title.add_theme_font_size_override("font_size", 25)
	title.text = "LAN CREATIVE WORLD"
	panel.add_child(title)
	style_hud_label(title, Color("ffffff"))
	var controls := Label.new()
	controls.position = Vector2(20, 47)
	controls.text = "WASD / arrows move  |  Space jump  |  Q place  |  E remove  |  R attack\nB shop  |  M map  |  P blueprint  |  F balloon / workshop"
	controls.add_theme_color_override("font_color", Color("d8e8ff"))
	panel.add_child(controls)
	style_hud_label(controls, Color("e9f3ff"))
	health_panel = ColorRect.new()
	health_panel.color = Color(0.025, 0.04, 0.075, 0.96)
	health_panel.position = Vector2(18, 140)
	health_panel.size = Vector2(265, 72)
	layer.add_child(health_panel)
	health_scroll = ScrollContainer.new()
	health_scroll.position = Vector2.ZERO
	health_scroll.size = health_panel.size
	health_panel.add_child(health_scroll)
	health_list = Control.new()
	health_list.custom_minimum_size = Vector2(255, 72)
	health_scroll.add_child(health_list)
	for i in players.size(): add_health_bar(i)
	score_panel = ColorRect.new()
	score_panel.color = Color(0.025, 0.04, 0.075, 0.96)
	score_panel.position = Vector2(718, 18)
	score_panel.size = Vector2(310, 68)
	layer.add_child(score_panel)
	score_label = Label.new()
	score_label.position = Vector2(10, 6)
	score_label.add_theme_font_size_override("font_size", 20)
	style_hud_label(score_label, Color("fff4ce"))
	score_panel.add_child(score_label)
	location_panel = ColorRect.new()
	location_panel.color = Color(0.025, 0.04, 0.075, 0.96)
	location_panel.position = Vector2(718, 94)
	location_panel.size = Vector2(310, 34)
	layer.add_child(location_panel)
	location_label = Label.new()
	location_label.position = Vector2(10, 5)
	location_label.add_theme_font_size_override("font_size", 17)
	style_hud_label(location_label, Color("e8f4ce"))
	location_panel.add_child(location_label)
	message_label = Label.new()
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.position = Vector2(-350, 145)
	message_label.size = Vector2(700, 45)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 20)
	message_label.add_theme_color_override("font_color", Color("fff0a6"))
	style_hud_label(message_label, Color("fff0a6"))
	layer.add_child(message_label)
	var travel_label := Label.new()
	travel_label.name = "TravelHint"
	travel_label.anchor_left = 0.5
	travel_label.anchor_right = 0.5
	travel_label.anchor_top = 1.0
	travel_label.anchor_bottom = 1.0
	travel_label.offset_left = -330
	travel_label.offset_right = 330
	travel_label.offset_top = -85
	travel_label.offset_bottom = -45
	travel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	travel_label.add_theme_font_size_override("font_size", 20)
	travel_label.add_theme_color_override("font_color", Color("fff0b8"))
	style_hud_label(travel_label, Color("fff0b8"))
	layer.add_child(travel_label)
	make_minimap(layer)
	make_shop(layer)
	make_blueprint(layer)
	update_score()
	update_health_ui()


func style_hud_label(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("07121f"))
	label.add_theme_constant_override("outline_size", 3)


func add_health_bar(index: int) -> void:
	if not health_panel or health_bars.size() > index: return
	health_panel.size.y = minf(288.0, 10.0 + float(index + 1) * 31.0)
	health_scroll.size = health_panel.size
	health_list.custom_minimum_size.y = 10.0 + float(index + 1) * 31.0
	var label := Label.new()
	label.text = "P%d HP" % (index + 1)
	label.position = Vector2(10, 9 + index * 31)
	style_hud_label(label, Color("f6f9ff"))
	health_list.add_child(label)
	var bar := ProgressBar.new()
	bar.position = Vector2(67, 10 + index * 31)
	bar.size = Vector2(175, 18)
	bar.max_value = MAX_HEALTH
	bar.value = MAX_HEALTH
	bar.show_percentage = true
	bar.add_theme_color_override("font_color", Color("ffffff"))
	bar.add_theme_color_override("font_outline_color", Color("08111c"))
	bar.add_theme_constant_override("outline_size", 3)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("192a3e")
	bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = palette[index % palette.size()]
	bar.add_theme_stylebox_override("fill", fill)
	health_list.add_child(bar)
	health_bars.append(bar)


func make_minimap(layer: CanvasLayer) -> void:
	minimap_panel = PanelContainer.new()
	minimap_panel.name = "MinimapPanel"
	minimap_panel.anchor_left = 1.0
	minimap_panel.anchor_right = 1.0
	minimap_panel.offset_left = -250
	minimap_panel.offset_right = -16
	minimap_panel.offset_top = 16
	minimap_panel.offset_bottom = 296
	minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.04, 0.075, 0.92)
	background.set_corner_radius_all(8)
	background.content_margin_left = 5
	background.content_margin_right = 5
	background.content_margin_top = 4
	background.content_margin_bottom = 4
	minimap_panel.add_theme_stylebox_override("panel", background)
	layer.add_child(minimap_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_panel.add_child(column)
	var heading := Label.new()
	heading.text = "WORLD MAP    N ↑    [M]"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)
	minimap_view = MinimapView.new()
	minimap_view.game = self
	minimap_view.half_world = Vector2(WORLD_HALF)
	minimap_view.custom_minimum_size = Vector2(216, 216)
	minimap_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(minimap_view)
	var legend := Label.new()
	legend.text = "White you | Orange pal | Cyan gem\nPurple balloon | Tan wildlife | Red enemy"
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 12)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(legend)


func make_shop(layer: CanvasLayer) -> void:
	shop_panel = PanelContainer.new()
	shop_panel.anchor_left = 0.5
	shop_panel.anchor_right = 0.5
	shop_panel.anchor_top = 0.5
	shop_panel.anchor_bottom = 0.5
	shop_panel.offset_left = -245
	shop_panel.offset_right = 245
	shop_panel.offset_top = -280
	shop_panel.offset_bottom = 280
	shop_panel.visible = false
	layer.add_child(shop_panel)
	var content := VBoxContainer.new()
	shop_panel.add_child(content)
	var heading := Label.new()
	heading.text = "CRYSTAL SHOP"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 25)
	content.add_child(heading)
	shop_status = Label.new()
	shop_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(shop_status)
	for id in SHOP_ITEMS:
		var button := Button.new()
		button.custom_minimum_size.y = 43
		button.pressed.connect(on_shop_item_pressed.bind(id))
		content.add_child(button)
		shop_buttons[id] = button
	var close_button := Button.new()
	close_button.text = "Close (B)"
	close_button.pressed.connect(func(): shop_panel.visible = false)
	content.add_child(close_button)
	refresh_shop()


func make_blueprint(layer: CanvasLayer) -> void:
	blueprint_panel = PanelContainer.new()
	blueprint_panel.anchor_left = 0.5
	blueprint_panel.anchor_right = 0.5
	blueprint_panel.anchor_top = 0.5
	blueprint_panel.anchor_bottom = 0.5
	blueprint_panel.offset_left = -315
	blueprint_panel.offset_right = 315
	blueprint_panel.offset_top = -270
	blueprint_panel.offset_bottom = 270
	blueprint_panel.visible = false
	layer.add_child(blueprint_panel)
	var column := VBoxContainer.new()
	blueprint_panel.add_child(column)
	blueprint_text = Label.new()
	blueprint_text.add_theme_font_size_override("font_size", 18)
	column.add_child(blueprint_text)
	var close_button := Button.new()
	close_button.text = "Close [P]"
	close_button.pressed.connect(func(): blueprint_panel.visible = false)
	column.add_child(close_button)
	refresh_blueprint()


func refresh_blueprint() -> void:
	if not blueprint_text or found_parts.size() <= local_index(): return
	var index := local_index()
	var lines := ["PLANE ASSEMBLY BLUEPRINT", "", "Collect one glowing component in each destination:"]
	for id in PLANE_PARTS:
		var part: Dictionary = PLANE_PARTS[id]
		lines.append("%s  %s — %s" % ["[FOUND]" if found_parts[index].has(id) else "[     ]", part.label, part.world])
	lines.append("")
	lines.append("1. Collect all eight components (%d/8 found)." % found_parts[index].size())
	lines.append("2. Return to the workbench at the mainland crossroads.")
	lines.append("3. Press F there to assemble and equip your plane.")
	lines.append("4. Fly with WASD/arrows, Space to climb, Shift to descend.")
	lines.append("5. Land at the workbench and press F to park or re-equip.")
	blueprint_text.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_B:
			shop_panel.visible = not shop_panel.visible
			if shop_panel.visible: blueprint_panel.visible = false
			refresh_shop()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_P:
			if owned_items[local_index()].has("blueprint"):
				blueprint_panel.visible = not blueprint_panel.visible
				if blueprint_panel.visible: shop_panel.visible = false
				refresh_blueprint()
			else:
				show_message("Buy the plane blueprint in the crystal shop first.", 3.0)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_M:
			toggle_minimap()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F:
			if nearby_workshop(local_index()): try_use_workshop()
			else: try_board_balloon()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_R:
			try_attack()
			get_viewport().set_input_as_handled()


func toggle_minimap() -> void:
	minimap_panel.visible = not minimap_panel.visible
	if minimap_panel.visible: minimap_view.queue_redraw()


func nearby_balloon_station(index: int) -> int:
	for station_index in balloon_stations.size():
		if players[index].position.distance_to(balloon_stations[station_index].from) <= 5.0:
			return station_index
	return -1


func nearby_workshop(index: int) -> bool:
	var pos := players[index].position
	return Vector2(pos.x, pos.z).distance_to(Vector2.ZERO) <= 5.0 and pos.y <= 4.0


func try_use_workshop() -> void:
	var index := local_index()
	if not connected or shop_panel.visible or blueprint_panel.visible or not balloon_flights[index].is_empty(): return
	if multiplayer.is_server(): process_workshop(index)
	else: request_workshop.rpc_id(1, players[index].position)


@rpc("any_peer", "reliable")
func request_workshop(reported_pos: Vector3) -> void:
	if not multiplayer.is_server() or slot_for_sender() < 0: return
	var index := slot_for_sender()
	if Vector2(reported_pos.x, reported_pos.z).length() > 5.0 or reported_pos.y > 4.0: return
	if reported_pos.distance_to(players[index].position) > 8.0: return
	players[index].position = reported_pos
	process_workshop(index)


func process_workshop(index: int) -> void:
	if not nearby_workshop(index) or not balloon_flights[index].is_empty(): return
	if not owned_items[index].has("blueprint"):
		shop_notice(index, "Buy the plane blueprint in the crystal shop first.")
		return
	if found_parts[index].size() < PLANE_PARTS.size():
		shop_notice(index, "Plane parts found: %d/%d. The blueprint lists the worlds." % [found_parts[index].size(), PLANE_PARTS.size()])
		return
	if not owned_items[index].has("plane"):
		owned_items[index]["plane"] = true
		active_vehicle[index] = "plane"
		shop_notice(index, "Plane assembled! Space climbs; Shift descends.")
	elif active_vehicle[index] == "plane":
		active_vehicle[index] = ""
		shop_notice(index, "Plane parked at the workshop.")
	else:
		active_vehicle[index] = "plane"
		shop_notice(index, "Plane equipped. Ready for takeoff!")
	players[index].position.y = 1.0 if active_vehicle[index].is_empty() else 2.8
	players[index].velocity = Vector3.ZERO
	apply_equipment(index)
	update_score()
	sync_shop_state.rpc(scores, owned_items, active_vehicle, food_time)
	respawn_player_remote.rpc(index, players[index].position)


func try_board_balloon() -> void:
	var index := local_index()
	if shop_panel.visible or not balloon_flights[index].is_empty() or not connected: return
	var station_index := nearby_balloon_station(index)
	if station_index < 0:
		show_message("Find a balloon landing at the edge of an island.", 3.0)
		return
	if multiplayer.is_server():
		begin_balloon_flight(index, station_index)
	else:
		request_balloon.rpc_id(1, station_index, players[index].position)


@rpc("any_peer", "reliable")
func request_balloon(station_index: int, reported_pos: Vector3) -> void:
	if not multiplayer.is_server() or slot_for_sender() < 0: return
	var index := slot_for_sender()
	if station_index < 0 or station_index >= balloon_stations.size(): return
	if reported_pos.distance_to(balloon_stations[station_index].from) > 5.0: return
	if reported_pos.distance_to(players[index].position) > 8.0: return
	players[index].position = reported_pos
	begin_balloon_flight(index, station_index)


func begin_balloon_flight(index: int, station_index: int) -> void:
	if station_index < 0 or station_index >= balloon_stations.size(): return
	if not balloon_flights[index].is_empty() or nearby_balloon_station(index) != station_index: return
	var from := players[index].position
	var destination: Vector3 = balloon_stations[station_index].to
	balloon_flights[index] = {"start": from, "end": destination, "elapsed": 0.0, "duration": BALLOON_TRAVEL_TIME}
	start_balloon_visual(index)
	start_balloon_remote.rpc(index, from, destination)
	if index == 0: show_message("Balloon departing for %s..." % balloon_stations[station_index].destination, 4.0)
	else: shop_notice(index, "Balloon departing for %s..." % balloon_stations[station_index].destination)


@rpc("authority", "reliable")
func start_balloon_remote(index: int, from: Vector3, destination: Vector3) -> void:
	balloon_flights[index] = {"start": from, "end": destination, "elapsed": 0.0, "duration": BALLOON_TRAVEL_TIME}
	start_balloon_visual(index)
	if index == local_index(): show_message("Balloon departing. Enjoy the view!", 4.0)


func start_balloon_visual(index: int) -> void:
	var body := players[index]
	if body.get_node_or_null("HotAirBalloon"): return
	body.collision_mask = 0
	var vehicle := body.get_node_or_null("Vehicle")
	if vehicle: vehicle.visible = false
	body.add_child(BalloonVisuals.create())


func update_balloon_flights(delta: float) -> void:
	for i in players.size():
		if balloon_flights[i].is_empty(): continue
		var flight: Dictionary = balloon_flights[i]
		flight.elapsed += delta
		var progress := clampf(float(flight.elapsed) / float(flight.duration), 0.0, 1.0)
		if i == local_index():
			players[i].velocity = Vector3.ZERO
			players[i].position = (flight.start as Vector3).lerp(flight.end, progress) + Vector3.UP * sin(progress * PI) * 11.0
		if progress >= 1.0:
			players[i].position = flight.end
			finish_balloon_flight(i)


func finish_balloon_flight(index: int) -> void:
	balloon_flights[index] = {}
	players[index].collision_mask = 1
	var visual := players[index].get_node_or_null("HotAirBalloon")
	if visual: visual.queue_free()
	var vehicle := players[index].get_node_or_null("Vehicle")
	if vehicle: vehicle.visible = true
	if index == local_index():
		last_safe_position[index] = players[index].position
		show_message("You have arrived! Explore and find animals.", 4.0)


func update_travel_hint() -> void:
	var hint := get_node_or_null("CanvasLayer/TravelHint") as Label
	if not hint: return
	var index := local_index()
	if not balloon_flights[index].is_empty():
		hint.text = "Floating to the next place..."
		return
	if nearby_workshop(index):
		hint.text = "Press F: plane workshop (%d/%d parts)  |  P: blueprint" % [found_parts[index].size(), PLANE_PARTS.size()]
		return
	var station_index := nearby_balloon_station(index)
	hint.text = "Press F: balloon to %s" % balloon_stations[station_index].destination if station_index >= 0 else "Plane: Space climb / Shift descend" if active_vehicle[index] == "plane" else ""


func refresh_shop() -> void:
	if not shop_status: return
	var index := local_index()
	shop_status.text = "Your crystals: %d   |   Plane parts: %d/%d" % [scores[index], found_parts[index].size(), PLANE_PARTS.size()]
	for id in SHOP_ITEMS:
		var definition: Dictionary = SHOP_ITEMS[id]
		var suffix := " - %d crystals" % definition.cost
		if owned_items[index].has(id):
			if id in ["car", "motorbike", "bicycle", "rowboat", "speedboat"]:
				suffix = " - Riding (click to park)" if active_vehicle[index] == id else " - Owned (click to ride)"
			else:
				suffix = " - Owned"
		shop_buttons[id].text = definition.label + suffix
		shop_buttons[id].disabled = owned_items[index].has(id) and id in ["lantern", "boots", "blueprint", "sword"]


func on_shop_item_pressed(id: String) -> void:
	if multiplayer.is_server():
		process_shop_action(0, id)
	elif connected:
		request_shop_action.rpc_id(1, id)


@rpc("any_peer", "reliable")
func request_shop_action(id: String) -> void:
	if not multiplayer.is_server() or slot_for_sender() < 0: return
	process_shop_action(slot_for_sender(), id)


func process_shop_action(index: int, id: String) -> void:
	if not SHOP_ITEMS.has(id): return
	if is_lake_water(players[index].position) and id in ["car", "motorbike", "bicycle", "rowboat", "speedboat"]:
		shop_notice(index, "Stay in your boat until you reach shore.")
		return
	var notice := "Purchased %s!" % SHOP_ITEMS[id].label
	if owned_items[index].has(id) and id in ["car", "motorbike", "bicycle", "rowboat", "speedboat"]:
		active_vehicle[index] = "" if active_vehicle[index] == id else id
		notice = "Parked your vehicle." if active_vehicle[index].is_empty() else "Now riding your %s." % id
	else:
		if owned_items[index].has(id) and id != "food": return
		var cost: int = SHOP_ITEMS[id].cost
		if scores[index] < cost:
			shop_notice(index, "Need %d more crystals for %s." % [cost - scores[index], SHOP_ITEMS[id].label])
			return
		scores[index] -= cost
		if id == "food":
			food_time[index] += 20.0
			player_health[index] = mini(MAX_HEALTH, player_health[index] + 30)
			update_health_ui()
			sync_health.rpc(player_health)
		else:
			owned_items[index][id] = true
			if id in ["car", "motorbike", "bicycle", "rowboat", "speedboat"]:
				active_vehicle[index] = id
	apply_equipment(index)
	update_score()
	sync_shop_state.rpc(scores, owned_items, active_vehicle, food_time)
	if id == "blueprint": notice = "Blueprint purchased! Press P to read the plane instructions."
	shop_notice(index, notice)


func shop_notice(index: int, notice: String) -> void:
	if index == 0:
		show_message(notice, 3.0)
	else:
		for peer_id in peer_slots:
			if peer_slots[peer_id] == index:
				receive_shop_notice.rpc_id(peer_id, notice)
				break


@rpc("authority", "reliable")
func receive_shop_notice(notice: String) -> void:
	show_message(notice, 3.0)


@rpc("authority", "reliable")
func sync_shop_state(new_scores: Array, new_owned: Array, new_vehicles: Array, new_food_time: Array) -> void:
	ensure_player_slot(new_scores.size() - 1)
	for i in new_scores.size():
		scores[i] = int(new_scores[i])
	apply_shop_state(new_owned, new_vehicles, new_food_time)
	update_score()


func apply_shop_state(new_owned: Array, new_vehicles: Array, new_food_time: Array) -> void:
	ensure_player_slot(new_owned.size() - 1)
	for i in new_owned.size():
		owned_items[i] = new_owned[i].duplicate()
		active_vehicle[i] = str(new_vehicles[i])
		food_time[i] = float(new_food_time[i])
		apply_equipment(i)
	refresh_shop()


func apply_equipment(index: int) -> void:
	var body := players[index]
	var old_vehicle := body.get_node_or_null("Vehicle")
	if old_vehicle:
		old_vehicle.name = "OldVehicle"
		old_vehicle.queue_free()
	if not active_vehicle[index].is_empty():
		var ride: Node3D = VehicleVisuals.create(active_vehicle[index])
		ride.visible = balloon_flights[index].is_empty()
		body.add_child(ride)
	var light := body.get_node_or_null("Lantern")
	if owned_items[index].has("lantern") and not light:
		var lantern := OmniLight3D.new()
		lantern.name = "Lantern"
		lantern.position = Vector3(0, 2.2, 0.5)
		lantern.light_color = Color("ffe5a2")
		lantern.light_energy = 1.4
		lantern.omni_range = 6.0
		body.add_child(lantern)
	if owned_items[index].has("sword") and not body.get_node_or_null("Sword"):
		var sword := Node3D.new()
		sword.name = "Sword"
		sword.position = Vector3(-0.78, 1.15, 0.18)
		sword.rotation.z = -0.4
		var blade := MeshInstance3D.new()
		var blade_mesh := BoxMesh.new()
		blade_mesh.size = Vector3(0.12, 1.0, 0.12)
		blade.mesh = blade_mesh
		blade.position.y = 0.45
		blade.material_override = material(Color("c5d8de"), 0.25)
		sword.add_child(blade)
		var handle := MeshInstance3D.new()
		var handle_mesh := BoxMesh.new()
		handle_mesh.size = Vector3(0.42, 0.1, 0.16)
		handle.mesh = handle_mesh
		handle.material_override = material(Color("684e36"), 0.8)
		sword.add_child(handle)
		body.add_child(sword)
	var model := body.get_node_or_null("CharacterModel")
	if model:
		model.position.y = 0.75 if active_vehicle[index] == "plane" else 0.55 if active_vehicle[index] in ["car", "rowboat", "speedboat"] else 0.05


func _physics_process(delta: float) -> void:
	world_clock += delta
	update_animals()
	for i in players.size():
		attack_cooldown[i] = maxf(0.0, attack_cooldown[i] - delta)
	for i in players.size():
		food_time[i] = maxf(0.0, food_time[i] - delta)
	if connected and balloon_flights[local_index()].is_empty(): move_player(local_index(), delta)
	update_balloon_flights(delta)
	if GameManager.network_mode == "host": update_enemies(delta)
	else: interpolate_enemies(delta)
	update_walk_animation(delta)
	cooldowns[local_index()] = maxf(0.0, cooldowns[local_index()] - delta)
	handle_building()
	position_timer += delta
	if position_timer >= 0.05 and connected:
		position_timer = 0.0
		var i := local_index()
		var speed := Vector2(players[i].velocity.x, players[i].velocity.z).length()
		if multiplayer.is_server(): relay_position.rpc(i, players[i].position, players[i].rotation.y, speed)
		else: submit_position.rpc_id(1, players[i].position, players[i].rotation.y, speed)
	pickup_timer += delta
	if connected and pickup_timer >= 0.15:
		pickup_timer = 0.0
		check_local_crystal_pickups()
		check_local_plane_materials()
	update_material_visuals(delta)
	update_camera(delta)
	update_location_label()
	update_travel_hint()
	minimap_timer += delta
	if minimap_timer >= 0.15:
		minimap_timer = 0.0
		if minimap_panel.visible: minimap_view.queue_redraw()
	if message_time > 0.0:
		message_time -= delta
		if message_time <= 0.0:
			message_label.text = ""


func move_player(index: int, delta: float) -> void:
	var body := players[index]
	var before := body.position
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	if shop_panel.visible or blueprint_panel.visible: input = Vector2.ZERO
	if input.length() > 1.0:
		input = input.normalized()
	var direction := Vector3(input.x, 0, input.y)
	if direction.length_squared() > 0.01:
		facing[index] = direction.normalized()
		body.rotation.y = lerp_angle(body.rotation.y, atan2(direction.x, direction.z), delta * 12.0)
	var speed := SPEED
	if owned_items[index].has("boots"): speed += 1.5
	if food_time[index] > 0.0: speed += 2.0
	match active_vehicle[index]:
		"bicycle": speed = maxf(speed, 10.0)
		"motorbike": speed = maxf(speed, 13.0)
		"car": speed = maxf(speed, 16.0)
		"rowboat": speed = 6.0 if is_lake_water(body.position) else SPEED
		"speedboat": speed = 18.0 if is_lake_water(body.position) else SPEED
		"plane": speed = 21.0
	body.velocity.x = direction.x * speed
	body.velocity.z = direction.z * speed
	if active_vehicle[index] == "plane":
		var climb := float(Input.is_action_pressed("jump"))
		var descend := float(Input.is_action_pressed("plane_descend"))
		body.velocity.y = (climb - descend) * 10.0
	else:
		var jumping := Input.is_physical_key_pressed(KEY_SPACE)
		if body.is_on_floor():
			if jumping:
				body.velocity.y = JUMP_SPEED
		else:
			body.velocity.y -= GRAVITY * delta
	body.move_and_slide()
	if is_lake_water(body.position) and not active_vehicle[index] in ["rowboat", "speedboat", "plane"]:
		body.position = before
		body.velocity.x = 0.0
		body.velocity.z = 0.0
	if body.is_on_floor(): last_safe_position[index] = body.position
	if active_vehicle[index] == "plane": body.position.y = clampf(body.position.y, 1.0, 45.0)
	body.position.x = clampf(body.position.x, -WORLD_HALF.x + 1.0, WORLD_HALF.x - 1.0)
	body.position.z = clampf(body.position.z, -WORLD_HALF.y + 1.0, WORLD_HALF.y - 1.0)
	if body.position.y < -5.0:
		body.position = last_safe_position[index] + Vector3.UP * 2.0
		body.velocity = Vector3.ZERO


func is_lake_water(pos: Vector3) -> bool:
	return LAKE_WATER.has_point(Vector2(pos.x, pos.z))


func update_animals() -> void:
	for i in animals.size():
		var phase := world_clock * (0.45 if animal_kinds[i] in ["rabbit", "fish"] else 0.25) + float(i) * 1.7
		var origin := animal_origins[i]
		var creature := animals[i]
		creature.position = origin + Vector3(sin(phase) * 0.85, maxf(0.0, sin(phase * 7.0)) * 0.14 if animal_kinds[i] == "rabbit" else sin(phase * 2.0) * 0.08 if animal_kinds[i] in ["fish", "whale"] else 0.0, cos(phase) * 0.85)
		creature.rotation.y = atan2(cos(phase), -sin(phase))


func try_attack() -> void:
	var index := local_index()
	if not connected or shop_panel.visible or blueprint_panel.visible or not balloon_flights[index].is_empty(): return
	if multiplayer.is_server(): attack_nearest_enemy(index)
	else: request_attack.rpc_id(1)


@rpc("any_peer", "reliable")
func request_attack() -> void:
	if not multiplayer.is_server() or slot_for_sender() < 0: return
	attack_nearest_enemy(slot_for_sender())


func attack_nearest_enemy(index: int) -> void:
	if attack_cooldown[index] > 0.0: return
	attack_cooldown[index] = 0.55
	var origin := players[index].position
	var front := players[index].global_transform.basis.z.normalized()
	var reach := 3.3 if owned_items[index].has("sword") else 2.4
	var best_id := -1
	var best_distance := reach
	for id in enemy_states:
		var state: Dictionary = enemy_states[id]
		if not state.alive: continue
		if absf(state.position.y - origin.y) > 3.5: continue
		var delta_2d := Vector3(state.position.x - origin.x, 0, state.position.z - origin.z)
		var distance := delta_2d.length()
		if distance < best_distance and (distance < 0.7 or front.dot(delta_2d.normalized()) > 0.2):
			best_distance = distance
			best_id = id
	if best_id >= 0:
		damage_enemy(best_id, 24 if owned_items[index].has("sword") else 10, index)


func update_enemies(delta: float) -> void:
	for id in enemy_states:
		var state: Dictionary = enemy_states[id]
		if not state.alive:
			state.respawn_timer -= delta
			if state.respawn_timer <= 0.0:
				state.alive = true
				state.health = state.maximum
				state.position = state.spawn
				state.attack_timer = 0.0
				state.impact_timer = 0.0
				update_enemy_visual(id)
				sync_enemy_state.rpc(id, state.position, state.health, true)
			continue
		state.attack_timer = maxf(0.0, float(state.attack_timer) - delta)
		state.impact_timer = maxf(0.0, float(state.impact_timer) - delta)
		var closest := -1
		var closest_distance := 16.0 if state.kind in ["polar_bear", "sasquatch", "shark"] else 12.0 if state.kind == "skeleton" else 10.0
		for i in players.size():
			if i > 0 and not peer_slots.values().has(i): continue
			if not balloon_flights[i].is_empty(): continue
			if active_vehicle[i] == "plane" and players[i].position.y > 3.5: continue
			var distance := Vector2(players[i].position.x - state.position.x, players[i].position.z - state.position.z).length()
			if distance < closest_distance:
				closest = i
				closest_distance = distance
		var goal: Vector3 = state.spawn
		if closest >= 0: goal = players[closest].position
		var motion := Vector2(goal.x - state.position.x, goal.z - state.position.z)
		if motion.length() > 0.35:
			var direction := motion.normalized()
			var next_pos: Vector3 = state.position
			var chase_speed := 6.0 if state.kind == "shark" else 3.7 if state.kind == "polar_bear" else 2.8 if state.kind == "sasquatch" else 3.0 if state.kind == "skeleton" else 4.5
			next_pos.x += direction.x * chase_speed * delta
			next_pos.z += direction.y * chase_speed * delta
			var arena: Rect2 = state.arena
			next_pos.x = clampf(next_pos.x, arena.position.x, arena.end.x)
			next_pos.z = clampf(next_pos.z, arena.position.y, arena.end.y)
			state.position = next_pos
			enemy_nodes[id].rotation.y = atan2(direction.x, direction.y)
		if state.kind == "bat":
			var bat_pos: Vector3 = state.position
			bat_pos.y = 2.2 + sin(world_clock * 5.0 + float(id)) * 0.28
			state.position = bat_pos
		update_enemy_visual(id)
		if closest >= 0:
			resolve_enemy_contact(id, closest)
	enemy_sync_timer += delta
	if enemy_sync_timer >= 0.12:
		enemy_sync_timer = 0.0
		var positions: Array = []
		for id in enemy_states:
			if enemy_states[id].alive: positions.append([id, enemy_states[id].position, enemy_nodes[id].rotation.y])
		sync_enemy_positions.rpc(positions)


func resolve_enemy_contact(id: int, index: int) -> void:
	var state: Dictionary = enemy_states[id]
	if not state.alive: return
	if active_vehicle[index] == "plane" and players[index].position.y > 3.5: return
	var distance := Vector2(players[index].position.x - state.position.x, players[index].position.z - state.position.z).length()
	if distance > 1.8: return
	var vehicle := active_vehicle[index]
	var speed := Vector2(players[index].velocity.x, players[index].velocity.z).length() if index == 0 else remote_walk_speed[index]
	if vehicle in ["car", "motorbike", "bicycle", "rowboat", "speedboat"] and speed > 3.0 and state.impact_timer <= 0.0:
		state.impact_timer = 1.5
		state.attack_timer = 1.5
		var force := 100 if vehicle == "car" else 60 if vehicle == "speedboat" else 30 if vehicle == "motorbike" else 15 if vehicle == "rowboat" else 12
		damage_enemy(id, force, index)
		if vehicle == "bicycle": damage_player(index, 4)
		elif vehicle == "motorbike": damage_player(index, 2)
	elif state.attack_timer <= 0.0:
		state.attack_timer = 1.6
		var damage := 100 if state.kind == "shark" else 28 if state.kind == "sasquatch" else 20 if state.kind == "polar_bear" else 12 if state.kind == "skeleton" else 8
		if vehicle == "bicycle": damage = maxi(2, int(ceil(damage * 0.45)))
		elif vehicle == "motorbike": damage = 3
		elif vehicle == "car": damage = 1
		elif vehicle == "rowboat": damage = 18 if state.kind == "shark" else maxi(2, int(ceil(damage * 0.5)))
		elif vehicle == "speedboat": damage = 5 if state.kind == "shark" else 2
		damage_player(index, damage)


func damage_enemy(id: int, amount: int, attacker: int) -> void:
	var state: Dictionary = enemy_states[id]
	if not state.alive: return
	state.health = maxi(0, int(state.health) - amount)
	if state.health == 0:
		state.alive = false
		state.respawn_timer = 25.0
		scores[attacker] += 1
		update_score()
		sync_shop_state.rpc(scores, owned_items, active_vehicle, food_time)
		shop_notice(attacker, "+1 crystal for defeating a %s!" % state.kind)
	update_enemy_visual(id)
	sync_enemy_state.rpc(id, state.position, state.health, state.alive)


func damage_player(index: int, amount: int) -> void:
	if amount <= 0: return
	player_health[index] = maxi(0, player_health[index] - amount)
	if player_health[index] == 0:
		player_health[index] = MAX_HEALTH
		var safe_pos := Vector3(-2.0 + float(index % 6) * 2.0, 2.0, 2.0 + float(index / 6) * 2.0)
		players[index].position = safe_pos
		players[index].velocity = Vector3.ZERO
		last_safe_position[index] = safe_pos
		respawn_player_remote.rpc(index, safe_pos)
		shop_notice(index, "You fainted and woke up at the mainland.")
	update_health_ui()
	sync_health.rpc(player_health)


@rpc("authority", "reliable")
func sync_health(values: Array) -> void:
	ensure_player_slot(values.size() - 1)
	for i in values.size(): player_health[i] = int(values[i])
	update_health_ui()


@rpc("authority", "reliable")
func respawn_player_remote(index: int, pos: Vector3) -> void:
	players[index].position = pos
	players[index].velocity = Vector3.ZERO
	last_safe_position[index] = pos


func update_health_ui() -> void:
	for i in health_bars.size():
		health_bars[i].value = player_health[i]


func update_enemy_visual(id: int) -> void:
	var state: Dictionary = enemy_states[id]
	var node: Node3D = enemy_nodes[id]
	node.visible = state.alive
	node.position = state.position
	EnemyVisuals.set_health(node, state.health, state.maximum)
	var bar := node.get_node_or_null("HealthBar") as Node3D
	if bar: bar.rotation.y = -node.rotation.y


@rpc("authority", "reliable")
func sync_enemy_state(id: int, pos: Vector3, hp: int, alive: bool) -> void:
	if not enemy_states.has(id): return
	var state: Dictionary = enemy_states[id]
	state.position = pos
	state.health = hp
	state.alive = alive
	enemy_targets[id] = pos
	update_enemy_visual(id)


@rpc("authority", "unreliable")
func sync_enemy_positions(positions: Array) -> void:
	for item in positions:
		var id: int = item[0]
		if enemy_states.has(id):
			enemy_targets[id] = item[1]
			enemy_nodes[id].rotation.y = item[2]


func interpolate_enemies(delta: float) -> void:
	for id in enemy_states:
		if not enemy_states[id].alive: continue
		var node: Node3D = enemy_nodes[id]
		node.position = node.position.lerp(enemy_targets[id], minf(1.0, delta * 9.0))
		var bar := node.get_node_or_null("HealthBar") as Node3D
		if bar: bar.rotation.y = -node.rotation.y


func update_walk_animation(delta: float) -> void:
	for i in players.size():
		var speed := remote_walk_speed[i]
		if i == local_index():
			speed = Vector2(players[i].velocity.x, players[i].velocity.z).length()
		var target_amount := clampf(speed / SPEED, 0.0, 1.0)
		if active_vehicle[i] == "car" or not balloon_flights[i].is_empty(): target_amount = 0.0
		walk_amount[i] = move_toward(walk_amount[i], target_amount, delta * 5.0)
		walk_phase[i] += delta * (7.0 + speed * 0.75) * walk_amount[i]
		var model := players[i].get_node_or_null("CharacterModel")
		if not model: continue
		var left_leg := model.get_node_or_null("LeftLeg")
		var right_leg := model.get_node_or_null("RightLeg")
		if not left_leg or not right_leg: continue
		var swing := sin(walk_phase[i]) * 0.55 * walk_amount[i]
		left_leg.rotation.x = swing
		right_leg.rotation.x = -swing


func handle_building() -> void:
	if shop_panel.visible or blueprint_panel.visible or not balloon_flights[local_index()].is_empty(): return
	if Input.is_physical_key_pressed(KEY_Q): request_build(true)
	if Input.is_physical_key_pressed(KEY_E): request_build(false)


func request_build(placing: bool) -> void:
	var index := local_index()
	if cooldowns[index] > 0.0 or not connected: return
	cooldowns[index] = 0.18
	if multiplayer.is_server():
		if placing: place_block(index)
		else: remove_block(index)
	else:
		request_build_on_host.rpc_id(1, placing, target_column(index))


@rpc("any_peer", "reliable")
func request_build_on_host(placing: bool, column: Vector2i) -> void:
	if not multiplayer.is_server() or slot_for_sender() < 0: return
	var index := slot_for_sender()
	if Vector2(players[index].position.x, players[index].position.z).distance_to(Vector2(column.x, column.y)) > 3.5: return
	if placing: place_block(index, column)
	else: remove_block(index, column)


func target_column(index: int) -> Vector2i:
	var point := players[index].position + facing[index] * 1.65
	return Vector2i(roundi(point.x), roundi(point.z))


func place_block(index: int, column: Vector2i = Vector2i(999, 999)) -> void:
	if column.x == 999: column = target_column(index)
	if abs(column.x) >= WORLD_HALF.x or abs(column.y) >= WORLD_HALF.y: return
	var height := 0
	while creations.has(Vector3i(column.x, height, column.y)) and height < 7:
		height += 1
	if height >= 7:
		show_message("That tower is tall enough!", 1.5)
		return
	var pos := Vector3i(column.x, height, column.y)
	for body in players:
		if Vector2(body.position.x, body.position.z).distance_to(Vector2(pos.x, pos.z)) < 0.9 and height < 2: return
	var color: Color = palette[(creations.size() + index * 2) % palette.size()]
	add_creation(pos, color)
	add_creation_remote.rpc(pos, color)


func remove_block(index: int, column: Vector2i = Vector2i(999, 999)) -> void:
	if column.x == 999: column = target_column(index)
	for height in range(7, -1, -1):
		var key := Vector3i(column.x, height, column.y)
		if creations.has(key):
			delete_creation(key)
			delete_creation_remote.rpc(key)
			return


func add_creation(pos: Vector3i, color: Color) -> void:
	if creations.has(pos): return
	var block := cube_body(Vector3(pos.x, pos.y + 0.5, pos.z), color)
	block.name = "Creation_%s_%s_%s" % [pos.x, pos.y, pos.z]
	add_child(block)
	creations[pos] = block


func delete_creation(pos: Vector3i) -> void:
	if not creations.has(pos): return
	creations[pos].queue_free()
	creations.erase(pos)


@rpc("authority", "reliable")
func add_creation_remote(pos: Vector3i, color: Color) -> void:
	add_creation(pos, color)


@rpc("authority", "reliable")
func delete_creation_remote(pos: Vector3i) -> void:
	delete_creation(pos)


func add_scenery(pos: Vector3i, color: Color) -> void:
	var body := cube_body(Vector3(pos.x, pos.y + 0.5, pos.z), color)
	body.name = "WorldBlock"
	add_child(body)


func cube_body(pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	visual.mesh = mesh
	visual.material_override = material(color, 0.78)
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	collision.shape = shape
	body.add_child(collision)
	return body


func material(color: Color, roughness: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	return result


func spawn_crystals(count: int) -> void:
	for i in count:
		var id := next_crystal_id
		next_crystal_id += 1
		var point := Vector2.ZERO
		for attempt in 60:
			match i % 9:
				0:
					point = Vector2(rng.randi_range(-51, 51), rng.randi_range(-40, 40))
				1:
					point = Vector2(rng.randi_range(73, 157), rng.randi_range(-37, 37))
				2:
					point = Vector2(rng.randi_range(-157, -73), rng.randi_range(-37, 37))
				3:
					point = Vector2(rng.randi_range(-59, 59), rng.randi_range(-151, -73))
				4:
					point = Vector2(rng.randi_range(-58, 58), rng.randi_range(71, 153))
				5:
					point = Vector2(rng.randi_range(-162, -88), rng.randi_range(-150, -80))
				6:
					point = Vector2(rng.randi_range(88, 162), rng.randi_range(-150, -80))
				7:
					point = Vector2(rng.randi_range(-162, -88), rng.randi_range(80, 150))
				8:
					point = Vector2(rng.randi_range(88, 162), rng.randi_range(80, 150))
			if crystal_spot_clear(point): break
		var pos := Vector3(point.x, 0.75, point.y)
		add_crystal(id, pos)
		add_crystal_remote.rpc(id, pos)


func crystal_spot_clear(point: Vector2) -> bool:
	for zone in obstacle_zones:
		if zone.has_point(point): return false
	for id in PLANE_PARTS:
		var part_pos: Vector3 = PLANE_PARTS[id].position
		if Vector2(part_pos.x, part_pos.z).distance_to(point) < 3.0: return false
	for crystal in crystal_nodes.values():
		if Vector2(crystal.position.x, crystal.position.z).distance_to(point) < 3.0: return false
	return true


func add_crystal(id: int, pos: Vector3) -> void:
	if crystal_nodes.has(id): return
	var crystal := Area3D.new()
	crystal.name = "Crystal_%d" % id
	crystal.collision_layer = 0
	crystal.collision_mask = 2
	crystal.position = pos
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.75
	visual.mesh = mesh
	visual.material_override = material(Color("79f7ff"), 0.15)
	crystal.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.55
	collision.shape = shape
	crystal.add_child(collision)
	crystal.body_entered.connect(crystal_touched.bind(id))
	add_child(crystal)
	crystal_nodes[id] = crystal


@rpc("authority", "reliable")
func add_crystal_remote(id: int, pos: Vector3) -> void:
	add_crystal(id, pos)


func crystal_touched(body: Node3D, id: int) -> void:
	if not crystal_nodes.has(id): return
	var index := -1
	for i in players.size():
		if players[i] == body:
			index = i
			break
	if index < 0: return
	if multiplayer.is_server() and index > 0 and not peer_slots.values().has(index): return
	if not multiplayer.is_server():
		if index == local_index(): request_crystal.rpc_id(1, id, players[index].position)
		return
	collect_crystal(index, id)


func check_local_crystal_pickups() -> void:
	var index := local_index()
	for id in crystal_nodes.keys():
		if players[index].position.distance_to(crystal_nodes[id].position) > 1.2: continue
		if multiplayer.is_server(): collect_crystal(index, id)
		else: request_crystal.rpc_id(1, id, players[index].position)


func check_local_plane_materials() -> void:
	var index := local_index()
	for id in PLANE_PARTS:
		if found_parts[index].has(id): continue
		if players[index].position.distance_to(PLANE_PARTS[id].position) > 1.5: continue
		if multiplayer.is_server(): collect_plane_material(index, id)
		else: request_plane_material.rpc_id(1, id, players[index].position)


@rpc("any_peer", "reliable")
func request_plane_material(id: String, reported_pos: Vector3) -> void:
	if not multiplayer.is_server() or slot_for_sender() < 0 or not PLANE_PARTS.has(id): return
	var index := slot_for_sender()
	if reported_pos.distance_to(PLANE_PARTS[id].position) > 1.5: return
	if reported_pos.distance_to(players[index].position) > 8.0: return
	players[index].position = reported_pos
	collect_plane_material(index, id)


func collect_plane_material(index: int, id: String) -> void:
	if not PLANE_PARTS.has(id) or found_parts[index].has(id): return
	found_parts[index][id] = true
	update_local_material_visibility()
	material_found_remote.rpc(index, id)
	shop_notice(index, "Found %s! Plane parts: %d/%d" % [PLANE_PARTS[id].label, found_parts[index].size(), PLANE_PARTS.size()])
	refresh_shop()
	refresh_blueprint()


@rpc("authority", "reliable")
func material_found_remote(index: int, id: String) -> void:
	if not PLANE_PARTS.has(id): return
	ensure_player_slot(index)
	found_parts[index][id] = true
	update_local_material_visibility()
	refresh_shop()
	refresh_blueprint()


func update_local_material_visibility() -> void:
	var index := local_index()
	if index >= found_parts.size(): return
	for id in material_nodes:
		material_nodes[id].visible = not found_parts[index].has(id)


@rpc("any_peer", "reliable")
func request_crystal(id: int, reported_pos: Vector3) -> void:
	if not multiplayer.is_server() or slot_for_sender() < 0 or not crystal_nodes.has(id): return
	var index := slot_for_sender()
	if is_lake_water(reported_pos) and not active_vehicle[index] in ["rowboat", "speedboat", "plane"]: return
	if reported_pos.distance_to(crystal_nodes[id].position) > 2.0: return
	if reported_pos.distance_to(players[index].position) > 8.0: return
	players[index].position = reported_pos
	collect_crystal(index, id)


func collect_crystal(index: int, id: int) -> void:
	if not crystal_nodes.has(id): return
	scores[index] += 1
	crystals_collected += 1
	delete_crystal(id)
	update_score()
	crystal_collected_remote.rpc(id, scores)
	if crystals_collected % CRYSTALS_PER_ROUND == 0:
		show_message("You found them all! New crystals appeared.", 4.0)
		await get_tree().create_timer(1.5).timeout
		spawn_crystals(CRYSTALS_PER_ROUND)


func delete_crystal(id: int) -> void:
	if not crystal_nodes.has(id): return
	crystal_nodes[id].queue_free()
	crystal_nodes.erase(id)


@rpc("authority", "reliable")
func crystal_collected_remote(id: int, new_scores: Array) -> void:
	delete_crystal(id)
	ensure_player_slot(new_scores.size() - 1)
	for i in new_scores.size(): scores[i] = int(new_scores[i])
	update_score()


func update_score() -> void:
	if score_label:
		var lines := ["CRYSTALS"]
		var row: Array[String] = []
		for i in scores.size():
			row.append("P%d %02d" % [i + 1, scores[i]])
			if row.size() == 4:
				lines.append("   ".join(row))
				row.clear()
		if not row.is_empty(): lines.append("   ".join(row))
		score_label.text = "\n".join(lines)
		score_panel.size.y = 14.0 + float(lines.size()) * 27.0
		location_panel.position.y = score_panel.position.y + score_panel.size.y + 8.0
	refresh_shop()


func show_message(text: String, duration: float) -> void:
	if message_label: message_label.text = text
	message_time = duration


func update_location_label() -> void:
	if not location_label: return
	var pos := players[local_index()].position
	var area := "Central crossroads"
	if pos.x <= -83.0 and pos.z <= -75.0: area = "Crystal Caverns"
	elif pos.x >= 83.0 and pos.z <= -75.0: area = "Volcano"
	elif pos.x <= -83.0 and pos.z >= 75.0: area = "Golden Dunes"
	elif pos.x >= 83.0 and pos.z >= 75.0: area = "Jungle Ruins"
	elif pos.z <= -67.0 and absf(pos.x) <= 64.0: area = "Arctic tundra"
	elif pos.z >= 65.0 and absf(pos.x) <= 63.0: area = "Lake water" if is_lake_water(pos) else "Lake shore"
	elif pos.x <= -69.0: area = "Wildwood forest"
	elif pos.x >= 69.0:
		area = "Bat cave" if Vector2(pos.x, pos.z).distance_to(Vector2(100, 18)) < 12.0 or Vector2(pos.x, pos.z).distance_to(Vector2(130, -3)) < 11.0 else "Mountain range"
	elif pos.x >= 16.0 and pos.x <= 37.0 and pos.z >= -29.0 and pos.z <= -9.0: area = "Cemetery"
	elif pos.x < -8.0 and pos.z < -7.0: area = "Pine forest"
	elif pos.x > 8.0 and pos.z < -7.0: area = "Rocky highlands"
	elif pos.x < -8.0 and pos.z > 7.0: area = "Sunny meadow"
	elif pos.x > 8.0 and pos.z > 7.0: area = "Sandy desert"
	location_label.text = "%s  (%d, %d)" % [area, roundi(pos.x), roundi(pos.z)]


func update_camera(delta: float) -> void:
	if players.size() < 2 or not camera: return
	var focus := players[local_index()].position
	camera.position = camera.position.lerp(focus + Vector3(0, 14, 10), minf(1.0, delta * 4.0))
	camera.look_at(focus + Vector3.UP * 0.7, Vector3.UP)
