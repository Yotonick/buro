extends Node
## Пользовательские настройки (имя, последний IP). Хранятся в user://settings.cfg.

const PATH := "user://settings.cfg"

var player_name := "Ремонтник"
var last_address := ""
var port := 27015

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	player_name = str(cfg.get_value("player", "name", player_name))
	last_address = str(cfg.get_value("net", "last_address", last_address))
	port = int(cfg.get_value("net", "port", port))

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("net", "last_address", last_address)
	cfg.set_value("net", "port", port)
	cfg.save(PATH)
