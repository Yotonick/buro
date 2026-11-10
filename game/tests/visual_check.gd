extends Node
## Кадры для проверки внешнего вида (облако, без видеокарты):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --write-movie /tmp/shot/f.png --fixed-fps 60 res://tests/visual_check.tscn
## В журнале строки SHOT отмечают моменты, которые стоит посмотреть.
var room; var k; var cam
func _ready():
	room = load("res://levels/test_room/test_room.tscn").instantiate()
	add_child(room)
	room.controller.kombez = null
	k = room.player; cam = room.camera
	await f(40)
	# 1: спереди, крупно
	cam._arm.spring_length = 2.2; cam.yaw = PI; cam.pitch = -0.1
	await f(30); print("SHOT front")
	await f(4)
	k.laugh(); await f(12); print("SHOT joy"); await f(40)
	cam.yaw = PI * 0.75; k.in_grab_l = true; k.in_grab_r = true; k.in_aim_pitch = 0.3
	await f(30); print("SHOT arms"); await f(4)
	k.in_grab_l = false; k.in_grab_r = false
	cam.yaw = 0.5; cam.pitch = -0.35; cam._arm.spring_length = 3.0
	await f(30); print("SHOT back"); await f(4)
	k.knock_out(3.0); cam.yaw = PI*0.9
	await f(60); print("SHOT ko"); await f(4)
	cam._arm.spring_length = 9.0; cam.yaw = -0.5; cam.pitch = -0.45
	await f(200); print("SHOT room"); await f(4)
	get_tree().quit()
func f(n):
	for i in n: await get_tree().physics_frame
