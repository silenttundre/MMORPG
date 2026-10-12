extends Node

var character_data: Dictionary = {}
var network_mode: String = "host"
var host_address: String = "127.0.0.1"
var network_port: int = 24567

func go_to_main_scene():
	get_tree().change_scene_to_file("res://Main.tscn")
