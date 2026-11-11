extends Node
## Помощник сетевых автотестов (включается аргументом --probe, в обычной игре не участвует).
##   --autostart=N       хост начинает смену, когда в лобби N игроков
##   --map=КЛЮЧ          …на этом уровне (по умолчанию полигон)
##   --burst=T           хост на T-й секунде уровня прорывает две течи («Глубокая тарелка»)
##   --surge=T           хост на T-й секунде устраивает скачок в щитке (пробка вылетает, рубильник падает)
##   --pump=T            хост на T-й секунде собирает трубу насоса (ровно, с лентой) и открывает вентиль
##   --lobby=T           хост на T-й секунде уровня возвращает бригаду в лобби
##   --walk=A-B          свой персонаж идёт вперёд с A по B секунду на уровне
##   --grab=A-B          свой персонаж в это время тянет обе руки вперёд-вниз
##   --ko=Имя@T          хост на T-й секунде уровня отправляет игрока в нокаут
##   --use=T             свой персонаж на T-й секунде уровня жмёт «использовать» (E)
##   --tape=T            хост на T-й секунде связывает лентой два ящика по 14 кг
##   --give=Имя          хост кладёт рулон изоленты в левую руку игрока, как только тот её поднимет
##   --bad-link=З,Р,П    плохая связь: задержка З с, разброс Р с, потери П (0..1) для входящих снимков
##   --probe-report=T    на T-й секунде от запуска печатает состояние мира (строка PROBE)
##   --review=T          хост на T-й секунде уровня заканчивает смену — начинается приёмка (метрдотель ускорен)
##   --review-report     печатает PROBE через 1 с после того, как приёмка закончилась

var args := {}
var _level: Node
var _me: Kombez
var _t := 0.0
var _ko_done := false
var _use_done := false
var _tape_done := false
var _give_done := false
var _give_t := 0.0
var _burst_done := false
var _pump_done := false
var _surge_done := false
var _lobby_done := false
var _review_done := false
var _review_rep := -1.0
var _autostarted := false
var _prev := {}      ## имя -> позиция на прошлом тике
var _steps := {}     ## имя -> [тиков в движении, из них рывков] (плавность картинки)

func _ready() -> void:
	if args.has("bad-link"):
		var v: PackedStringArray = str(args["bad-link"]).split(",")
		load("res://net/net_world.gd").sim_bad_link = [float(v[0]), float(v[1]), float(v[2])]
	if args.has("probe-report"):
		get_tree().create_timer(float(args["probe-report"])).timeout.connect(_report)

func _physics_process(dt: float) -> void:
	if args.has("autostart") and not _autostarted and Net.is_host() and Game.current_level == "" \
			and Net.players.size() >= int(args["autostart"]):
		_autostarted = true   # один раз: после возврата в лобби снова не начинаем
		Game.start_match(str(args.get("map", "polygon")))
	var scene := get_tree().current_scene
	if scene == null or not ("world" in scene):
		_level = null
		return
	if scene != _level:
		_level = scene
		_t = 0.0
		_me = null
		_use_done = false
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
		if args.has("use") and not _use_done and _t >= float(args["use"]):
			_use_done = true
			_me.use()
	if Net.is_host():
		_host_tape(dt)
		if args.has("burst") and not _burst_done and _t >= float(args["burst"]) and "leaks" in _level:
			_burst_done = true
			_level.leaks[0].burst()
			_level.leaks[5].burst()
		if args.has("surge") and not _surge_done and _t >= float(args["surge"]) and "board" in _level:
			_surge_done = true
			_level.board.surge()
		if args.has("pump") and not _pump_done and _t >= float(args["pump"]) and "pump" in _level:
			_pump_done = true
			_fix_pump(_level.pump)
		if args.has("review") and not _review_done and _t >= float(args["review"]) and "review" in _level:
			_review_done = true
			_level.maitre.speed = 7.0
			_level.review.pace = 0.25
			_level.shift.time = _level.SHIFT_LEN + 1.0
		if args.has("lobby") and not _lobby_done and _t >= float(args["lobby"]):
			_lobby_done = true
			Game.back_to_lobby()
	if args.has("review-report") and "shift" in _level and _level.shift != null and _level.shift.phase == 1:
		if _review_rep < 0.0:
			_review_rep = _t
		elif _t - _review_rep >= 1.0 and _review_rep < 1e8:
			_review_rep = 1e9
			_report()
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

