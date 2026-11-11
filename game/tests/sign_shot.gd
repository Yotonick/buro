extends Node
## Кадры табличек, экранчиков, всплывающих подсказок, стикеров, имён и пузыря (шаг 2 визуала):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --write-movie /tmp/shot/f.png --fixed-fps 30 res://tests/sign_shot.tscn
## Номер кадра печатается в строке SHOT (файлы сдвинуты — смотри соседние).
var lvl; var k; var cam
const R := 10.0
func _ready():
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	lvl._next_leak = 99999.0
	lvl.board._next_surge = 99999.0
	k = lvl.player; cam = lvl.camera
	await f(20)
	await view(Vector3(0, 1, R + 3.4), Vector3(0, 2.4, R + 0.1), 3.0); shot("airlock_out")
	await view(Vector3(0.6, 1, R + 3.2), Vector3(0, 1.6, R + 5.0), 2.2); shot("airlock_back")
	await view(Vector3(-1.0, 1, R + 3.2), Vector3(-1.2, 0.86, R + 4.3), 2.0); shot("prompt_roll")
	await view(Vector3(1.8, 1, 5.0), Vector3(0, 2.6, 0), 2.5); shot("column")
	await view(Vector3(0.4, 1, 1.4), Vector3(0, 0.85, 0.45), 1.8); shot("column_water")
	var p = lvl.pump
	await view(Vector3(0.5, 1, -5.6), p.wheel.global_position + Vector3.UP * 0.5, 3.0); shot("pump")
	await view(p.wheel.global_position + Vector3(0.3, 0.3, 1.5), p.wheel.global_position, 1.6); shot("prompt_wheel")
	var b = lvl.board
	var bf: Vector3 = b.global_basis.z
	await view(b.panel.global_position + bf * 1.6 + b.global_basis.x * 0.5, b.panel.global_position + Vector3.UP * 0.6, 2.4); shot("board")
	var lk = lvl.leaks[0]
	lk.burst()
	await view(lk.global_position + lk.inward() * 1.6 + Vector3.DOWN * 0.3, lk.global_position, 2.6, 50); shot("leak_tip")
	var m = lvl.maitre
	m.active = true
	m._apply_active()
	m.teleport(Vector3(2.5, 0, 4.5), 0.0)
	await f(5)
	m.say("Это что, изолента?! На моём стекле?! Я вызывал ремонт, а не кружок «умелые руки».", "disgust")
	await view(Vector3(0.5, 1, 7.5), Vector3(2.5, 1.6, 4.5), 3.0, 20); shot("bubble")
	await view(Vector3(0.5, 1, 7.5), Vector3(-6, 1.6, 7.5), 3.0, 20); shot("bubble_off")
	lvl.queue_free()
	await f(5)
	lvl = load("res://levels/test_room/test_room.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	k = lvl.player; cam = lvl.camera
	await f(20)
	var d0 = lvl.dummies[1]
	d0.peer_id = 7; d0.player_name = "Петя"
	await view(Vector3(0, 1, 7), Vector3(0, 2.6, 2.5), 3.5); shot("room_start")
	await view(d0.global_position + Vector3(1.2, 0, 2.2), d0.global_position + Vector3.UP * 0.3, 2.5); shot("room_name_prompt")
	await view(Vector3(-4.5, 1, 6.6), Vector3(-4.5, 1.2, 4.6), 2.5); shot("room_tape")
	await view(Vector3(-5, 1, 1), Vector3(-9, 5.0, -9.6), 2.0); shot("room_tower")
	await view(Vector3(10.0, 1, 4.6), Vector3(11, 0.4, 2.5), 2.0); shot("room_70")
	await view(Vector3(4.5, 1, -1.5), Vector3(6.2, 2.8, -6), 2.0); shot("room_bag")
	await view(Vector3(1.5, 1, -6.0), Vector3(0, 1.2, -10), 2.0); shot("room_carousel")
	get_tree().quit()
## Поставить Комбеза в from и навести взгляд (камеру и «прицел» персонажа) на target.
func view(from: Vector3, target: Vector3, dist: float, wait := 30):
	k.teleport(from)
	await f(4)
	var eye: Vector3 = k.global_position + Vector3.UP * 0.7
	var d: Vector3 = target - eye
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	cam._arm.spring_length = dist; cam.yaw = yaw; cam.pitch = pitch
	k.in_aim_yaw = yaw; k.in_aim_pitch = pitch
	cam.snap()
	await f(wait)
func shot(n):
	print("SHOT %s frame=%d" % [n, Engine.get_frames_drawn()])
	await f(2)
func f(n):
	for i in n: await get_tree().physics_frame
