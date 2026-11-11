extends Node
## Кадры щитка «Глубокой тарелки» (как plate_shot.gd):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --write-movie /tmp/shot/f.png --fixed-fps 60 res://tests/board_shot.tscn
## Номер нужного кадра печатается в строке SHOT (файлы сдвинуты — смотри соседние).
var lvl; var k; var cam; var b
func _ready():
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	lvl._next_leak = 99999.0
	k = lvl.player; cam = lvl.camera; b = lvl.board
	b._next_surge = 99999.0
	var fwd: Vector3 = b.global_basis.z
	k.teleport(b.panel.global_position + fwd * 1.2 + b.global_basis.x * 0.9)
	await f(30)
	look(3.4, -0.2)
	await f(40); shot("board")
	b.warn_sector = 0
	b.surge()
	await f(60); shot("board_surge")
	lvl.flood.level = 0.42
	await f(80); shot("board_short")
	lvl.flood.level = 0.6
	var e_off: Vector3 = b.global_basis * b.EYE
	b.panel.global_transform = Transform3D(b.global_basis, b.hook_point - e_off)
	await f(90); shot("board_hooked")
	k.teleport(Vector3(-2, 1, 2))
	cam._arm.spring_length = 8.0; cam.yaw = 0.9; cam.pitch = -0.45
	await f(60); shot("hall_dark")
	get_tree().quit()
func look(dist, pitch):
	var d: Vector3 = b.panel.global_position - k.global_position
	cam._arm.spring_length = dist; cam.yaw = atan2(-d.x, -d.z) - 0.55; cam.pitch = pitch
func shot(n):
	print("SHOT %s frame=%d" % [n, Engine.get_frames_drawn()])
	await f(2)
func f(n):
	for i in n: await get_tree().physics_frame
