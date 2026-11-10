extends Node
## Помощник сетевых автотестов (включается аргументом --probe, в обычной игре не участвует).
##   --autostart=N       хост начинает смену, когда в лобби N игроков
##   --walk=A-B          свой персонаж идёт вперёд с A по B секунду на уровне
##   --grab=A-B          свой персонаж в это время тянет обе руки вперёд-вниз
##   --ko=Имя@T          хост на T-й секунде уровня отправляет игрока в нокаут
##   --bad-link=З,Р,П    плохая связь: задержка З с, разброс Р с, потери П (0..1) для входящих снимков
##   --probe-report=T    на T-й секунде от запуска печатает состояние мира (строка PROBE)

var args := {}
var _level: Node
var _me: Kombez
var _t := 0.0
var _ko_done := false
var _prev := {}      ## имя -> позиция на прошлом тике
var _steps := {}     ## имя -> [тиков в движении, из них рывков] (плавность картинки)

func _ready() -> void:
	if args.has("bad-link"):
		var v: PackedStringArray = str(args["bad-link"]).split(",")
		load("res://net/net_world.gd").sim_bad_link = [float(v[0]), float(v[1]), float(v[2])]
	if args.has("probe-report"):
		get_tree().create_timer(float(args["probe-report"])).timeout.connect(_report)

func _physics_process(dt: float) -> void:
	if args.has("autostart") and Net.is_host() and Game.current_level == "" \
			and Net.players.size() >= int(args["autostart"]):
		Game.start_match()
	var scene := get_tree().current_scene
	if scene == null or not ("world" in scene):
		_level = null
		return
	if scene != _level:
		_level = scene
		_t = 0.0
		_me = null
	_t += dt
	if _me == null and is_instance_valid(_level.player):
		_me = _level.player
		_level.controller.kombez = null
	if _me != null and is_instance_valid(_me):
		_me.in_move = Vector2(0, -1) if _in_window("walk") else Vector2.ZERO
		var grab := _in_window("grab")
		_me.in_grab_l = grab
		_me.in_grab_r = grab
		_me.in_aim_pitch = -0.75 if grab else 0.0
	for k in get_tree().get_nodes_in_group("kombez"):
		if k.peer_id <= 0:
			continue
		var p: Vector3 = k.global_position
		if _prev.has(k.player_name) and k.visual_velocity().length() > 4.0 and not k.is_ko():
			var step: float = p.distance_to(_prev[k.player_name])
			var nb: Array = _steps.get(k.player_name, [0, 0])
			_steps[k.player_name] = [nb[0] + 1, nb[1] + int(step < 0.035 or step > 0.105)]
		_prev[k.player_name] = p
	if args.has("ko") and not _ko_done and Net.is_host():
		var parts: PackedStringArray = str(args["ko"]).split("@")
		if _t >= float(parts[1]):
			_ko_done = true
			for k in get_tree().get_nodes_in_group("kombez"):
				if k.player_name == parts[0]:
					k.knock_out()
					print("KO_DONE helmets=", get_tree().get_nodes_in_group("helmet").size())

func _in_window(key: String) -> bool:
	if not args.has(key):
		return false
	var ab: PackedStringArray = str(args[key]).split("-")
	return _t >= float(ab[0]) and _t < float(ab[1])

static func _p(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]

func _report() -> void:
	var out := {"steps": _steps, "scene": "", "players": {}, "dummies": [], "helmets": [], "bodies": []}
	var scene := get_tree().current_scene
	if scene != null:
		out["scene"] = scene.scene_file_path
	for k in get_tree().get_nodes_in_group("kombez"):
		var info := {"pos": _p(k.global_position), "ko": k.is_ko(), "helmet": k.has_helmet,
			"hand": _p(k.hand_l.global_position), "color": k.suit_color.to_html(false)}
		if k.peer_id > 0:
			out["players"][k.player_name] = info
		else:
			out["dummies"].append(info)
	for h in get_tree().get_nodes_in_group("helmet"):
		out["helmets"].append(_p(h.global_position))
	if scene != null and "world" in scene:
		var ids: Array = scene.world._nodes.keys()
		ids.sort()
		for id in ids:
			if id < 1000 and not (scene.world._nodes[id] is AnimatableBody3D):
				out["bodies"].append(_p(scene.world._nodes[id].global_position))
	print("PROBE ", JSON.stringify(out))
