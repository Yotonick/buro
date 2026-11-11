extends Node
## Автотест насоса «Глубокой тарелки» (без экрана):
##   godot --headless --path game --fixed-fps 60 --disable-render-loop res://tests/pump_test.tscn

const PumpScript := preload("res://levels/deep_plate/pump.gd")
const St := PumpScript.St

var lvl: Node3D
var k: Kombez
var pump: Node3D
var fails := 0

func _ready() -> void:
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	k = lvl.player
	lvl._next_leak = 99999.0
	pump = lvl.pump
	await _wait(0.5)
	await _run()
	print("RESULT ", "PASS" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit(fails)

func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await get_tree().physics_frame

func _check(name: String, ok: bool, info := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, info])
	if not ok:
		fails += 1

## Уложить кусок i на прямую между патрубками: from — где его ближний к приямку конец.
func _lay(i: int, from: Vector3, dir: Vector3) -> void:
	var p: RigidBody3D = pump.pieces[i]
	var y := -dir   # верхний конец куска (+Y) смотрит к приямку
	var x := Vector3.UP.cross(y).normalized()
	p.global_transform = Transform3D(Basis(x, y, x.cross(y)), from + dir * PumpScript.PIPE_LEN * 0.5)
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO

func _tape_between(a: Node3D, pa: Vector3, b: Node3D, pb: Vector3) -> Node:
	var w: Node = lvl.world
	var ia: int = 0 if a == null else w.id_of(a)
	var ib: int = 0 if b == null else w.id_of(b)
	var la := pa if a == null else a.global_transform.affine_inverse() * pa
	var lb := pb if b == null else b.global_transform.affine_inverse() * pb
	return w.spawn("tape", {"a": ia, "la": la, "na": Vector3.UP, "b": ib, "lb": lb, "nb": Vector3.UP, "rest": pa.distance_to(pb)})

