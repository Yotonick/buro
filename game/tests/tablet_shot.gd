extends Node
## Кадры рабочего планшета (шаг 3 визуала): 4 вкладки во время смены, приёмка, полигон.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --write-movie /tmp/tab/f.png --fixed-fps 30 res://tests/tablet_shot.tscn
## Номер кадра печатается в строке SHOT (файлы сдвинуты — смотри соседние). ~2 мин.
var lvl; var k; var cam; var tab
func _ready():
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	lvl._next_leak = 99999.0
	lvl.board._next_surge = 99999.0
	k = lvl.player; cam = lvl.camera; tab = lvl.hud.tablet
	k.player_name = "Ёжик"
	# напарники из ничего — чтобы было кого показать на «Бригаде»
	var mates := []
	for i in 2:
		var m: Kombez = Kombez.new()
		m.peer_id = 20 + i
		m.player_name = ["Толян", "Маринка"][i]
		m.suit_color = [Color("e05a3a"), Color("5ba35a")][i]
		m.position = [Vector3(5, 1, -6), Vector3(-8.2, 1, 0.5)][i]
		lvl.add_child(m)
		lvl._players[m.peer_id] = m
		mates.append(m)
	await f(20)
	lvl.leaks[0].burst(); lvl.leaks[4].burst()
	lvl.shift.time = 96.0
	lvl.flood.level = 0.18
	lvl.board.surge()
	await f(120)
	mates[0].flop()
	await view(Vector3(1.0, 1, 6.5), Vector3(0, 1.2, 0), 3.0)
	lvl.hud.set_tablet(true)
	await f(30); shot("tab_order")
	tab.set_tab(1); await f(12); shot("tab_crew")
	tab.set_tab(2); await f(12); shot("tab_controls")
	tab.set_tab(3); await f(12); shot("tab_notes")
	lvl.hud.set_tablet(false)
	await f(4); shot("tab_closing")
	await f(20)
	# приёмка
	for l in lvl.leaks:
		if l.is_burst(): l.queue_free()
	lvl.leaks = lvl.leaks.filter(func(l): return not l.is_queued_for_deletion())
	lvl.flood.level = 0.0
	lvl.review.pace = 0.3
	lvl.shift.start_review("ПРИЁМКА")
	lvl.review.start()
	for fd in get_tree().get_nodes_in_group("food").slice(0, 3):
		fd.global_position = Vector3(0, -40, 0); fd.freeze = true
	await f(400)
	tab.set_tab(0)
	lvl.hud.set_tablet(true)
	await f(30); shot("tab_review")
	lvl.queue_free()
	await f(5)
	lvl = load("res://levels/test_room/test_room.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	k = lvl.player; cam = lvl.camera; tab = lvl.hud.tablet
	await f(20)
	await view(Vector3(0, 1, 7), Vector3(0, 2.6, 2.5), 3.5)
	lvl.hud.set_tablet(true)
	await f(30); shot("tab_room")
	get_tree().quit()
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
