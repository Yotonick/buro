class_name Kombez
extends RigidBody3D
## Комбез — физический персонаж.
## Тело — одно твёрдое тело, которое «мышцы» (пружины) держат над землёй и вертикально.
## Руки — отдельные тела на пружинах, хватают всё, чего коснутся.
## При сильном ударе мышцы отключаются (нокаут), потом Комбез встаёт сам.
##
## Управляется только через поля in_* — их заполняет игрок (PlayerController),
## а позже сеть. Сам персонаж не читает клавиатуру.

signal knocked_out
signal recovered
## «Кукла» (персонаж на клиенте) сама ничего не решает — просит хост.
signal action_requested(action: StringName)

enum State { ACTIVE, KO }

const HandScript := preload("res://characters/kombez/kombez_hand.gd")
const VisualScript := preload("res://characters/kombez/kombez_visual.gd")
const HelmetProp := preload("res://characters/kombez/helmet_prop.gd")

const L_WORLD := 1
const L_PROP := 2
const L_BODY := 4
const L_HAND := 8
const L_NPC := 16              ## клиенты на вызове (метрдотель): толкают Комбеза, но не предметы

# --- настройка ощущений (крутим по отзывам) ---
const BODY_MASS := 40.0
const BODY_INERTIA := 4.0
const RIDE_HEIGHT := 0.78        ## высота центра тела над землёй
const RAY_LENGTH := 1.1
const CROUCH_HEIGHT := 0.54      ## то же вприсядку (Ctrl): руки достают до пола
const CROUCH_SPEED := 0.55       ## вприсядку ходим медленнее (доля от SPEED)
const PICK_AIM := 3.0            ## с такого расстояния E цепляет инструмент на пояс, если смотреть на него
const PICK_NEAR := 1.5           ## …или просто ближайший в таком радиусе
const FLOAT_K := 22000.0         ## жёсткость «ног»
const FLOAT_D := 1300.0
const FLOAT_MAX := 4000.0
const UPRIGHT_K := 1300.0        ## как сильно держит вертикаль
const UPRIGHT_D := 120.0
const SPEED := 4.2
const GROUND_ACCEL := 28.0
const AIR_ACCEL := 7.0
const JUMP_SPEED := 5.6
const TURN_RATE := 10.0
const KO_TIME := 2.4
const HIT_IMPULSE := 90.0        ## удар движущимся предметом
const SLAM_IMPULSE := 300.0      ## сам во что-то влетел
const FALL_KO_SPEED := 9.5

# --- ввод ---
var in_move := Vector2.ZERO      ## желаемое направление в мире (x, z), длина <= 1
var in_jump := false
var in_grab_l := false
var in_grab_r := false
var in_aim_yaw := 0.0
var in_aim_pitch := 0.0
var in_crouch := false

# --- состояние ---
var peer_id := 0                 ## чей это персонаж в сети (0 — ничей: стажёр)
var player_name := ""
var puppet := false              ## true на клиенте: физику считает хост, здесь только картинка
var state := State.ACTIVE
var suit_color := Color("378add")
var helmet_color := Color("f2c230")
var has_helmet := true
var grounded := false
var ground_dist := RIDE_HEIGHT
var air_time := 0.0
var laugh_time := 0.0
var hand_l: RigidBody3D
var hand_r: RigidBody3D
var visual: Node3D
var tool: Node3D                 ## инструмент на поясе (руки свободны); E — пустить в дело, Q — снять

var _face_yaw := 0.0
var _strength := 1.0             ## 0..1 — сила мышц (плавно возвращается после нокаута)
var _ko_timer := 0.0
var _immune := 0.0
var _float_off := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _jump_held := false
var _pending_ko := false
var _ground_vel := Vector3.ZERO
var _ground_body: Object
var _ground_point := Vector3.ZERO
var _prev_vy := 0.0
var _net_velocity := Vector3.ZERO
var _net_effort := 0.0

func _ready() -> void:
	add_to_group("kombez")
	mass = BODY_MASS
	inertia = Vector3.ONE * BODY_INERTIA
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	collision_layer = L_BODY
	collision_mask = L_WORLD | L_PROP | L_BODY | L_NPC
	linear_damp = 0.05
	angular_damp = 0.3
	var mat := PhysicsMaterial.new()
	mat.friction = 0.25
	mat.bounce = 0.05
	physics_material_override = mat

	var belly := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 0.9
	belly.shape = cap
	belly.position = Vector3(0, -0.05, 0)
	add_child(belly)
	var head := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.31
	head.shape = sph
	head.position = Vector3(0, 0.56, 0)
	add_child(head)

	_face_yaw = rotation.y
	in_aim_yaw = _face_yaw

	visual = VisualScript.new()
	visual.name = "Visual"
	add_child(visual)
	visual.setup(self)

	hand_l = _make_hand(-1.0)
	hand_r = _make_hand(1.0)