func _host_tape(dt: float) -> void:
	var w: Node = _level.world
	if args.has("tape") and not _tape_done and _t >= float(args["tape"]):
		_tape_done = true
		var boxes := _level.get_children().filter(func(n): return n is RigidBody3D and n.mass == 14.0)
		w.spawn("tape", {"a": w.id_of(boxes[0]), "la": Vector3(0, 0.35, 0), "na": Vector3.UP,
			"b": w.id_of(boxes[1]), "lb": Vector3(0, 0.35, 0), "nb": Vector3.UP, "rest": 1.7})
	if args.has("give") and not _give_done:
		for k in get_tree().get_nodes_in_group("kombez"):
			if k.player_name != str(args["give"]):
				continue
			_give_t = _give_t + dt if k.hand_l.active else 0.0
			if _give_t > 0.6:
				_give_done = true
				var roll: RigidBody3D = get_tree().get_nodes_in_group("tape_roll")[1]
				roll.global_position = k.hand_l.global_position
				roll.linear_velocity = Vector3.ZERO

func _in_window(key: String) -> bool:
	if not args.has(key):
		return false
	var ab: PackedStringArray = str(args[key]).split("-")
	return _t >= float(ab[0]) and _t < float(ab[1])

static func _p(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]

## Уложить три куска трубы ровно от приямка до насоса, примотать стыки, открыть вентиль (хост).
func _fix_pump(pump: Node3D) -> void:
	var w: Node = _level.world
	var s: Vector3 = pump.end_at(0)[0]
	var e: Vector3 = pump.end_at(1)[0]
	var dir := (e - s).normalized()
	var x := Vector3.UP.cross(-dir).normalized()
	var step: float = pump.PIPE_LEN + 0.0167
	for i in 3:
		var p: RigidBody3D = pump.pieces[i]
		p.global_transform = Transform3D(Basis(x, -dir, x.cross(-dir)), s + dir * (step * i + pump.PIPE_LEN * 0.5))
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
	var pts := [[null, s - dir * 0.2 + Vector3.DOWN * 0.12]]
	for p in pump.pieces:
		pts.append([p, p.global_position - dir * 0.4])
		pts.append([p, p.global_position + dir * 0.4])
	pts.append([null, e + dir * 0.2 + Vector3.DOWN * 0.12])
	for i in range(0, pts.size(), 2):
		var a: Node3D = pts[i][0]
		var b: Node3D = pts[i + 1][0]
		var pa: Vector3 = pts[i][1]
		var pb: Vector3 = pts[i + 1][1]
		w.spawn("tape", {"a": 0 if a == null else w.id_of(a), "la": pa if a == null else a.global_transform.affine_inverse() * pa, "na": Vector3.UP,
			"b": 0 if b == null else w.id_of(b), "lb": pb if b == null else b.global_transform.affine_inverse() * pb, "nb": Vector3.UP,
			"rest": pa.distance_to(pb)})
	pump._acc = pump.VALVE_FULL

func _report() -> void:
	var out := {"steps": _steps, "scene": "", "players": {}, "dummies": [], "helmets": [], "bodies": [], "tapes": [], "rolls": [],
		"leaks": [], "flood": -1.0}
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
	for t in get_tree().get_nodes_in_group("tape"):
		out["tapes"].append([t.a_id, t.b_id, snappedf(t.rest, 0.01)])
	for r in get_tree().get_nodes_in_group("tape_roll"):
		out["rolls"].append([snappedf(r.left, 0.01), r.end_on, r.end_id])
	if scene != null and "world" in scene:
		var ids: Array = scene.world._nodes.keys()
		ids.sort()
		for id in ids:
			if id < 1000 and not (scene.world._nodes[id] is AnimatableBody3D):
				out["bodies"].append(_p(scene.world._nodes[id].global_position))
	for l in get_tree().get_nodes_in_group("leak"):
		out["leaks"].append(l.state)
	for f in get_tree().get_nodes_in_group("flood"):
		out["flood"] = snappedf(f.level, 0.001)
	if _level != null and "board" in _level and _level.board != null:
		var bd: Node3D = _level.board
		out["board"] = [bd.fuse_in, bd.lever_on, bd.short, bd.lit_sectors()]
	if _level != null and "maitre" in _level and _level.maitre != null:
		var m: Node3D = _level.maitre
		out["maitre"] = [m.active, _p(m.global_position), m.mood, m.last_line()]
		out["shift"] = [_level.shift.phase, _level.shift.stars, _level.hud.banner_stars(), _level.hud.banner_text()]
	for pm in get_tree().get_nodes_in_group("pump"):
		out["pump"] = [pm.state, snappedf(pm.valve, 0.05), pm.loose_joints.size()]
	print("PROBE ", JSON.stringify(out))
