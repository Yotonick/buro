extends Node
## Кадры для проверки вида «Глубокой тарелки» (как tape_shot.gd):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --write-movie /tmp/shot/f.png --fixed-fps 60 res://tests/plate_shot.tscn
## Номер нужного кадра печатается в строке SHOT.
var lvl; var k; var cam
func _ready():
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	k = lvl.player; cam = lvl.camera
	await f(40)
	cam._arm.spring_length = 4.0; cam.yaw = 0.0; cam.pitch = -0.2
	await f(40); shot("airlock")
	k.teleport(Vector3(0, 1, 6.5))
	cam._arm.spring_length = 7.0; cam.yaw = 0.0; cam.pitch = -0.45
	await f(60); shot("hall")
	var leak = lvl.leaks[1]
	leak.burst()
	var p: Vector3 = leak.global_position
	var n: Vector3 = leak.inward()
	k.teleport(Vector3(p.x, 1.0, p.z) + n * 2.6 + n.cross(Vector3.UP) * 0.8)
	cam._arm.spring_length = 2.5; cam.yaw = atan2(n.x, n.z) + 0.35; cam.pitch = -0.05
	await f(60); shot("leak")
	lvl.flood.level = 0.45
	k.teleport(Vector3(4, 1, 0))
	cam._arm.spring_length = 6.0; cam.yaw = 1.2; cam.pitch = -0.5
	await f(150); shot("water")
	lvl.flood.level = 0.1
	k.teleport(Vector3(0.5, 1, -5.6))
	cam._arm.spring_length = 4.5; cam.yaw = 0.0; cam.pitch = -0.35
	await f(60); shot("pump_broken")
	var probe = load("res://tests/net_probe.gd").new()
	probe._level = lvl
	probe._fix_pump(lvl.pump)
	await f(30)
	await f(90); shot("pump_on")
	get_tree().quit()
func shot(n):
	print("SHOT %s frame=%d" % [n, Engine.get_frames_drawn()])
	await f(2)
func f(n):
	for i in n: await get_tree().physics_frame
