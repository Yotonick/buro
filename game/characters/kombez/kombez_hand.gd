extends RigidBody3D
## Рука Комбеза: шарик на пружине. Когда активна — тянется к цели и хватает то,
## чего коснулась (шарнир). Сила руки приложена и к телу (обратная реакция),
## поэтому за зацеп можно подтягиваться, а тяжёлое — тянет вниз.

const KP := 900.0
const KD := 85.0
const F_ACTIVE := 650.0
const F_IDLE := 260.0
const ARM_MAX := 0.95        ## дальше рука «натягивается» как верёвка
const ARM_BREAK := 1.7       ## дальше — хват срывается
const ROPE_K := 9000.0
const ROPE_D := 120.0
const RADIUS := 0.115

var body: RigidBody3D        ## Kombez
var side := 1.0
var active := false
var limp := false
var puppet := false         ## на клиенте: руку двигает сеть
var held: PhysicsBody3D
var effort := 0.0            ## 0..1 — насколько рука напряжена (для лица)
var _joint: PinJoint3D
var _was_active := false

func setup(owner_body: RigidBody3D, s: float) -> void:
	body = owner_body
	side = s
	mass = 2.0
	gravity_scale = 0.0
	can_sleep = false
	lock_rotation = true
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	collision_layer = 8
	collision_mask = 0
	linear_damp = 0.5
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = RADIUS
	cs.shape = sp
	add_child(cs)
	add_collision_exception_with(body)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS + 0.01
	sm.height = (RADIUS + 0.01) * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("e8762c")
	m.roughness = 0.9
	mi.material_override = m
	add_child(mi)
	snap_to_rest()

func snap_to_rest() -> void:
	global_position = body.hand_target(side, false)
	linear_velocity = body.linear_velocity
	reset_physics_interpolation()

func set_puppet(v: bool) -> void:
	puppet = v
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = v
	if v:
		release()
		collision_mask = 0

func set_limp(v: bool) -> void:
	limp = v
	if v:
		release()
		gravity_scale = 1.0
		collision_mask = 1
	else:
		gravity_scale = 0.0
		collision_mask = 0

func release() -> void:
	if _joint != null and is_instance_valid(_joint):
		_joint.queue_free()
	_joint = null
	held = null

func _physics_process(_dt: float) -> void:
	if puppet:
		return
	if held != null and not is_instance_valid(held):
		release()
	var shoulder: Vector3 = body.shoulder_global(side)
	var to_hand := global_position - shoulder
	var dist := to_hand.length()
	effort = 0.0

	# рука не может быть длиннее себя
	if dist > ARM_MAX:
		var n := to_hand / dist
		var rel_v := (linear_velocity - body.linear_velocity).dot(n)
		var pull := n * ((dist - ARM_MAX) * ROPE_K + maxf(rel_v, 0.0) * ROPE_D)
		apply_central_force(-pull)
		body.apply_force(pull, shoulder - body.global_position)
		effort = 1.0
	if dist > ARM_BREAK:
		release()
		if not limp:
			snap_to_rest()
		return
	if limp:
		return

	if active != _was_active:
		_was_active = active
		collision_mask = (1 | 2 | 4 | 16) if active else 0
		if not active:
			release()

	var target: Vector3 = body.hand_target(side, active)
	var f := (target - global_position) * KP - (linear_velocity - body.linear_velocity) * KD
	f = f.limit_length(F_ACTIVE if active else F_IDLE)
	apply_central_force(f)
	if active:
		body.apply_force(-f, shoulder - body.global_position)
		effort = maxf(effort, f.length() / F_ACTIVE if held != null else 0.0)
		if held == null:
			_try_grab()

func _try_grab() -> void:
	for b in get_colliding_bodies():
		var pb := b as PhysicsBody3D
		if pb == null or pb == body or pb.is_in_group("no_grab"):
			continue
		if pb.get_parent() == body:
			continue
		_grab(pb)
		return

func _grab(pb: PhysicsBody3D) -> void:
	held = pb
	_joint = PinJoint3D.new()
	add_child(_joint)
	_joint.global_position = global_position
	_joint.node_a = _joint.get_path_to(self)
	_joint.node_b = _joint.get_path_to(pb)