func _run() -> void:
	_check("насос на месте: 3 куска трубы, штурвал", pump.pieces.size() == 3 and pump.wheel != null)
	_check("в начале сломан и не качает", pump.state == St.BROKEN and pump.drain() == 0.0)

	# штурвал крутится только вокруг своей оси
	var ax: Vector3 = pump.wheel_axis
	var side := ax.cross(Vector3.UP).normalized()
	pump.wheel.angular_velocity = side * 4.0
	await _wait(0.1)
	_check("штурвал не качается вбок", absf(pump.wheel.angular_velocity.dot(side)) < 0.5, "%.2f" % pump.wheel.angular_velocity.dot(side))
	var v0: float = pump.valve
	await _spin(6.0, 0.1)
	_check("штурвал крутится по оси — вентиль приоткрылся", pump.valve > v0 + 0.05, "%.2f -> %.2f" % [v0, pump.valve])
	await _spin(-6.0, 0.3)
	pump._acc = 0.0
	await _wait(0.3)

	# уложить трубу ровно: приямок -> 3 куска -> насос
	var s: Array = pump.end_at(0)
	var inl: Array = pump.end_at(1)
	var dir: Vector3 = ((inl[0] as Vector3) - (s[0] as Vector3)).normalized()
	var step := PumpScript.PIPE_LEN + 0.0167
	for i in 3:
		_lay(i, (s[0] as Vector3) + dir * (0.0 + step * i), dir)
	await _wait(0.6)
	_check("уложено без ленты — не считается", pump.state == St.BROKEN)

	var tapes: Array = []
	var p0: RigidBody3D = pump.pieces[0]
	var p1: RigidBody3D = pump.pieces[1]
	var p2: RigidBody3D = pump.pieces[2]
	var off := dir.cross(Vector3.UP) * 0.1
	tapes.append(_tape_between(null, (s[0] as Vector3) - dir * 0.2 + Vector3.DOWN * 0.12, p0, p0.global_position - dir * 0.4 + off))
	tapes.append(_tape_between(p0, p0.global_position + dir * 0.4 + off, p1, p1.global_position - dir * 0.4 + off))
	tapes.append(_tape_between(p1, p1.global_position + dir * 0.4 + off, p2, p2.global_position - dir * 0.4 + off))
	await _wait(0.3)
	_check("три стыка из четырёх примотаны — ещё не собрано", pump.state == St.BROKEN)
	tapes.append(_tape_between(p2, p2.global_position + dir * 0.4 + off, null, (inl[0] as Vector3) + dir * 0.2 + Vector3.DOWN * 0.12))
	await _wait(0.3)
	_check("все стыки примотаны — труба собрана, ждёт вентиль", pump.state == St.CLOSED, "состояние %d" % pump.state)
	_check("ровные стыки — не брызжет", pump.loose_joints.is_empty(), str(pump.loose_joints))

	# открыть вентиль: насос пошёл, вода уходит
	await _spin(6.0, 1.0)
	_check("вентиль открыт — КАЧАЕТ", pump.state == St.RUNNING and pump.valve >= PumpScript.VALVE_OPEN, "вентиль %.2f" % pump.valve)
	lvl.flood.level = 0.3
	await _wait(3.0)
	_check("вода уходит", lvl.flood.level < 0.3 - 0.02, "%.3f" % lvl.flood.level)
	await _wait(5.0)
	_check("насос трясёт трубу, но примотанная держится", pump.state == St.RUNNING and _alive(tapes), "лент живо %d" % tapes.filter(func(t): return is_instance_valid(t)).size())
	var good: float = pump.drain()

	# закрыть вентиль обратно
	await _spin(-6.0, 1.0)
	await _wait(0.2)
	_check("закрутили обратно — стоит", pump.state == St.CLOSED, "вентиль %.2f" % pump.valve)

	# кривой стык: средний кусок повёрнут на 30° — качает, но брызжет и хуже
	await _spin(6.0, 1.0)
	for t in tapes:
		if is_instance_valid(t):
			t.queue_free()
	await _wait(0.1)
	tapes.clear()
	for i in 3:
		_lay(i, (s[0] as Vector3) + dir * (step * i), dir)
	var bent := Basis(Vector3.UP, 0.3) * p1.global_basis
	p1.global_transform = Transform3D(bent, p1.global_position)
	await _wait(0.1)
	tapes.append(_tape_between(null, (s[0] as Vector3) - dir * 0.2 + Vector3.DOWN * 0.12, p0, p0.global_position - dir * 0.4 + off))
	tapes.append(_tape_between(p0, p0.global_position + dir * 0.4 + off, p1, p1.global_position + (p1.global_basis.y * 0.4)))
	tapes.append(_tape_between(p1, p1.global_position - (p1.global_basis.y * 0.4), p2, p2.global_position - dir * 0.4 + off))
	tapes.append(_tape_between(p2, p2.global_position + dir * 0.4 + off, null, (inl[0] as Vector3) + dir * 0.2 + Vector3.DOWN * 0.12))
	await _wait(0.4)
	_check("кривая сборка тоже качает", pump.state == St.RUNNING, "состояние %d, стыки %s" % [pump.state, str(pump.loose_joints)])
	_check("…но брызжет и качает хуже", pump.loose_joints.size() >= 1 and pump.drain() < good, "кривых %d, %.4f < %.4f" % [pump.loose_joints.size(), pump.drain(), good])

	# порвали ленту на стыке — насос встал
	for t in tapes:
		if is_instance_valid(t):
			t.queue_free()
			break
	await _wait(0.3)
	_check("порвали ленту — магистраль разорвана, насос встал", pump.state == St.BROKEN and pump.drain() == 0.0)

	# живой игрок крутит штурвал рукой
	pump._acc = 0.0
	var wc: Vector3 = pump.wheel.global_position
	k.teleport(Vector3(wc.x, 0.9, wc.z) + ax * 0.6 - side * 0.2, atan2(ax.x, ax.z))
	await _wait(0.8)
	_aim_at(wc + side * 0.23)
	await _wait(0.2)
	k.in_grab_r = true
	await _wait(0.6)
	var held: bool = k.hand_r.held == pump.wheel
	# схватил за обод снизу — ведём руку вправо: против часовой
	var yaw0 := k.in_aim_yaw
	for i in 60:
		k.in_aim_yaw = yaw0 - i * 0.02
		await get_tree().physics_frame
	await _wait(0.3)
	k.in_grab_r = false
	await _wait(0.3)
	_check("игрок схватил штурвал рукой и провернул", held and pump.valve > 0.1, "схватил %s, вентиль %.2f" % [held, pump.valve])

## Крутить штурвал «рукой бога» sec секунд со скоростью w рад/с.
func _spin(w: float, sec: float) -> void:
	for i in int(sec * 60.0):
		pump.wheel.angular_velocity = pump.wheel_axis * w
		await get_tree().physics_frame

func _alive(ts: Array) -> bool:
	return ts.all(func(t): return is_instance_valid(t) and not t.is_queued_for_deletion())

func _aim_at(p: Vector3) -> void:
	var d := (p - k.aim_origin()).normalized()
	k.in_aim_yaw = atan2(-d.x, -d.z)
	k.in_aim_pitch = asin(clampf(d.y, -1.0, 1.0))
