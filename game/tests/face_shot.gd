extends Node
## Крупный план метрдотеля: лица по очереди (кадры для проверки вида):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --write-movie /tmp/shot/f.png --fixed-fps 60 res://tests/face_shot.tscn
var lvl; var cam; var m
func _ready():
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	lvl._next_leak = 99999.0
	lvl.board._next_surge = 99999.0
	cam = lvl.camera; m = lvl.maitre
	lvl.player.teleport(Vector3(6, 1, -3))
	m.set_active(true)
	m.teleport(Vector3(0, 0, 6.5), 0.0)
	var pivot := Node3D.new(); add_child(pivot); pivot.global_position = Vector3(0, 1.2, 6.5)
	cam.target = pivot
	cam._arm.spring_length = 2.4; cam.yaw = PI + 0.35; cam.pitch = 0.0
	for face in ["snob", "disgust", "shock", "wet", "pleased"]:
		m.say(face, face)
		await f(25); print("SHOT %s frame=%d m=%s vis=%s cam=%s" % [face, Engine.get_frames_drawn(), m.global_position, m.is_visible_in_tree(), cam.camera.global_position])
	m.act("knock")
	await f(20); print("SHOT knock frame=%d" % Engine.get_frames_drawn())
	get_tree().quit()
func f(n):
	for i in n: await get_tree().physics_frame