func _make_hand(side: float) -> RigidBody3D:
	var h: RigidBody3D = HandScript.new()
	h.name = "HandL" if side < 0.0 else "HandR"
	h.top_level = true
	add_child(h)
	h.setup(self, side)
	return h

# ---------- публичное ----------

func shoulder_global(side: float) -> Vector3:
	return global_transform * Vector3(side * 0.34, 0.2, 0.0)

func head_top_global() -> Vector3:
	return global_transform * Vector3(0, 0.84, 0)

## Куда тянется рука: активная — туда, куда смотрит игрок; свободная — висит у бока.
func hand_target(side: float, active: bool) -> Vector3:
	if not active:
		return global_transform * Vector3(side * 0.47, -0.14, -0.04)
	var pitch := clampf(in_aim_pitch * 1.3 + 0.3, -1.35, 1.45)
	var dir := Vector3(-side * 0.14, sin(pitch), -cos(pitch)).normalized()
	return shoulder_global(side) + Basis(Vector3.UP, in_aim_yaw) * dir * 0.78

## Точка на уровне глаз камеры и направление взгляда игрока — туда «целятся» инструменты с пояса.
func aim_origin() -> Vector3:
	return global_position + Vector3.UP * 0.7

func aim_dir() -> Vector3:
	return Basis.from_euler(Vector3(in_aim_pitch, in_aim_yaw, 0.0)) * Vector3.FORWARD

## Где на теле висит инструмент с пояса.
func belt_global() -> Transform3D:
	return global_transform * Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(0.41, -0.2, 0.02))

func ride_height() -> float:
	return CROUCH_HEIGHT if in_crouch else RIDE_HEIGHT

func is_ko() -> bool:
	return state == State.KO

func is_holding() -> bool:
	return hand_l.held != null or hand_r.held != null

func effort() -> float:
	if puppet:
		return _net_effort
	return maxf(hand_l.effort, hand_r.effort)

## Нокаут: мышцы отключаются на duration секунд.
func knock_out(duration := KO_TIME, drop_helmet := true) -> void:
	if puppet:
		return
	if state == State.KO:
		_ko_timer = maxf(_ko_timer, duration)
		return
	state = State.KO
	_ko_timer = duration
	angular_damp = 1.2
	hand_l.set_limp(true)
	hand_r.set_limp(true)
	if drop_helmet and has_helmet:
		_drop_helmet()
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 6.0)
	knocked_out.emit()

## Упасть нарочно (каска остаётся).
func flop() -> void:
	if puppet:
		action_requested.emit(&"flop")
		return
	if state == State.ACTIVE:
		knock_out(1.1, false)
		apply_central_impulse(Basis(Vector3.UP, _face_yaw) * Vector3(0, 0.5, -2.0) * mass)

func laugh() -> void:
	if puppet:
		action_requested.emit(&"laugh")
		return
	if state == State.ACTIVE:
		laugh_time = 1.6

## Пустить в дело то, что в руках (изолента и другие инструменты). Решает хост.
func use() -> void:
	if puppet:
		action_requested.emit(&"use")
		return
	if state != State.ACTIVE:
		return
	if tool != null and not is_instance_valid(tool):
		tool = null
	var used := false
	for h in [hand_l, hand_r]:
		if h.held != null and is_instance_valid(h.held) and h.held.has_method("use_tool"):
			h.held.use_tool(self, h)
			used = true
	if used:
		return
	if tool != null:
		tool.use_tool(self, null)
		return
	var found := _find_tool()
	if found != null:
		found.attach_to(self)

## Снять инструмент с пояса и бросить перед собой (Q).
func drop_tool() -> void:
	if puppet:
		action_requested.emit(&"drop")
		return
	if tool != null and is_instance_valid(tool):
		tool.detach(true)
	tool = null

