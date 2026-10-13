extends Control

# Draws the same fixed-size overview for each client. Markers are read from the
# local world nodes, which are already synchronized by the host.
var game
var half_world := Vector2(190, 190)


func _draw() -> void:
	if game == null: return
	var bounds := Rect2(Vector2(7, 7), size - Vector2(14, 14))
	draw_rect(bounds, Color("316684"))
	draw_world_rect(Vector2.ZERO, Vector2(112, 90), Color("659e65"))
	draw_world_rect(Vector2(-115, 0), Vector2(92, 84), Color("39734c"))
	draw_world_rect(Vector2(115, 0), Vector2(92, 84), Color("777d7c"))
	draw_world_rect(Vector2(0, -112), Vector2(128, 90), Color("e2eef0"))
	draw_world_rect(Vector2(0, 112), Vector2(126, 94), Color("70a864"))
	draw_world_rect(Vector2(0, 112), Vector2(84, 58), Color("38a6c9"))
	draw_world_rect(Vector2(-125, -115), Vector2(84, 80), Color("514862"))
	draw_world_rect(Vector2(125, -115), Vector2(84, 80), Color("794438"))
	draw_world_rect(Vector2(-125, 115), Vector2(84, 80), Color("d8b970"))
	draw_world_rect(Vector2(125, 115), Vector2(84, 80), Color("397b50"))
	# Match the four terrain regions and central crossroads in Main.gd.
	draw_world_rect(Vector2(-26, -19), Vector2(36, 27), Color("39774d"))
	draw_world_rect(Vector2(26, -19), Vector2(36, 27), Color("777d7c"))
	draw_world_rect(Vector2(-26, 19), Vector2(36, 27), Color("94bc64"))
	draw_world_rect(Vector2(26, 19), Vector2(36, 27), Color("d9bd78"))
	draw_world_rect(Vector2.ZERO, Vector2(12, 60), Color("aa9b70"))
	draw_world_rect(Vector2.ZERO, Vector2(86, 7), Color("aa9b70"))
	draw_world_rect(Vector2(26, -19), Vector2(22, 20), Color("42474e"))
	draw_world_rect(Vector2(100, 18), Vector2(18, 17), Color("292d35"))
	draw_world_rect(Vector2(130, -3), Vector2(18, 17), Color("292d35"))
	draw_circle(world_to_map(Vector2.ZERO), 2.5, Color("f0c779"))
	for zone in game.obstacle_zones:
		var center: Vector2 = zone.get_center()
		draw_circle(world_to_map(center), 1.3, Color(0.13, 0.25, 0.18, 0.8))
	for station in game.balloon_stations:
		var from: Vector3 = station.from
		draw_circle(world_to_map(Vector2(from.x, from.z)), 3.0, Color("db9aff"))
	for block_pos in game.creations:
		var point := world_to_map(Vector2(block_pos.x, block_pos.z))
		draw_rect(Rect2(point - Vector2.ONE * 1.4, Vector2.ONE * 2.8), Color("ffe184"))
	for crystal in game.crystal_nodes.values():
		var point := world_to_map(Vector2(crystal.position.x, crystal.position.z))
		draw_circle(point, 2.4, Color("72f6ff"))
	for animal in game.animals:
		draw_circle(world_to_map(Vector2(animal.position.x, animal.position.z)), 1.7, Color("e6b580"))
	for id in game.enemy_states:
		if not game.enemy_states[id].alive: continue
		var enemy = game.enemy_nodes[id]
		draw_circle(world_to_map(Vector2(enemy.position.x, enemy.position.z)), 2.5, Color("f35f61"))
	for i in game.players.size():
		var player = game.players[i]
		var point := world_to_map(Vector2(player.position.x, player.position.z))
		draw_circle(point, 5.5, Color("13232b"))
		draw_circle(point, 3.7, Color.WHITE if i == game.local_index() else Color("ff8659"))
	draw_rect(bounds, Color("dce9db"), false, 1.5)


func draw_world_rect(center: Vector2, world_size: Vector2, color: Color) -> void:
	var start := world_to_map(center - world_size * 0.5)
	var end := world_to_map(center + world_size * 0.5)
	draw_rect(Rect2(start, end - start), color)


func world_to_map(point: Vector2) -> Vector2:
	var bounds := Rect2(Vector2(7, 7), size - Vector2(14, 14))
	return bounds.position + Vector2(
		(point.x + half_world.x) / (half_world.x * 2.0) * bounds.size.x,
		(point.y + half_world.y) / (half_world.y * 2.0) * bounds.size.y
	)
