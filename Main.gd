extends Node3D

# Two-player LAN creative playground. The host owns shared world state.
const CharacterFactory = preload("res://ProceduralCharacter.gd")
const VehicleVisuals = preload("res://VehicleFactory.gd")
const MinimapView = preload("res://Minimap.gd")
const BalloonVisuals = preload("res://BalloonFactory.gd")
const AnimalVisuals = preload("res://AnimalFactory.gd")
const EnemyVisuals = preload("res://EnemyFactory.gd")
const MAIN_HALF := Vector2i(48, 36)
const WORLD_HALF := Vector2i(154, 40)
const CRYSTALS_PER_ROUND := 36
const BALLOON_TRAVEL_TIME := 14.0
const SPEED := 7.0
const JUMP_SPEED := 8.5
const GRAVITY := 22.0
const MAX_HEALTH := 100
const SHOP_ITEMS := {
	"food": {"label": "Snack - heal 30 HP + speed boost", "cost": 2},
	"lantern": {"label": "Lantern - portable light", "cost": 3},
	"boots": {"label": "Speed boots - permanent boost", "cost": 5},
	"sword": {"label": "Sword - stronger attacks", "cost": 4},
	"bicycle": {"label": "Bicycle - faster travel", "cost": 6},
	"motorbike": {"label": "Motorbike - quick travel", "cost": 9},
	"car": {"label": "Car - fastest travel", "cost": 12}
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
var message_label: Label
var message_time := 0.0
var rng := RandomNumberGenerator.new()
var obstacle_zones: Array[Rect2] = []
var location_label: Label
var palette := [Color("ef6f6c"), Color("ffd166"), Color("61d095"), Color("5aa9e6"), Color("b388eb"), Color("ff9f1c")]
var crystal_nodes: Dictionary = {}
var next_crystal_id := 0
var connected := false
var guest_peer_id := 0
var position_timer := 0.0
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
var minimap_panel: PanelContainer
var minimap_view: Control
var minimap_timer := 0.0


func _ready() -> void:
	rng.seed = 481516
	UIManager.visible = false
	make_world()
	make_players()
	make_camera()
	make_hud()
	setup_network()
	if GameManager.network_mode == "host":
		spawn_crystals(CRYSTALS_PER_ROUND)
		show_message("Hosting on UDP port %d. Waiting for Player 2..." % GameManager.network_port, 8.0)
	else:
		show_message("Connecting to %s..." % GameManager.host_address, 8.0)


func setup_network() -> void:
	print("LAN setup: ", GameManager.network_mode, " port ", GameManager.network_port)
	var peer := ENetMultiplayerPeer.new()
	var error := OK
	if GameManager.network_mode == "host":
		error = peer.create_server(GameManager.network_port, 1)
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
	if GameManager.network_mode == "host":
		connected = true


func on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server(): return
	guest_peer_id = peer_id
	show_message("Player 2 joined! Build and explore together.", 4.0)


@rpc("any_peer", "reliable")
func request_world() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != guest_peer_id: return
	var peer_id := multiplayer.get_remote_sender_id()
	var snapshot: Array = []
	for key in creations:
		snapshot.append([key, (creations[key] as StaticBody3D).get_child(0).material_override.albedo_color])
	var crystals: Array = []
	for id in crystal_nodes:
		crystals.append([id, crystal_nodes[id].position])
	receive_world.rpc_id(peer_id, snapshot, crystals, scores, owned_items, active_vehicle, food_time, player_health, enemy_states, players[0].position, GameManager.character_data, world_clock, balloon_flights)


func on_peer_disconnected(_peer_id: int) -> void:
	show_message("Other player disconnected.", 20.0)
	if multiplayer.is_server():
		guest_peer_id = 0
		players[1].position = Vector3(2, 1, 2)


func on_connected_to_server() -> void:
	print("LAN client: connected")
	connected = true
	show_message("Connected! Build and explore together.", 4.0)
	set_player_appearance(1, GameManager.character_data)
	send_appearance.rpc_id(1, GameManager.character_data)
	request_world.rpc_id(1)


func on_connection_failed() -> void:
	show_message("Could not connect. Check the host IP and Windows firewall (UDP %d)." % GameManager.network_port, 30.0)


@rpc("authority", "reliable")
func receive_world(snapshot: Array, crystals: Array, new_scores: Array, new_owned: Array, new_vehicles: Array, new_food_time: Array, new_health: Array, new_enemies: Dictionary, host_pos: Vector3, host_appearance: Dictionary, host_clock: float, flights: Array) -> void:
	print("LAN client: received world with ", crystals.size(), " crystals")
	if multiplayer.is_server(): return
	for item in snapshot:
		add_creation(item[0], item[1])
	for item in crystals:
		add_crystal(item[0], item[1])
	scores[0] = int(new_scores[0])
	scores[1] = int(new_scores[1])
	player_health[0] = int(new_health[0])
	player_health[1] = int(new_health[1])
	update_health_ui()
	for id in new_enemies:
		if not enemy_states.has(id): continue
		enemy_states[id] = new_enemies[id].duplicate()
		enemy_targets[id] = enemy_states[id].position
		update_enemy_visual(id)
	apply_shop_state(new_owned, new_vehicles, new_food_time)
	players[0].position = host_pos
	world_clock = host_clock
	for i in 2:
		if not flights[i].is_empty(): start_balloon_visual(i)
		balloon_flights[i] = flights[i].duplicate()
	set_player_appearance(0, host_appearance)
	update_score()


@rpc("any_peer", "reliable")
func send_appearance(data: Dictionary) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != guest_peer_id: return
	set_player_appearance(1, data)
	apply_appearance.rpc(data)


@rpc("authority", "reliable")
func apply_appearance(data: Dictionary) -> void:
	set_player_appearance(1, data)


func set_player_appearance(index: int, data: Dictionary) -> void:
	if data.is_empty(): return
	var old := players[index].get_node_or_null("CharacterModel")
	if old:
		old.name = "OldCharacterModel"
		old.queue_free()
	var model: Node3D = CharacterFactory.create(data.get("body_shape", "default"), data.get("animal_type", "rabbit"), data.get("body_color", Color.WHITE), data.get("shirt_type", "basic_tshirt"), data.get("pants_type", "jeans"), data.get("shoes_type", "sneakers"))
	model.name = "CharacterModel"
	model.position.y = 0.5 if active_vehicle[index] == "car" else 0.05
	players[index].add_child(model)


@rpc("any_peer", "unreliable")
func submit_position(pos: Vector3, rotation_y: float, speed: float) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != guest_peer_id: return
	if pos.distance_to(players[1].position) > 4.0: return
	players[1].position = pos
	players[1].rotation.y = rotation_y
	remote_walk_speed[1] = speed
	relay_position.rpc(1, pos, rotation_y, speed)


@rpc("authority", "unreliable")
func relay_position(index: int, pos: Vector3, rotation_y: float, speed: float) -> void:
	if index == local_index(): return
	players[index].position = pos
	players[index].rotation.y = rotation_y
	remote_walk_speed[index] = speed


func local_index() -> int:
	return 0 if GameManager.network_mode == "host" else 1


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
	add_cemetery()
	make_remote_places()


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
	var maximum := 24 if kind == "bat" else 40
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
	add_island_ground("MountainIsland", Vector2(115, 0), Vector2(70, 68), Color("777b78"))
	add_island_ground("WildwoodIsland", Vector2(-115, 0), Vector2(70, 68), Color("407c4e"))
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
	add_balloon_station(Vector3(42, 1, -2), Vector3(86, 1, -2), "Mountains")
	add_balloon_station(Vector3(86, 1, -2), Vector3(42, 1, -2), "Mainland")
	add_balloon_station(Vector3(-42, 1, 2), Vector3(-86, 1, 2), "Wildwood")
	add_balloon_station(Vector3(-86, 1, 2), Vector3(-42, 1, 2), "Mainland")


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
	panel.color = Color(0.025, 0.04, 0.075, 0.82)
	panel.position = Vector2(18, 18)
	panel.size = Vector2(690, 112)
	layer.add_child(panel)
	var title := Label.new()
	title.position = Vector2(20, 10)
	title.add_theme_font_size_override("font_size", 25)
	title.text = "TWO PLAYER CREATIVE WORLD"
	panel.add_child(title)
	var controls := Label.new()
	controls.position = Vector2(20, 47)
	controls.text = "WASD / arrows move  |  Space jump  |  Q place  |  E remove  |  R attack\nB shop  |  M map  |  F board balloon near a landing."
	controls.add_theme_color_override("font_color", Color("d8e8ff"))
	panel.add_child(controls)
	var health_panel := ColorRect.new()
	health_panel.color = Color(0.025, 0.04, 0.075, 0.82)
	health_panel.position = Vector2(18, 140)
	health_panel.size = Vector2(265, 72)
	layer.add_child(health_panel)
	for i in 2:
		var label := Label.new()
		label.text = "P%d HP" % (i + 1)
		label.position = Vector2(10, 9 + i * 31)
		health_panel.add_child(label)
		var bar := ProgressBar.new()
		bar.position = Vector2(67, 10 + i * 31)
		bar.size = Vector2(185, 18)
		bar.max_value = MAX_HEALTH
		bar.value = MAX_HEALTH
		bar.show_percentage = true
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("77d779") if i == 0 else Color("e9aa69")
		bar.add_theme_stylebox_override("fill", fill)
		health_panel.add_child(bar)
		health_bars.append(bar)
	score_label = Label.new()
	score_label.position = Vector2(735, 24)
	score_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(score_label)
	location_label = Label.new()
	location_label.position = Vector2(735, 103)
	location_label.add_theme_font_size_override("font_size", 17)
	location_label.add_theme_color_override("font_color", Color("e8f4ce"))
	layer.add_child(location_label)
	message_label = Label.new()
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.position = Vector2(-350, 145)
	message_label.size = Vector2(700, 45)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 20)
	message_label.add_theme_color_override("font_color", Color("fff0a6"))
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
	layer.add_child(travel_label)
	make_minimap(layer)
	make_shop(layer)
	update_score()
	update_health_ui()


