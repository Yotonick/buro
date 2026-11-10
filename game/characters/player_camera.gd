extends Node3D
## Камера от третьего лица: вращается мышью вокруг персонажа, не проходит сквозь стены.

const SENS := 0.0026
const DISTANCE := 4.4

var target: Node3D
var yaw := 0.0
var pitch := -0.3
var camera: Camera3D
var _arm: SpringArm3D

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_arm = SpringArm3D.new()
	_arm.spring_length = DISTANCE
	_arm.collision_mask = 1
	_arm.margin = 0.2
	var sh := SphereShape3D.new()
	sh.radius = 0.2
	_arm.shape = sh
	add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 200.0
	_arm.add_child(camera)
	camera.make_current()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw = wrapf(yaw - e.relative.x * SENS, -PI, PI)
		pitch = clampf(pitch - e.relative.y * SENS, -1.25, 1.1)

func snap() -> void:
	if target != null:
		global_position = target.global_position + Vector3.UP * 0.7

func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var p := target.get_global_transform_interpolated().origin + Vector3.UP * 0.7
	global_position = global_position.lerp(p, 1.0 - exp(-dt * 16.0))
	rotation = Vector3(pitch, yaw, 0)
