extends Node
## Кадры вида от первого лица в «Глубокой тарелке»: течь, насос, щиток, табличка, взгляд вниз,
## прицел «достаю», вещь в руках, планшет, нокаут, «за спиной» и общий план.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --write-movie /tmp/fp/f.png --fixed-fps 30 res://tests/fp_shot.tscn
## Номер кадра печатается в строке SHOT (файлы сдвинуты — смотри соседние). ~2 мин.
var lvl; var k; var cam
const R := 10.0
func _ready():
	Settings.start_view = "first"
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	lvl._next_leak = 99999.0
	lvl.board._next_surge = 99999.0
	k = lvl.player; cam = lvl.camera
	await f(20)
	var lk = lvl.leaks[0]
	lk.burst()
	await view(lk.global_position + lk.inward() * 1.3 + Vector3.DOWN * 0.4, lk.global_position, 0.0, 50); shot("fp_leak")
	var p = lvl.pump
	await view(Vector3(0.5, 1, -5.6), p.wheel.global_position + Vector3.UP * 0.5, 0.0); shot("fp_pump")
	var b = lvl.board
	var bf: Vector3 = b.global_basis.z
	await view(b.panel.global_position + bf * 1.3 + b.global_basis.x * 0.3, b.panel.global_position + Vector3.UP * 0.2, 0.0); shot("fp_board")
	await view(Vector3(0, 1, R - 3.0), Vector3(0, 2.4, R + 0.1), 0.0); shot("fp_sign")
	await view(Vector3(2, 1, 3), Vector3(2, 0, 2.2), 0.0); shot("fp_down")
	var dish: Node3D = get_tree().get_nodes_in_group("dish")[0]
	var dp: Vector3 = dish.global_position
	var away := Vector3(dp.x, 0, dp.z).normalized()
	await view(Vector3(dp.x, 1, dp.z) + away * 0.95, dp, 0.0); shot("fp_reach")
	k.in_grab_r = true; k.in_grab_l = true
	await f(30)
	k.in_aim_pitch = 0.0; cam.pitch = 0.0
	await f(30); shot("fp_hold")
	k.in_grab_r = false; k.in_grab_l = false
	await f(20)
	await view(Vector3(1.0, 1, 6.5), Vector3(0, 1.2, 0), 0.0)
	lvl.hud.set_tablet(true)
	await f(30); shot("fp_tablet")
	lvl.hud.set_tablet(false)
	await f(20)
	k.knock_out(2.4)
	await f(18); shot("fp_ko")
	await f(200)
	await view(Vector3(1.0, 1, 6.5), Vector3(0, 1.2, 0), 1.6); shot("close_3rd")
	await view(Vector3(1.0, 1, 6.5), Vector3(0, 1.2, 0), 6.5); shot("far_3rd")
	get_tree().quit()
func view(from: Vector3, target: Vector3, dist: float, wait := 30):
	k.teleport(from)
	await f(4)
	var yaw := 0.0; var pitch := 0.0
	for i in 3:
		var d: Vector3 = target - k.aim_origin()
		yaw = atan2(-d.x, -d.z)
		pitch = atan2(d.y, Vector2(d.x, d.z).length())
		k.in_aim_yaw = yaw; k.in_aim_pitch = pitch
	cam.set_zoom(dist, true); cam.yaw = yaw; cam.pitch = pitch
	k.in_face_aim = true
	cam.snap()
	await f(wait)
func shot(n):
	print("SHOT %s frame=%d" % [n, Engine.get_frames_drawn()])
	await f(2)
func f(n):
	for i in n: await get_tree().physics_frame