## Свободный инструмент, на который смотрит игрок, или ближайший рядом.
func _find_tool() -> Node3D:
	var q := PhysicsRayQueryParameters3D.create(aim_origin(), aim_origin() + aim_dir() * PICK_AIM, L_WORLD | L_PROP)
	q.exclude = [get_rid(), hand_l.get_rid(), hand_r.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c: Node3D = hit["collider"]
		if c.is_in_group("tool") and c.holder == null:
			return c
	var best: Node3D = null
	var best_d := PICK_NEAR
	for t in get_tree().get_nodes_in_group("tool"):
		if t.holder != null:
			continue
		var d: float = (t.global_position - (global_position + Vector3.DOWN * 0.3)).length()
		if d < best_d:
			best_d = d
			best = t
	return best

func equip_helmet(color: Color) -> void:
	has_helmet = true
	helmet_color = color
	visual.refresh_helmet()

## Мгновенно перенести (спавн, возврат на полигон).
func teleport(pos: Vector3, yaw := 0.0) -> void:
	hand_l.release()
	hand_r.release()
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_face_yaw = yaw
	hand_l.snap_to_rest()
	hand_r.snap_to_rest()
	reset_physics_interpolation()

# ---------- сеть ----------

## Режим «куклы»: тело и руки не считают физику, их двигает NetWorld по снимкам хоста.
func set_puppet(v: bool) -> void:
	puppet = v
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = v
	hand_l.set_puppet(v)
	hand_r.set_puppet(v)

## Скорость для картинки (у куклы настоящей скорости нет).
func visual_velocity() -> Vector3:
	return _net_velocity if puppet else linear_velocity

## Состояние для снимка: нокаут, на земле, каска, смех, усилие.
func net_flags() -> int:
	return int(state == State.KO) | int(grounded) << 1 | int(has_helmet) << 2 \
		| int(laugh_time > 0.0) << 3 | int(effort() > 0.5) << 4

func apply_net(vel: Vector3, flags: int, gdist: float) -> void:
	_net_velocity = vel
	state = State.KO if flags & 1 else State.ACTIVE
	grounded = flags & 2 != 0
	ground_dist = gdist
	laugh_time = 1.0 if flags & 8 else 0.0
	_net_effort = 1.0 if flags & 16 else 0.0
	var helmet := flags & 4 != 0
	if helmet != has_helmet:
		has_helmet = helmet
		visual.refresh_helmet()

# ---------- физика ----------

func _integrate_forces(s: PhysicsDirectBodyState3D) -> void:
	if puppet or state == State.KO or _immune > 0.0:
		return
	for i in s.get_contact_count():
		var imp := s.get_contact_impulse(i).length()
		if imp < HIT_IMPULSE:
			continue
		var col := s.get_contact_collider_object(i)
		if col == hand_l.held or col == hand_r.held:
			continue
		var other_speed := s.get_contact_collider_velocity_at_position(i).length()
		if imp > SLAM_IMPULSE or other_speed > 2.5:
			_pending_ko = true

func _physics_process(dt: float) -> void:
	if puppet:
		air_time = 0.0 if grounded else air_time + dt
		visual.tick(dt)
		return
	_immune = maxf(_immune - dt, 0.0)
	laugh_time = maxf(laugh_time - dt, 0.0)
	_update_ground()
	if state == State.ACTIVE:
		if _pending_ko:
			_pending_ko = false
			knock_out()
		else:
			_active(dt)
	if state == State.KO:
		_pending_ko = false
		_ko(dt)
	_prev_vy = linear_velocity.y
	hand_l.active = in_grab_l and state == State.ACTIVE
	hand_r.active = in_grab_r and state == State.ACTIVE
	visual.tick(dt)

func _update_ground() -> void:
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_LENGTH,
		L_WORLD | L_PROP | L_BODY)
	q.exclude = [get_rid(), hand_l.get_rid(), hand_r.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_ground_body = null
	_ground_vel = Vector3.ZERO
	if hit.is_empty():
		grounded = false
		ground_dist = RAY_LENGTH
		return
	ground_dist = from.y - (hit["position"] as Vector3).y
	_ground_point = hit["position"]
	_ground_body = hit["collider"]
	var was_grounded := grounded
	grounded = ground_dist < ride_height() + 0.14
	var body := _ground_body as PhysicsBody3D
	if body != null and not (body is StaticBody3D and not body is AnimatableBody3D):
		var rid: RID = hit["rid"]
		var lin: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var ang: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		_ground_vel = lin + ang.cross(_ground_point - body.global_position)
	# жёсткое приземление с высоты
	if grounded and not was_grounded and state == State.ACTIVE and _immune <= 0.0:
		if _prev_vy - _ground_vel.y < -FALL_KO_SPEED:
			_pending_ko = true

func _active(dt: float) -> void:
	_strength = minf(_strength + dt / 0.6, 1.0)
	_float_off = maxf(_float_off - dt, 0.0)
	if grounded:
		_coyote = 0.12
		air_time = 0.0
	else:
		_coyote = maxf(_coyote - dt, 0.0)
		air_time += dt

	# «ноги»: пружина держит тело над землёй
	if ground_dist < RAY_LENGTH and _float_off <= 0.0:
		var rel_vy := linear_velocity.y - _ground_vel.y
		var f := (ride_height() - ground_dist) * FLOAT_K * _strength - rel_vy * FLOAT_D
		f = clampf(f, 0.0, FLOAT_MAX)
		apply_central_force(Vector3.UP * f)
		_push_ground(Vector3.DOWN * f)

	# ходьба
	var move := Vector3(in_move.x, 0, in_move.y).limit_length(1.0)
	var rel := linear_velocity - _ground_vel
	rel.y = 0.0
	var on_feet := grounded and _float_off <= 0.0
	if on_feet or move.length_squared() > 0.01:
		var dv := move * SPEED * (CROUCH_SPEED if in_crouch and on_feet else 1.0) - rel
		var force := (dv / dt * mass).limit_length(mass * (GROUND_ACCEL if on_feet else AIR_ACCEL))
		force *= _strength
		apply_central_force(force)
		if on_feet:
			_push_ground(-force)

	# прыжок
	if in_jump and not _jump_held:
		_jump_buffer = 0.14
	_jump_held = in_jump
	_jump_buffer = maxf(_jump_buffer - dt, 0.0)
	if _jump_buffer > 0.0 and _coyote > 0.0 and _strength > 0.8:
		_jump_buffer = 0.0
		_coyote = 0.0
		_float_off = 0.2
		var dvy := maxf(JUMP_SPEED + _ground_vel.y - linear_velocity.y, 0.0)
		apply_central_impulse(Vector3.UP * dvy * mass)
		var rb := _ground_body as RigidBody3D
		if rb != null:
			rb.apply_impulse(Vector3.DOWN * dvy * mass * 0.5, _ground_point - rb.global_position)

	# куда повернуться: с поднятой рукой — как камера, иначе по ходу движения
	var want_yaw := _face_yaw
	if in_grab_l or in_grab_r:
		want_yaw = in_aim_yaw
	elif move.length_squared() > 0.04:
		want_yaw = atan2(-move.x, -move.z)
	_face_yaw = rotate_toward(_face_yaw, want_yaw, TURN_RATE * dt)

	# держим вертикаль (с лёгким наклоном в сторону разгона)
	var target := Basis(Vector3.UP, _face_yaw)
	var lean := (move * SPEED - rel) / SPEED
	if lean.length_squared() > 0.001 and on_feet:
		var axis := Vector3.UP.cross(lean).normalized()
		target = Basis(axis, minf(lean.length(), 1.0) * 0.16) * target
	var cur := global_basis.orthonormalized()
	var qd := (target * cur.inverse()).get_rotation_quaternion()
	if qd.w < 0.0:
		qd = -qd
	var angle := qd.get_angle()
	if angle > 0.0001:
		apply_torque(qd.get_axis() * angle * UPRIGHT_K * _strength)
	apply_torque(-angular_velocity * UPRIGHT_D * _strength)

func _push_ground(force: Vector3) -> void:
	var rb := _ground_body as RigidBody3D
	if rb != null:
		rb.apply_force(force, _ground_point - rb.global_position)

func _ko(dt: float) -> void:
	_ko_timer -= dt
	air_time = 0.0 if grounded else air_time + dt
	if (_ko_timer <= 0.0 and linear_velocity.length() < 1.5) or _ko_timer < -4.0:
		_recover()

func _recover() -> void:
	state = State.ACTIVE
	_strength = 0.0
	_immune = 1.0
	angular_damp = 0.3
	# встаём лицом туда, куда лежим головой/животом — берём текущий «перёд» по горизонтали
	var fwd := -global_basis.z
	fwd.y = 0.0
	if fwd.length() > 0.2:
		_face_yaw = atan2(-fwd.x, -fwd.z)
	hand_l.set_limp(false)
	hand_r.set_limp(false)
	recovered.emit()

func _drop_helmet() -> void:
	has_helmet = false
	visual.refresh_helmet()
	var xf := Transform3D(global_basis.orthonormalized(), head_top_global() - global_basis.y * 0.08)
	var world := get_tree().get_first_node_in_group("net_world")
	var prop: RigidBody3D
	if world != null:
		prop = world.spawn("helmet", {"color": helmet_color, "xform": xf})
	else:
		prop = HelmetProp.create({"color": helmet_color})
		get_parent().add_child(prop)
		prop.global_transform = xf
	prop.linear_velocity = linear_velocity + Vector3(randf_range(-1.5, 1.5), 3.5, randf_range(-1.5, 1.5))
	prop.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	prop.add_collision_exception_with(self)
	prop.reset_physics_interpolation()
