extends RigidBody3D
## Слетевшая каска. Обычный предмет: можно схватить, пнуть, надеть на любого Комбеза без каски
## (достаточно поднести к голове).

const KombezVisual := preload("res://characters/kombez/kombez_visual.gd")

var color := Color("f2c230")
var _age := 0.0
var _exceptions_cleared := false

func _ready() -> void:
	add_to_group("helmet")
	mass = 1.5
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	continuous_cd = true
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.36
	sh.height = 0.24
	cs.shape = sh
	cs.position = Vector3(0, 0.1, 0)
	add_child(cs)
	add_child(KombezVisual.build_helmet(color))

func _physics_process(dt: float) -> void:
	_age += dt
	if _age < 1.0:
		return
	if not _exceptions_cleared:
		_exceptions_cleared = true
		for b in get_collision_exceptions():
			remove_collision_exception_with(b)
	if global_position.y < -30.0:
		queue_free()
		return
	for k in get_tree().get_nodes_in_group("kombez"):
		if k.has_helmet or k.is_ko():
			continue
		if global_position.distance_to(k.head_top_global()) < 0.45:
			k.equip_helmet(color)
			queue_free()
			return
