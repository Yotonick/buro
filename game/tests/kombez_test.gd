extends Node
## Автотест Комбеза на полигоне (без экрана):
##   godot --headless --path game res://tests/kombez_test.tscn
## Печатает PASS/FAIL по каждой проверке и итог.

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

func _upright() -> float:
	return k.global_basis.y.dot(Vector3.UP)

func _reset(pos: Vector3, yaw := 0.0) -> void:
	k.in_move = Vector2.ZERO
	k.in_jump = false
	k.in_grab_l = false
	k.in_grab_r = false
	k.in_aim_yaw = yaw
	k.in_aim_pitch = 0.0
	if k.is_ko():
		await _wait(8.0)
	k.teleport(pos, yaw)
	await _wait(1.0)

func _run() -> void:
	await _wait(2.0)
	_check("стоит ровно", absf(k.global_position.y - 0.78) < 0.06 and _upright() > 0.98 and k.linear_velocity.length() < 0.15,
		"y=%.2f up=%.2f v=%.2f" % [k.global_position.y, _upright(), k.linear_velocity.length()])

	var z0 := k.global_position.z
	k.in_move = Vector2(0, -1)
	await _wait(2.0)
	var dist := z0 - k.global_position.z
	_check("идёт вперёд", dist > 6.5 and dist < 9.0 and _upright() > 0.9, "прошёл %.1f м за 2 с, up=%.2f" % [dist, _upright()])
	k.in_move = Vector2.ZERO
	await _wait(0.6)
	_check("останавливается", k.linear_velocity.length() < 0.3, "v=%.2f" % k.linear_velocity.length())

	k.in_jump = true
	var top := 0.0
	for i in 70:
		await get_tree().physics_frame
		top = maxf(top, k.global_position.y - 0.78)
		if i == 5:
			k.in_jump = false
	await _wait(1.0)
	_check("прыгает", top > 1.1 and top < 2.0 and k.grounded and _upright() > 0.95, "высота %.2f м" % top)

	await _reset(Vector3(-9, 0.9, 3.6))
	k.in_move = Vector2(0, -1)
	await _wait(1.6)
	k.in_move = Vector2.ZERO
	await _wait(0.5)
	_check("поднимается по лестнице", absf(k.global_position.y - (1.44 + 0.78)) < 0.1, "y=%.2f z=%.2f" % [k.global_position.y, k.global_position.z])

	# хват и подъём ящика 14 кг
	await _reset(Vector3(8, 0.9, 5.0))
	var box: RigidBody3D = room.get_children().filter(func(n): return n is RigidBody3D and n.mass == 14.0)[0]
	box.global_position = Vector3(8, 0.36, 4.1)
	box.linear_velocity = Vector3.ZERO
	k.in_aim_pitch = -0.75
	k.in_grab_l = true
	k.in_grab_r = true
	await _wait(1.2)
	var got: bool = k.hand_l.held == box and k.hand_r.held == box
	k.in_aim_pitch = 0.5
	await _wait(1.5)
	_check("хватает и поднимает ящик 14 кг", got and box.global_position.y > 1.0 and _upright() > 0.85,
		"схватил=%s ящик y=%.2f up=%.2f усилие=%.2f" % [got, box.global_position.y, _upright(), k.effort()])
	k.in_grab_l = false
	k.in_grab_r = false
	await _wait(0.5)
	_check("отпускает", k.hand_l.held == null and k.hand_r.held == null)

	# лазание: прыжок к стенке 2 м, зацеп, подтянуться
	await _reset(Vector3(-2.5, 0.9, -6.4))
	k.in_grab_l = true
	k.in_grab_r = true
	k.in_aim_pitch = 0.45
	k.in_move = Vector2(0, -1)
	k.in_jump = true
	await _wait(0.2)
	k.in_jump = false
	await _wait(1.3)
	var hooked: bool = k.hand_l.held != null and k.hand_r.held != null
	k.in_aim_pitch = -1.25
	await _wait(1.2)
	k.in_move = Vector2.ZERO
	k.in_grab_l = false
	k.in_grab_r = false
	await _wait(1.0)
	_check("залезает на стенку 2 м руками", hooked and k.global_position.y > 2.6 and k.grounded, "зацепился=%s y=%.2f" % [hooked, k.global_position.y])

	# спрыгнуть с 2 м — не нокаут
	k.in_move = Vector2(0, -1)
	await _wait(0.7)
	k.in_move = Vector2.ZERO
	await _wait(1.2)
	_check("прыжок с 2 м без нокаута", not k.is_ko() and k.has_helmet and k.global_position.y < 1.0 and _upright() > 0.9, "y=%.2f" % k.global_position.y)

	# нарочное падение и подъём
	await _reset(Vector3(0, 0.9, 7))
	k.flop()
	await _wait(0.3)
	var was_ko := k.is_ko()
	await _wait(5.0)
	_check("падает по F и встаёт сам", was_ko and not k.is_ko() and _upright() > 0.95 and k.has_helmet,
		"нокаут=%s встал=%s up=%.2f" % [was_ko, not k.is_ko(), _upright()])

	# падение с высоты: нокаут, каска слетает, потом встаёт
	await _reset(Vector3(0, 0.9, 7))
	k.teleport(Vector3(0, 8.0, 10))
	await _wait(1.8)
	var ko_fall := k.is_ko()
	var lost := not k.has_helmet and get_tree().get_nodes_in_group("helmet").size() == 1
	await _wait(7.0)
	_check("падение с 7 м: нокаут и каска слетает", ko_fall and lost and not k.is_ko() and _upright() > 0.95,
		"нокаут=%s каска слетела=%s встал=%s" % [ko_fall, lost, not k.is_ko()])
	# надеть каску обратно: подносим к голове
	var helmets := get_tree().get_nodes_in_group("helmet")
	if helmets.size() == 1:
		helmets[0].global_position = k.head_top_global() + Vector3(0, 0.2, 0)
		helmets[0].linear_velocity = Vector3.ZERO
		await _wait(0.5)
	_check("каска надевается обратно", k.has_helmet)

	# карусель сбивает
	await _reset(Vector3(2.6, 0.9, -14))
	var hit := false
	for i in 300:
		await get_tree().physics_frame
		hit = hit or k.is_ko()
	_check("карусель сбивает с ног", hit)

	# стажёр стоит сам и не падает
	var d: Kombez = room.dummies[0]
	_check("стажёр стоит", d.global_basis.y.dot(Vector3.UP) > 0.95 and not d.is_ko(), "y=%.2f" % d.global_position.y)