func make_minimap(layer: CanvasLayer) -> void:
	minimap_panel = PanelContainer.new()
	minimap_panel.name = "MinimapPanel"
	minimap_panel.anchor_left = 1.0
	minimap_panel.anchor_right = 1.0
	minimap_panel.offset_left = -250
	minimap_panel.offset_right = -16
	minimap_panel.offset_top = 16
	minimap_panel.offset_bottom = 238
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
	minimap_view.custom_minimum_size = Vector2(216, 157)
	minimap_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(minimap_view)
	var legend := Label.new()
	legend.text = "White you | Orange pal | Cyan gem\nPurple balloon | Tan wildlife"
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
	shop_panel.offset_top = -245
	shop_panel.offset_bottom = 245
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_B:
			shop_panel.visible = not shop_panel.visible
			refresh_shop()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_M:
			toggle_minimap()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F:
			try_board_balloon()
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
		request_balloon.rpc_id(1, station_index)


@rpc("any_peer", "reliable")
func request_balloon(station_index: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != guest_peer_id: return
	begin_balloon_flight(1, station_index)


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
	for i in 2:
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
	var station_index := nearby_balloon_station(index)
	hint.text = "Press F: balloon to %s" % balloon_stations[station_index].destination if station_index >= 0 else ""


func refresh_shop() -> void:
	if not shop_status: return
	var index := local_index()
	shop_status.text = "Your crystals: %d" % scores[index]
	for id in SHOP_ITEMS:
		var definition: Dictionary = SHOP_ITEMS[id]
		var suffix := " - %d crystals" % definition.cost
		if owned_items[index].has(id):
			if id in ["car", "motorbike", "bicycle"]:
				suffix = " - Riding (click to park)" if active_vehicle[index] == id else " - Owned (click to ride)"
			else:
				suffix = " - Owned"
		shop_buttons[id].text = definition.label + suffix
		shop_buttons[id].disabled = owned_items[index].has(id) and id in ["lantern", "boots"]


func on_shop_item_pressed(id: String) -> void:
	if multiplayer.is_server():
		process_shop_action(0, id)
	elif connected:
		request_shop_action.rpc_id(1, id)


@rpc("any_peer", "reliable")
func request_shop_action(id: String) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != guest_peer_id: return
	process_shop_action(1, id)


func process_shop_action(index: int, id: String) -> void:
	if not SHOP_ITEMS.has(id): return
	var notice := "Purchased %s!" % SHOP_ITEMS[id].label
	if owned_items[index].has(id) and id in ["car", "motorbike", "bicycle"]:
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
			if id in ["car", "motorbike", "bicycle"]:
				active_vehicle[index] = id
	apply_equipment(index)
	update_score()
	sync_shop_state.rpc(scores, owned_items, active_vehicle, food_time)
	shop_notice(index, notice)


func shop_notice(index: int, notice: String) -> void:
	if index == 0:
		show_message(notice, 3.0)
	elif guest_peer_id != 0:
		receive_shop_notice.rpc_id(guest_peer_id, notice)


@rpc("authority", "reliable")
func receive_shop_notice(notice: String) -> void:
	show_message(notice, 3.0)


@rpc("authority", "reliable")
func sync_shop_state(new_scores: Array, new_owned: Array, new_vehicles: Array, new_food_time: Array) -> void:
	for i in 2:
		scores[i] = int(new_scores[i])
	apply_shop_state(new_owned, new_vehicles, new_food_time)
	update_score()


func apply_shop_state(new_owned: Array, new_vehicles: Array, new_food_time: Array) -> void:
	for i in 2:
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
		model.position.y = 0.5 if active_vehicle[index] == "car" else 0.05


func _physics_process(delta: float) -> void:
	world_clock += delta
	update_animals()
	for i in 2:
		attack_cooldown[i] = maxf(0.0, attack_cooldown[i] - delta)
	for i in 2:
		food_time[i] = maxf(0.0, food_time[i] - delta)
	if balloon_flights[local_index()].is_empty(): move_player(local_index(), delta)
	update_balloon_flights(delta)
	if multiplayer.is_server(): update_enemies(delta)
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
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	if shop_panel.visible: input = Vector2.ZERO
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
	body.velocity.x = direction.x * speed
	body.velocity.z = direction.z * speed
	var jumping := Input.is_physical_key_pressed(KEY_SPACE)
	if body.is_on_floor():
		if jumping:
			body.velocity.y = JUMP_SPEED
	else:
		body.velocity.y -= GRAVITY * delta
	body.move_and_slide()
	if body.is_on_floor(): last_safe_position[index] = body.position
	body.position.x = clampf(body.position.x, -WORLD_HALF.x + 1.0, WORLD_HALF.x - 1.0)
	body.position.z = clampf(body.position.z, -WORLD_HALF.y + 1.0, WORLD_HALF.y - 1.0)
	if body.position.y < -5.0:
		body.position = last_safe_position[index] + Vector3.UP * 2.0
		body.velocity = Vector3.ZERO


func update_animals() -> void:
	for i in animals.size():
		var phase := world_clock * (0.45 if animal_kinds[i] == "rabbit" else 0.25) + float(i) * 1.7
		var origin := animal_origins[i]
		var creature := animals[i]
		creature.position = origin + Vector3(sin(phase) * 0.85, maxf(0.0, sin(phase * 7.0)) * 0.14 if animal_kinds[i] == "rabbit" else 0.0, cos(phase) * 0.85)
		creature.rotation.y = atan2(cos(phase), -sin(phase))


func try_attack() -> void:
	var index := local_index()
	if not connected or shop_panel.visible or not balloon_flights[index].is_empty(): return
	if multiplayer.is_server(): attack_nearest_enemy(index)
	else: request_attack.rpc_id(1)


@rpc("any_peer", "reliable")
func request_attack() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != guest_peer_id: return
	attack_nearest_enemy(1)


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
		var closest_distance := 12.0 if state.kind == "skeleton" else 10.0
		for i in 2:
			if not balloon_flights[i].is_empty(): continue
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
			next_pos.x += direction.x * (3.0 if state.kind == "skeleton" else 4.5) * delta
			next_pos.z += direction.y * (3.0 if state.kind == "skeleton" else 4.5) * delta
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
	var distance := Vector2(players[index].position.x - state.position.x, players[index].position.z - state.position.z).length()
	if distance > 1.8: return
	var vehicle := active_vehicle[index]
	var speed := Vector2(players[index].velocity.x, players[index].velocity.z).length() if index == 0 else remote_walk_speed[index]
	if vehicle in ["car", "motorbike", "bicycle"] and speed > 3.0 and state.impact_timer <= 0.0:
		state.impact_timer = 1.5
		state.attack_timer = 1.5
		var force := 100 if vehicle == "car" else 30 if vehicle == "motorbike" else 12
		damage_enemy(id, force, index)
		if vehicle == "bicycle": damage_player(index, 4)
		elif vehicle == "motorbike": damage_player(index, 2)
	elif state.attack_timer <= 0.0:
		state.attack_timer = 1.6
		var damage := 12 if state.kind == "skeleton" else 8
		if vehicle == "bicycle": damage = maxi(2, int(ceil(damage * 0.45)))
		elif vehicle == "motorbike": damage = 3
		elif vehicle == "car": damage = 1
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
		var safe_pos := Vector3(-2.0 + index * 4.0, 2.0, 2.0)
		players[index].position = safe_pos
		players[index].velocity = Vector3.ZERO
		last_safe_position[index] = safe_pos
		respawn_player_remote.rpc(index, safe_pos)
		shop_notice(index, "You fainted and woke up at the mainland.")
	update_health_ui()
	sync_health.rpc(player_health)


@rpc("authority", "reliable")
func sync_health(values: Array) -> void:
	player_health[0] = int(values[0])
	player_health[1] = int(values[1])
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
	if shop_panel.visible or not balloon_flights[local_index()].is_empty(): return
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
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != guest_peer_id: return
	if Vector2(players[1].position.x, players[1].position.z).distance_to(Vector2(column.x, column.y)) > 3.5: return
	if placing: place_block(1, column)
	else: remove_block(1, column)


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
			match i % 4:
				0, 1:
					point = Vector2(rng.randi_range(-44, 44), rng.randi_range(-31, 31))
				2:
					point = Vector2(rng.randi_range(83, 147), rng.randi_range(-30, 30))
				3:
					point = Vector2(rng.randi_range(-147, -83), rng.randi_range(-30, 30))
			if crystal_spot_clear(point): break
		var pos := Vector3(point.x, 0.75, point.y)
		add_crystal(id, pos)
		add_crystal_remote.rpc(id, pos)


func crystal_spot_clear(point: Vector2) -> bool:
	for zone in obstacle_zones:
		if zone.has_point(point): return false
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
	if not multiplayer.is_server():
		if index == 1: request_crystal.rpc_id(1, id)
		return
	collect_crystal(index, id)


@rpc("any_peer", "reliable")
func request_crystal(id: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != guest_peer_id or not crystal_nodes.has(id): return
	if players[1].position.distance_to(crystal_nodes[id].position) > 2.0: return
	collect_crystal(1, id)


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
	scores[0] = int(new_scores[0])
	scores[1] = int(new_scores[1])
	update_score()


func update_score() -> void:
	if score_label:
		score_label.text = "CRYSTALS\nP1  %02d     P2  %02d" % [scores[0], scores[1]]
	refresh_shop()


func show_message(text: String, duration: float) -> void:
	if message_label: message_label.text = text
	message_time = duration


func update_location_label() -> void:
	if not location_label: return
	var pos := players[local_index()].position
	var area := "Central crossroads"
	if pos.x <= -80.0: area = "Wildwood forest"
	elif pos.x >= 80.0:
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
