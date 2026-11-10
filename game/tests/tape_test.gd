extends Node
## Автотест изоленты на полигоне (без экрана):
##   godot --headless --path game --fixed-fps 60 --disable-render-loop res://tests/tape_test.tscn

const Kit := preload("res://levels/level_kit.gd")

var room: Node3D
var k: Kombez
var fails := 0

func _ready() -> void:
	room = load("res://levels/test_room/test_room.tscn").instantiate()
	add_child(room)
	room.controller.kombez = null
	k = room.player
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

func _tapes() -> Array:
	return get_tree().get_nodes_in_group("tape").filter(func(t): return not t.is_queued_for_deletion())

func _box(pos: Vector3, mass: float) -> RigidBody3D:
	var b := Kit.prop_box(room, pos, Vector3.ONE * 0.5, mass, Color("c08a4e"))
	room.world.track(b)
	return b

func _run() -> void:
	var w: Node = room.world
	var rolls := get_tree().get_nodes_in_group("tape_roll")
	_check("на полигоне лежат рулоны", rolls.size() == 3, "%d шт." % rolls.size())
	var roll: RigidBody3D = rolls[0]
	var o := Vector3(15, 0, 13)
	k.teleport(o + Vector3(0, 0.9, 0))
	var a := _box(o + Vector3(-0.34, 0.95, -1.25), 4.0)
	var b := _box(o + Vector3(-1.25, 0.95, 0.34), 4.0)
	a.freeze = true   # висят перед руками, пока мотаем
	b.freeze = true
	await _wait(1.0)

	# берём рулон левой рукой
	k.in_grab_l = true
	await _wait(0.6)
	roll.global_position = k.hand_l.global_position
	roll.linear_velocity = Vector3.ZERO
	await _wait(0.4)
	_check("рулон берётся в руку", k.hand_l.held == roll)

	k.use()
	await _wait(0.1)
	_check("первый раз E — конец прилип к ящику", roll.end_on and roll.end_id == w.id_of(a), "к чему: %d (ящик %d)" % [roll.end_id, w.id_of(a)])
	k.use()
	await _wait(0.1)
	_check("второй раз E по тому же ящику — ничего", roll.end_on and _tapes().is_empty())

	k.in_aim_yaw = PI / 2
	await _wait(1.2)
	var left0: float = roll.left
	k.use()
	await _wait(0.1)
	var tapes := _tapes()
	_check("второй ящик — лента натянулась", tapes.size() == 1 and not roll.end_on, "лент: %d" % tapes.size())
	if tapes.size() != 1:
		return
	var tape: Node3D = tapes[0]
	_check("рулон стал короче на длину куска", roll.left < left0 - 0.25 and absf((left0 - roll.left) - maxf(tape.rest, 0.3)) < 0.01,
		"кусок %.2f м, осталось %.1f м" % [tape.rest, roll.left])
	k.in_grab_l = false
	await _wait(0.3)

	# ящики падают на пол связанными; тянем один — второй едет за ним
	a.freeze = false
	b.freeze = false
	await _wait(1.5)
	var b0 := b.global_position
	for i in 120:
		a.apply_central_force(Vector3(-60, 0, -60))
		await get_tree().physics_frame
	await _wait(0.5)
	var pa: Vector3 = a.global_transform * (tape.a_local as Vector3)
	var gap := pa.distance_to(b.global_transform * (tape.b_local as Vector3))
	_check("примотанный ящик тащится следом", is_instance_valid(tape) and b.global_position.distance_to(b0) > 0.5 and gap < tape.rest + 0.3,
		"второй проехал %.2f м, между точками %.2f м (лента %.2f м)" % [b.global_position.distance_to(b0), gap, tape.rest])

	# рвём
	b.freeze = true
	var away := (a.global_position - b.global_position).normalized()
	for i in 60:
		a.apply_central_force(away * 1500.0)
		await get_tree().physics_frame
	b.freeze = false
	await _wait(0.2)
	_check("от сильного рывка лента рвётся", _tapes().is_empty())

	# груз на ленте под потолком (лента к неподвижному миру)
	var c := _box(Vector3(15, 1.5, 8), 14.0)
	var hang: Node3D = w.spawn("tape", {"a": w.id_of(c), "la": Vector3(0, 0.25, 0), "na": Vector3.UP,
		"b": 0, "lb": Vector3(15, 2.4, 8), "nb": Vector3.DOWN, "rest": 0.6})
	await _wait(3.0)
	_check("ящик 14 кг висит на ленте", is_instance_valid(hang) and c.global_position.y > 1.2 and absf(hang.tension - 137.0) < 30.0 and c.linear_velocity.length() < 0.3,
		"y=%.2f натяжение=%.0f Н v=%.2f" % [c.global_position.y, hang.tension if is_instance_valid(hang) else 0.0, c.linear_velocity.length()])
	var heavy := _box(Vector3(15, 2.3, 8), 70.0)
	heavy.global_position = c.global_position + Vector3(0, 0.6, 0)
	await _wait(1.5)
	_check("сверху упало 70 кг — лента не выдержала", _tapes().is_empty(), "y=%.2f" % c.global_position.y)

	# конец отрывается, если ленты не хватает
	roll.left = 1.0
	roll.end_on = true
	roll.end_id = w.id_of(b)
	roll.end_local = Vector3.ZERO
	roll.global_position = b.global_position + Vector3(0, 1.0, 2.0)
	await _wait(0.2)
	_check("отошёл дальше, чем осталось ленты, — конец оторвался", not roll.end_on)

	# --- пояс: рулон берётся с пола без рук, клеит по взгляду ---
	var r2: RigidBody3D = rolls[1]
	var o2 := Vector3(15, 0, 3)
	k.in_grab_l = false
	k.in_aim_yaw = 0.0
	k.in_aim_pitch = 0.0
	k.teleport(o2 + Vector3(0, 0.9, 0))
	r2.global_position = o2 + Vector3(0.3, 0.2, -0.9)
	r2.linear_velocity = Vector3.ZERO
	var d1 := _box(o2 + Vector3(0, 1.3, -2.0), 4.0)
	var d2 := _box(o2 + Vector3(-2.0, 1.3, 0), 4.0)
	d1.freeze = true
	d2.freeze = true
	await _wait(1.0)
	k.use()
	await _wait(0.3)
	_check("E рядом с рулоном на полу — рулон на поясе, руки свободны", k.tool == r2 and r2.holder == k and not k.is_holding()
		and r2.global_position.distance_to(k.global_position) < 0.7)
	k.in_aim_pitch = -0.05
	await _wait(0.1)
	k.use()
	await _wait(0.1)
	_check("E с пояса — конец прилип туда, куда смотришь", r2.end_on and r2.end_id == w.id_of(d1), "к чему: %d (ящик %d)" % [r2.end_id, w.id_of(d1)])
	k.in_aim_yaw = PI / 2
	await _wait(0.1)
	k.use()
	await _wait(0.1)
	_check("второй раз E — лента между двумя ящиками", _tapes().size() == 1 and not r2.end_on, "лент: %d" % _tapes().size())
	k.drop_tool()
	await _wait(1.0)
	_check("Q — рулон снят с пояса и лежит на полу", k.tool == null and r2.holder == null and not r2.freeze and r2.global_position.y < 0.4,
		"y=%.2f" % r2.global_position.y)

	# --- присесть ---
	k.teleport(Vector3(15, 0.9, -3))
	await _wait(1.0)
	var h_stand := k.global_position.y
	k.in_crouch = true
	k.in_aim_pitch = -1.25
	k.in_grab_r = true
	await _wait(1.0)
	_check("Ctrl — присел, рука достаёт до пола", k.global_position.y < h_stand - 0.18 and k.hand_r.global_position.y < 0.2,
		"тело %.2f -> %.2f, рука y=%.2f" % [h_stand, k.global_position.y, k.hand_r.global_position.y])
	k.in_crouch = false
	k.in_grab_r = false
	await _wait(1.0)
	_check("отпустил Ctrl — встал", absf(k.global_position.y - h_stand) < 0.05, "y=%.2f" % k.global_position.y)
