extends Node
## Ввод местного игрока: клавиатура и мышь -> поля in_* персонажа.
## Сеть позже будет заполнять те же поля для чужих персонажей.

var kombez: Kombez
var camera: Node3D   ## player_camera.gd
var enabled := true
## Открыт планшет: мышь свободна, но ходить, прыгать и приседать можно (руки и E — нет).
var walk_only := false

func _physics_process(_dt: float) -> void:
	if kombez == null or not is_instance_valid(kombez):
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var active := enabled and (captured or walk_only)
	if not active:
		kombez.in_move = Vector2.ZERO
		kombez.in_jump = false
		kombez.in_grab_l = false
		kombez.in_grab_r = false
		kombez.in_crouch = false
		return
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3(v.x, 0, v.y).rotated(Vector3.UP, camera.yaw)
	kombez.in_move = Vector2(dir.x, dir.z)
	kombez.in_jump = Input.is_action_pressed("jump")
	kombez.in_crouch = Input.is_action_pressed("crouch")
	kombez.in_aim_yaw = camera.yaw
	kombez.in_aim_pitch = camera.pitch
	if not captured:   # планшет в руках — руки заняты
		kombez.in_grab_l = false
		kombez.in_grab_r = false
		return
	kombez.in_grab_l = Input.is_action_pressed("grab_left")
	kombez.in_grab_r = Input.is_action_pressed("grab_right")
	if Input.is_action_just_pressed("flop"):
		kombez.flop()
	if Input.is_action_just_pressed("laugh"):
		kombez.laugh()
	if Input.is_action_just_pressed("use"):
		kombez.use()
	if Input.is_action_just_pressed("drop_tool"):
		kombez.drop_tool()
