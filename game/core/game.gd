extends Node
## Поток игры: меню <-> лобби. Также разбирает аргументы командной строки
## (быстрый запуск и автотесты): -- --host | --join=IP [--port=N] [--name=X]
## [--report-after=СЕК] [--quit-after=СЕК] | --playground | --probe (автотесты, см. tests/net_probe.gd)

const MENU := "res://ui/main_menu.tscn"
const LOBBY := "res://ui/lobby.tscn"
const PLAYGROUND := "res://levels/test_room/test_room.tscn"
## Уровни, на которые хост может отправить бригаду (по сети передаётся только ключ).
const LEVELS := {"polygon": PLAYGROUND}

## Сообщение, которое меню покажет при следующем открытии (причина разрыва).
var pending_message := ""
## Ключ уровня, на котором сейчас бригада ("" — в меню или лобби).
var current_level := ""

func _ready() -> void:
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	Net.player_joined.connect(_on_player_joined)
	_apply_cmdline.call_deferred()

func _on_session_started() -> void:
	current_level = ""
	get_tree().change_scene_to_file(LOBBY)

func _on_session_ended(reason: String) -> void:
	current_level = ""
	pending_message = reason
	get_tree().change_scene_to_file(MENU)

## Полигон: одиночная тестовая комната.
func open_playground() -> void:
	get_tree().change_scene_to_file(PLAYGROUND)

## Хост отправляет всю бригаду из лобби на уровень.
## Сначала уровень загружает сам хост, и только потом зовёт остальных:
## иначе быстрый клиент постучится в мир, которого у хоста ещё нет.
func start_match(level := "polygon") -> void:
	if not Net.is_host() or current_level != "" or not LEVELS.has(level):
		return
	current_level = level
	get_tree().change_scene_to_file(LEVELS[level])
	await get_tree().scene_changed
	if Net.is_host() and current_level == level:
		_enter_level.rpc(level)

@rpc("authority", "call_remote", "reliable")
func _enter_level(level: String) -> void:
	if not LEVELS.has(level) or not Net.in_session():
		return
	current_level = level
	get_tree().change_scene_to_file(LEVELS[level])

## Кто подключился, когда смена уже идёт, — сразу попадает на уровень.
func _on_player_joined(id: int) -> void:
	if Net.is_host() and current_level != "":
		_enter_level.rpc_id(id, current_level)

func to_menu() -> void:
	current_level = ""
	Net.leave()
	get_tree().change_scene_to_file(MENU)

func _apply_cmdline() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.is_empty():
		return
	if args.has("probe"):
		var probe: Node = load("res://tests/net_probe.gd").new()
		probe.args = args
		add_child(probe)
	if args.has("playground"):
		open_playground()
	var player_name := str(args.get("name", Settings.player_name))
	var port := int(args.get("port", Settings.port))
	var err := ""
	if args.has("host"):
		err = Net.host_game(player_name, port)
	elif args.has("join"):
		err = Net.join_game(player_name, str(args["join"]), port)
	if err != "":
		print("NET_ERROR ", err)
	Net.session_ended.connect(func(reason: String): print("SESSION_ENDED ", reason))
	if args.has("report-after"):
		get_tree().create_timer(float(args["report-after"])).timeout.connect(_report)
	if args.has("quit-after"):
		get_tree().create_timer(float(args["quit-after"])).timeout.connect(get_tree().quit)

func _report() -> void:
	var names: Array = []
	for id in Net.players:
		names.append("%s#%d" % [Net.players[id]["name"], Net.players[id]["slot"]])
	names.sort()
	print("REPORT ", JSON.stringify({"in_session": Net.in_session(), "host": Net.is_host(),
		"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene else "",
		"players": names}))
