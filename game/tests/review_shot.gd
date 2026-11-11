extends Node
## Кадры метрдотеля и итога приёмки (как board_shot.gd):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --write-movie /tmp/shot/f.png --fixed-fps 60 res://tests/review_shot.tscn
## Номер нужного кадра печатается в строке SHOT (файлы сдвинуты — смотри соседние).
var lvl; var k; var cam; var m
func _ready():
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	lvl._next_leak = 99999.0
	lvl.board._next_surge = 99999.0
	k = lvl.player; cam = lvl.camera; m = lvl.maitre
	# 1. выходит из шлюза
	k.teleport(Vector3(1.2, 1, 5.5))
	lvl.shift.time = lvl.SHIFT_LEN + 1.0
	await f(150)
	look_at_m(3.0, -0.12, 0.5)
	await f(20); shot("maitre_enter")
	# 2. лицо крупно, недоволен
	m.teleport(Vector3(0, 0, 6.8)); m.look(Vector3(0, 0, 0))
	lvl.review.running = false
	await f(30)
	k.teleport(Vector3(0.5, 1, 5.2))
	m.say("Здесь стояла еда. Где еда?!", "disgust")
	await f(30)
	look_at_m(2.2, -0.05, 0.25)
	await f(15); shot("maitre_face")
	m.say("Меня окатило! МЕНЯ!", "wet")
	await f(20); shot("maitre_wet")
	# 3. стучит по стеклу у течи
	var l: Node3D = lvl.leaks[0]
	var p: Vector3 = l.global_position * Vector3(1, 0, 1)
	m.teleport(p.normalized() * (lvl.R - 0.85))
	m.look(l.global_position)
	await f(30)
	m.act("knock"); m.say("Держится. Пока.", "snob")
	k.teleport(m.at() - p.normalized() * 2.2 + p.normalized().cross(Vector3.UP) * 1.0)
	await f(25)
	look_at_m(2.6, -0.1, -0.6)
	await f(10); shot("maitre_knock")
	# 4. итог
	lvl.shift.finish(true, "КУПОЛ ДЕРЖИТСЯ", "Метрдотель: «Посредственно. Как и всё в вашей жизни, полагаю.»\nБольше всего не понравилось: вода в зале", 3)
	await f(20); shot("review_stars")
	get_tree().quit()
func look_at_m(dist, pitch, side):
	var d: Vector3 = m.at() - k.global_position
	cam._arm.spring_length = dist; cam.yaw = atan2(-d.x, -d.z) + side; cam.pitch = pitch
func shot(n):
	print("SHOT %s frame=%d" % [n, Engine.get_frames_drawn()])
	await f(2)
func f(n):
	for i in n: await get_tree().physics_frame
