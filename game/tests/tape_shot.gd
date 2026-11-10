extends Node
## Кадры для проверки вида изоленты (как visual_check.gd):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --write-movie /tmp/shot/f.png --fixed-fps 60 res://tests/tape_shot.tscn
var room; var k; var cam
func _ready():
	room = load("res://levels/test_room/test_room.tscn").instantiate()
	add_child(room)
	room.controller.kombez = null
	k = room.player; cam = room.camera
	var w = room.world
	await f(30)
	# стол с рулонами
	k.teleport(Vector3(-4.5, 0.9, 7.2))
	cam._arm.spring_length = 2.6; cam.yaw = 0.35; cam.pitch = -0.35
	await f(50); print("SHOT table"); await f(4)
	# рулон в руке, конец прилеплен к ящику, второй кусок уже держит два ящика
	var boxes = room.get_children().filter(func(n): return n is RigidBody3D and n.mass == 14.0)
	k.teleport(Vector3(8.4, 0.9, 6.3))
	boxes[0].global_position = Vector3(8, 0.36, 4.6)
	boxes[1].global_position = Vector3(9.3, 0.36, 4.9)
	w.spawn("tape", {"a": w.id_of(boxes[0]), "la": Vector3(0.2, 0.35, 0.1), "na": Vector3.UP,
		"b": w.id_of(boxes[1]), "lb": Vector3(-0.35, 0.1, 0.0), "nb": Vector3.LEFT, "rest": 0.9})
	k.in_grab_l = true; k.in_aim_pitch = -0.2
	await f(40)
	var roll = get_tree().get_nodes_in_group("tape_roll")[0]
	roll.global_position = k.hand_l.global_position
	await f(20)
	roll.end_on = true; roll.end_id = w.id_of(boxes[0]); roll.end_local = Vector3(-0.1, 0.35, 0.2); roll.end_normal = Vector3.UP
	roll.left = 9.0; roll._refresh()
	cam._arm.spring_length = 3.0; cam.yaw = 0.9; cam.pitch = -0.4
	await f(50); print("SHOT tape"); await f(4)
	get_tree().quit()
func f(n):
	for i in n: await get_tree().physics_frame
