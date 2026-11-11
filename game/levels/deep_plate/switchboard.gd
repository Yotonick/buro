extends Node3D
## Электрощиток «Глубокой тарелки». От него горит свет в зале: три пробки — три сектора
## (по два стола), рубильник — всё сразу.
##
## Что ломается (решает хост):
##  - Скачки напряжения: сначала мигает свет сектора, потом его пробка вылетает из щитка
##    и улетает в зал, а рубильник падает в «выкл». После первого скачка защёлка рубильника
##    сломана: он сам падает вниз — держи рукой или примотай лентой.
##  - Пробку надо найти и вставить обратно (поднести к пустому гнезду). Пробка плавает;
##    мокрая (была в воде последние секунды) — бьёт током того, кто вставляет, и вылетает.
##  - Щиток стоит низко на тумбе. Вода дошла до розеток — короткое: все пробки вылетают,
##    свет гаснет, а всех, кто стоит в воде, периодически бьёт током. Спасение — поднять
##    тяжёлый щиток (вдвоём) и повесить на крюк повыше (или примотать, поставить на стол — как угодно).
##    Кабель от стены не даёт унести щиток далеко.
##
## Щиток, рубильник и пробки — физические тела, прямые дети уровня (их нумерует NetWorld).
## Клиентам уходят: какие пробки на месте, рубильник, короткое, мигание и вспышки искр.

const Kit := preload("res://levels/level_kit.gd")

const PANEL_SIZE := Vector3(0.7, 0.8, 0.28)
const PANEL_MASS := 60.0       ## тяжёлый: один еле поднимает, вдвоём — нормально
const STAND_H := 0.3
const HOOK_Y := 1.85
const HOOK_R := 0.2            ## ушко ближе этого к крюку — повесили
const HOOK_K := 5000.0
const HOOK_D := 250.0
const HOOK_MAX := 1500.0
const CABLE_LEN := 2.6
const CABLE_K := 3000.0
const CABLE_D := 200.0
const SLOT_R := 0.12           ## пробка ближе этого к пустому гнезду — встаёт на место
const FUSE_LEN := 0.14
const FUSE_R := 0.035
const WET_TIME := 8.0          ## столько секунд пробка мокрая после воды
const LEVER_ON := 0.45         ## рубильник «вкл», если отклонён от верха меньше этого, рад
const LEVER_MAX := 1.75
const LEVER_SPRING := 1.2      ## Н·м — сломанный рубильник падает вниз
const LATCH := 6.0             ## Н·м — целая защёлка держит наверху
const FIRST_SURGE := 40.0
const GAP_START := 42.0
const GAP_END := 24.0
const WARN := 2.2              ## столько мигает свет перед скачком
const SHOCK_EVERY := 2.2       ## при коротком — бьёт током стоящих в воде
const SHOCK_KO := 1.0
const SPARE_ABOVE := 0.15      ## «вода у розеток» — когда до розеток меньше этого

## Местные точки на щитке (центр — середина короба, +Z — лицом в зал).
const EYE := Vector3(0, 0.47, 0)
const CABLE_AT := Vector3(0, 0.3, -0.14)
const CONTACTS := Vector3(0, -0.3, 0.145)
const LEVER_AT := Vector3(0.27, -0.1, 0.17)
const SLOTS := [Vector3(-0.2, 0.17, 0.16), Vector3(0.0, 0.17, 0.16), Vector3(0.2, 0.17, 0.16)]

var panel: RigidBody3D
var lever: RigidBody3D
var fuses: Array[RigidBody3D] = []
var fuse_in: Array = [true, true, true]   ## какая пробка в каком гнезде (гнездо i — пробка i)
var lever_on := true
var short := false
var hooked := false
var latch_ok := true
var warn_sector := -1

var hook_point := Vector3.ZERO
var anchor := Vector3.ZERO

var _world: Node
var _flood: Node3D
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _next_surge := FIRST_SURGE
var _warn_t := 0.0
var _shock_t := 0.0
var _unhook_t := 0.0           ## только что сняли — сразу обратно не цепляется
var _wet_until: Array = [0.0, 0.0, 0.0]
var _cooldown: Array = [0.0, 0.0, 0.0]
var _zap := 0
var _sent := {}
var _label: Label3D
var _lamp_mat: StandardMaterial3D
var _cable: Array[MeshInstance3D] = []
var _sparks: Array[CPUParticles3D] = []
var _spark_i := 0

## Свет, которым управляет щиток (задаёт уровень): по сектору на пробку + общий.
var _sectors: Array = [[], [], []]
var _center: Array = []
var _base := {}                ## свет -> исходная яркость
var _env: Environment
var _env_ambient := 0.7
var _sun: Light3D
var _sun_base := 1.0

## Построить щиток. xf: начало — пол у стекла, +basis.z — в зал, basis.x — вдоль стены.
func build(level: Node3D, xf: Transform3D) -> void:
	level.add_child(self)
	global_transform = xf
	var b := xf.basis
	var o := xf.origin
	var steel := _mat(Color("6f7b80"), 0.45, 0.5)
	var dark := _mat(Color("2b3236"), 0.6, 0.3)

	# стойка у стекла: на ней крюк и ввод кабеля
	var post := Kit.block(level, o + b.z * 0.1 + Vector3.UP * 1.35, Vector3(0.18, 2.7, 0.14), steel)
	post.global_basis = b
	hook_point = o + b.z * 0.32 + Vector3.UP * HOOK_Y
	anchor = o + b.z * 0.2 + Vector3.UP * 2.5
	var hook := MeshInstance3D.new()   # крюк — только картинка: ушко само «садится»
	var hm := TorusMesh.new()
	hm.inner_radius = 0.05
	hm.outer_radius = 0.075
	hm.rings = 16
	hm.ring_segments = 6
	hook.mesh = hm
	hook.material_override = dark
	level.add_child(hook)
	hook.global_transform = Transform3D(b * Basis(Vector3.FORWARD, PI / 2), hook_point + Vector3.UP * 0.05)
	_box_mesh(level, Vector3(0.04, 0.04, 0.16), dark, Transform3D(b, o + b.z * 0.23 + Vector3.UP * HOOK_Y))
	_box_mesh(level, Vector3(0.12, 0.12, 0.08), dark, Transform3D(b, anchor))
	var yaw := atan2(b.z.x, b.z.z)
	Kit.sign(level, o + b.z * 0.2 + Vector3.UP * 2.2, "КРЮК ДЛЯ ЩИТКА ↓", yaw, 30)

	# тумба, на которой стоит щиток (низко — вода доберётся)
	Kit.block(level, o + b.z * 1.0 + Vector3.UP * STAND_H * 0.5, Vector3(0.9, STAND_H, 0.6), _mat(Color("4a5257"), 0.8, 0.1)).global_basis = b

	# сам щиток — тяжёлый короб
	panel = RigidBody3D.new()
	panel.mass = PANEL_MASS
	panel.collision_layer = Kit.L_PROP
	panel.collision_mask = Kit.PROP_MASK
	panel.continuous_cd = true
	panel.angular_damp = 1.5
	panel.add_to_group("switchboard")
	panel.set_meta("half", PANEL_SIZE.y * 0.5)
	panel.set_meta("float", 0.35)   # железный — не всплывает
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	panel.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = PANEL_SIZE
	cs.shape = sh
	panel.add_child(cs)
	_box_mesh(panel, PANEL_SIZE, _mat(Color("c9b84a"), 0.6, 0.3), Transform3D.IDENTITY)
	_box_mesh(panel, Vector3(0.6, 0.28, 0.02), _mat(Color("e9e4cf"), 0.7, 0.0), Transform3D(Basis.IDENTITY, Vector3(0, 0.17, 0.141)))
	# молния на дверце
	var bolt := Kit.sign(panel, Vector3(-0.25, -0.2, 0.145), "⚡", 0.0, 60)
	bolt.modulate = Color("1d1d1d")
	bolt.outline_size = 0
	Kit.sign(panel, Vector3(0, 0.36, 0.145), "ЩИТОК", 0.0, 34)
	_label = Kit.sign(panel, Vector3(0, -0.02, 0.15), "", 0.0, 22)
	# розетки внизу — до них доберётся вода
	for sx in [-0.12, 0.08]:
		_box_mesh(panel, Vector3(0.13, 0.11, 0.02), _mat(Color("f2efe6"), 0.6, 0.0), Transform3D(Basis.IDENTITY, CONTACTS + Vector3(sx, 0, 0)))
	# ушко сверху
	var eye := MeshInstance3D.new()
	var em := TorusMesh.new()
	em.inner_radius = 0.05
	em.outer_radius = 0.075
	em.rings = 16
	em.ring_segments = 6
	eye.mesh = em
	eye.material_override = dark
	eye.rotation = Vector3(PI / 2, 0, 0)
	eye.position = EYE - Vector3.UP * 0.02
	panel.add_child(eye)
	# лампа «есть ток»
	var lamp := MeshInstance3D.new()
	var lsm := SphereMesh.new()
	lsm.radius = 0.035
	lsm.height = 0.07
	lamp.mesh = lsm
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(0.27, 0.36, 0.15)
	panel.add_child(lamp)
	# гнёзда пробок
	for s in SLOTS:
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = FUSE_R
		rm.outer_radius = FUSE_R + 0.018
		rm.rings = 12
		rm.ring_segments = 6
		ring.mesh = rm
		ring.material_override = dark
		ring.rotation = Vector3(PI / 2, 0, 0)
		ring.position = (s as Vector3) + Vector3(0, 0, -0.015)
		panel.add_child(ring)
	level.add_child(panel)
	panel.global_transform = Transform3D(b, o + b.z * 1.0 + Vector3.UP * (STAND_H + PANEL_SIZE.y * 0.5 + 0.01))

	# рубильник — рычаг на шарнире к щитку
	lever = RigidBody3D.new()
	lever.mass = 1.2
	lever.collision_layer = Kit.L_PROP
	lever.collision_mask = 1 | 2 | 8
	lever.angular_damp = 3.0
	lever.add_to_group("breaker")
	var red := _mat(Color("b8322a"), 0.5, 0.2)
	_box_mesh(lever, Vector3(0.04, 0.26, 0.04), steel, Transform3D(Basis.IDENTITY, Vector3(0, 0.13, 0)))
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.05
	km.height = 0.1
	knob.mesh = km
	knob.material_override = red
	knob.position = Vector3(0, 0.28, 0)
	lever.add_child(knob)
	var lcs := CollisionShape3D.new()
	var lsh := BoxShape3D.new()
	lsh.size = Vector3(0.07, 0.32, 0.07)
	lcs.shape = lsh
	lcs.position = Vector3(0, 0.16, 0)
	lever.add_child(lcs)
	level.add_child(lever)
	lever.global_transform = panel.global_transform * Transform3D(Basis.IDENTITY, LEVER_AT)
	lever.add_collision_exception_with(panel)
	var hinge := HingeJoint3D.new()
	level.add_child(hinge)
	hinge.global_transform = panel.global_transform * Transform3D(Basis(Vector3.UP, PI / 2), LEVER_AT)
	hinge.node_a = hinge.get_path_to(panel)
	hinge.node_b = hinge.get_path_to(lever)
	_box_mesh(panel, Vector3(0.1, 0.06, 0.04), dark, Transform3D(Basis.IDENTITY, LEVER_AT - Vector3(0, 0, 0.01)))

	# пробки
	for i in SLOTS.size():
		var f := RigidBody3D.new()
		f.mass = 0.25
		f.collision_layer = Kit.L_PROP
		f.collision_mask = Kit.PROP_MASK
		f.continuous_cd = true
		f.add_to_group("fuse")
		f.set_meta("half", FUSE_R)
		f.set_meta("float", 1.4)
		var fcs := CollisionShape3D.new()
		var fsh := CylinderShape3D.new()
		fsh.radius = FUSE_R
		fsh.height = FUSE_LEN
		fcs.shape = fsh
		f.add_child(fcs)
		f.add_child(_cyl(FUSE_R, FUSE_LEN * 0.7, _mat(Color("efe9dc"), 0.4, 0.0), Vector3.ZERO))
		for s in [-1.0, 1.0]:
			f.add_child(_cyl(FUSE_R * 0.85, FUSE_LEN * 0.15, _mat(Color("c79a3a"), 0.3, 0.8), Vector3(0, s * FUSE_LEN * 0.42, 0)))
		level.add_child(f)
		f.global_transform = _slot_xf(i)
		f.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		f.freeze = true
		f.add_collision_exception_with(panel)
		f.add_collision_exception_with(lever)
		fuses.append(f)

	# кабель от стойки к щитку (провисает)
	var black := _mat(Color("161a1c"), 0.7, 0.0)
	for i in 12:
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 1.0
		cm.radial_segments = 6
		cm.rings = 1
		seg.mesh = cm
		seg.material_override = black
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		level.add_child(seg)
		_cable.append(seg)
	for i in 4:
		var p := CPUParticles3D.new()
		p.amount = 40
		p.lifetime = 0.45
		p.one_shot = true
		p.explosiveness = 0.9
		p.spread = 180.0
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 4.0
		p.gravity = Vector3(0, -6, 0)
		p.mesh = _spark_mesh()
		p.local_coords = false
		p.emitting = false
		level.add_child(p)
		_sparks.append(p)
	_show()

func _ready() -> void:
	add_to_group("tape_hint")
	_world = get_tree().get_first_node_in_group("net_world")
	_rng.seed = Time.get_ticks_usec()

## Какие лампы зажигает щиток: sectors — три массива OmniLight3D (по пробке), center — общий свет.
func set_lights(sectors: Array, center: Array, env: Environment, sun: Light3D = null) -> void:
	_sectors = sectors
	_center = center
	_env = env
	_sun = sun
	_sun_base = sun.light_energy if sun != null else 1.0
	_env_ambient = env.ambient_light_energy if env != null else 0.7
	for arr in sectors + [center]:
		for l in arr:
			_base[l] = (l as Light3D).light_energy

func powered() -> bool:
	return lever_on and not short

## Сколько секторов зала сейчас освещено (0..3).
func lit_sectors() -> int:
	if not powered():
		return 0
	return fuse_in.count(true)

## Где сейчас розетки щитка (по ним меряем воду).
func contacts_y() -> float:
	return (panel.global_transform * CONTACTS).y

func eye_point() -> Vector3:
	return panel.global_transform * EYE

## Отклонение рубильника от верхнего положения, рад (0 — вкл, ~1.7 — выкл).
func lever_angle() -> float:
	var d := lever.global_basis.y
	var pb := panel.global_basis
	return atan2(d.dot(pb.z), d.dot(pb.y))

## Для изоленты: подсветить колечко у рубильника, когда его надо держать.
func wants_tape(p: Vector3) -> bool:
	if latch_ok or panel == null:
		return false
	var tip := lever.global_transform * Vector3(0, 0.26, 0)
	return p.distance_to(tip) < 0.45 or p.distance_to(panel.global_position) < 0.5

func net_state(d: Dictionary) -> void:
	fuse_in = d.get("f", fuse_in)
	lever_on = bool(d.get("on", lever_on))
	short = bool(d.get("sh", short))
	hooked = bool(d.get("hk", hooked))
	latch_ok = bool(d.get("la", latch_ok))
	warn_sector = int(d.get("w", -1))
	var z := int(d.get("z", _zap))
	if z != _zap:
		_zap = z
		for p in d.get("zp", []):
			_spark(p)
	_show()

## Ход щитка во время смены (хост; зовёт уровень, пока идёт работа).
## crew_k — множитель промежутков (вчетвером скачки чаще), progress — доля смены 0..1.
func work(dt: float, crew_k: float, progress: float) -> void:
	if short:
		return
	_next_surge -= dt
	if warn_sector < 0 and _next_surge <= WARN:
		warn_sector = _pick_warn()
		_sync()
	if _next_surge <= 0.0:
		_surge()
		_next_surge = lerpf(GAP_START, GAP_END, clampf(progress, 0.0, 1.0)) * crew_k

## Скачок напряжения: пробка сектора вылетает, рубильник падает (хост).
func surge() -> void:
	_surge()

func _pick_warn() -> int:
	var inn: Array = []
	for i in fuse_in.size():
		if fuse_in[i]:
			inn.append(i)
	return -1 if inn.is_empty() else int(inn[_rng.randi() % inn.size()])

func _surge() -> void:
	var zp: Array = []
	var i := warn_sector if warn_sector >= 0 else _pick_warn()
	warn_sector = -1
	if i >= 0 and fuse_in[i]:
		_pop(i)
		zp.append(panel.global_transform * (SLOTS[i] as Vector3))
	latch_ok = false
	lever.apply_torque_impulse(panel.global_basis.x * 0.6)
	_zap_at(zp)

func _pop(i: int) -> void:
	var f := fuses[i]
	fuse_in[i] = false
	_cooldown[i] = 1.0
	f.freeze = false
	var b := panel.global_basis
	f.linear_velocity = panel.linear_velocity
	f.apply_central_impulse((b.z * 1.0 + b.y * 0.5 + b.x * _rng.randf_range(-0.6, 0.6)) * f.mass * 4.5)
	f.apply_torque_impulse(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.01)

func _slot_xf(i: int) -> Transform3D:
	return panel.global_transform * Transform3D(Basis(Vector3.RIGHT, PI / 2), SLOTS[i])

func _physics_process(dt: float) -> void:
	_t += dt
	if panel == null or _world == null or not _world.is_authority():
		return
	if _flood == null:
		_flood = get_tree().get_first_node_in_group("flood")
	_fuses(dt)
	_lever()
	_hang()
	_tether()
	_water(dt)
	if warn_sector >= 0 and not fuse_in[warn_sector]:
		warn_sector = -1
	lever_on = lever_angle() < LEVER_ON
	_sync()

func _fuses(dt: float) -> void:
	for i in fuses.size():
		var f := fuses[i]
		_cooldown[i] = maxf(_cooldown[i] - dt, 0.0)
		if fuse_in[i]:
			f.global_transform = _slot_xf(i)
			continue
		if _flood != null and _flood.level > 0.01 and _flood.depth_of(f) > 0.0 and Vector2(f.global_position.x, f.global_position.z).length() < _flood.radius:
			_wet_until[i] = _t + WET_TIME
		if _cooldown[i] > 0.0 or short:
			continue
		# пробка подходит в любое пустое гнездо
		for s in SLOTS.size():
			if fuse_in[s]:
				continue
			var at: Vector3 = panel.global_transform * (SLOTS[s] as Vector3)
			if f.global_position.distance_to(at) > SLOT_R:
				continue
			if _t < _wet_until[i]:
				_wet_shock(i, at)
			else:
				_seat(i, s)
			break

## Вставить пробку i в гнездо s. Пробки одинаковые: меняем их местами в списке,
## чтобы «гнездо i — пробка i».
func _seat(i: int, s: int) -> void:
	if i != s:
		var tmp := fuses[s]
		fuses[s] = fuses[i]
		fuses[i] = tmp
		var w = _wet_until[s]
		_wet_until[s] = _wet_until[i]
		_wet_until[i] = w
		var c = _cooldown[s]
		_cooldown[s] = _cooldown[i]
		_cooldown[i] = c
	var f := fuses[s]
	for k in get_tree().get_nodes_in_group("kombez"):
		for h in [k.hand_l, k.hand_r]:
			if h != null and h.held == f:
				h.release()
	f.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	f.freeze = true
	f.global_transform = _slot_xf(s)
	fuse_in[s] = true

## Мокрая пробка: бьёт током того, кто ближе, и выскакивает.
func _wet_shock(i: int, at: Vector3) -> void:
	var f := fuses[i]
	_cooldown[i] = 1.0
	f.apply_central_impulse(panel.global_basis.z * f.mass * 3.0)
	var who := _nearest_kombez(at, 1.6)
	if who != null:
		_shock(who, panel.global_basis.z * 3.0 + Vector3.UP * 1.5, 1.4)
	_zap_at([at])

func _lever() -> void:
	var ang := lever_angle()
	var ax := panel.global_basis.x
	var tq := 0.0
	if latch_ok:
		if ang < 0.5:
			tq = -LATCH * clampf(ang / 0.3, -1.0, 1.0)   # целая защёлка держит наверху
	else:
		tq = LEVER_SPRING
	# упоры: не выше верха и не ниже «выкл»
	if ang < 0.0:
		tq += -ang * 80.0
	elif ang > LEVER_MAX:
		tq -= (ang - LEVER_MAX) * 80.0
	lever.apply_torque(ax * tq)
	panel.apply_torque(-ax * tq)

## Ушко на крюке: держит снизу, снимается, если приподнять или сильно дёрнуть.
func _hang() -> void:
	var e := eye_point()
	var d := hook_point - e
	_unhook_t -= get_physics_process_delta_time()
	if not hooked:
		if d.length() < HOOK_R and _unhook_t <= 0.0:
			hooked = true
		else:
			return
	if -d.y > 0.12 or d.length() > 0.32:
		hooked = false
		_unhook_t = 0.6
		return
	var v := panel.linear_velocity + panel.angular_velocity.cross(e - panel.global_position)
	var f := (d * HOOK_K - v * HOOK_D).limit_length(HOOK_MAX)
	f.y = maxf(f.y, 0.0)   # крюк только держит снизу — вверх снимается свободно
	panel.apply_force(f, e - panel.global_position)

## Кабель не даёт унести щиток дальше своей длины.
func _tether() -> void:
	var at := panel.global_transform * CABLE_AT
	var d := at - anchor
	var len := d.length()
	if len <= CABLE_LEN:
		return
	var n := d / len
	var v := (panel.linear_velocity + panel.angular_velocity.cross(at - panel.global_position)).dot(n)
	var f := -n * minf((len - CABLE_LEN) * CABLE_K + maxf(v, 0.0) * CABLE_D, 2500.0)
	panel.apply_force(f, at - panel.global_position)

## Вода до розеток — короткое; пока короткое — бьёт током всех в воде.
func _water(dt: float) -> void:
	if _flood == null:
		return
	var wet: bool = _flood.level > 0.005 and _flood.floor_y + _flood.level > contacts_y() \
		and Vector2(panel.global_position.x, panel.global_position.z).length() < _flood.radius
	if wet and not short:
		short = true
		latch_ok = false
		var zp: Array = [panel.global_transform * CONTACTS]
		for i in fuse_in.size():
			if fuse_in[i]:
				_pop(i)
				zp.append(panel.global_transform * (SLOTS[i] as Vector3))
		lever.apply_torque_impulse(panel.global_basis.x * 0.6)
		_shock_t = 0.6
		_zap_at(zp)
	elif not wet and short and _flood.floor_y + _flood.level < contacts_y() - 0.05:
		short = false
	if not short:
		return
	_shock_t -= dt
	if _shock_t > 0.0:
		return
	_shock_t = SHOCK_EVERY
	var zp: Array = []
	for k in get_tree().get_nodes_in_group("kombez"):
		var kb := k as Kombez
		if kb == null or kb.puppet or _flood.depth_of(kb) <= 0.0:
			continue
		if Vector2(kb.global_position.x, kb.global_position.z).length() > _flood.radius:
			continue
		_shock(kb, Vector3(_rng.randf_range(-1, 1), 3.0, _rng.randf_range(-1, 1)), SHOCK_KO)
		zp.append(kb.global_position)
	if not zp.is_empty():
		_zap_at(zp)

func _shock(k: Kombez, push: Vector3, ko: float) -> void:
	k.knock_out(ko, false)
	k.apply_central_impulse(push * k.mass * 0.5)

func _nearest_kombez(at: Vector3, r: float) -> Kombez:
	var best: Kombez = null
	var bd := r
	for k in get_tree().get_nodes_in_group("kombez"):
		var d: float = (k as Node3D).global_position.distance_to(at)
		for h in [k.hand_l, k.hand_r]:
			if h != null:
				d = minf(d, (h as Node3D).global_position.distance_to(at))
		if d < bd:
			bd = d
			best = k
	return best

func _zap_at(points: Array) -> void:
	if points.is_empty():
		return
	_zap += 1
	for p in points:
		_spark(p)
	_sync(points)

func _sync(zp: Array = []) -> void:
	var d := {"f": fuse_in.duplicate(), "on": lever_on, "sh": short, "hk": hooked, "la": latch_ok, "w": warn_sector}
	if d == _sent and zp.is_empty():
		return
	_sent = d.duplicate(true)
	_show()
	if _world == null:
		return
	var out := d.duplicate()
	out["z"] = _zap
	out["zp"] = zp
	_world.sync_state(self, out)

func _spark(p: Vector3) -> void:
	if _sparks.is_empty():
		return
	var s := _sparks[_spark_i % _sparks.size()]
	_spark_i += 1
	s.global_position = p
	s.restart()

func _show() -> void:
	if _label == null:
		return
	var lines: Array = []
	if short:
		lines = ["КОРОТКОЕ! вода в щитке", "повесь щиток на крюк повыше"]
	else:
		var missing := fuse_in.count(false)
		lines.append("СВЕТ: %d/3" % lit_sectors())
		if not lever_on:
			lines.append("рубильник ВЫКЛ — подними вверх")
			if not latch_ok:
				lines.append("(сам падает: держи или примотай)")
		if missing > 0:
			lines.append("нет пробок: %d — вставь в гнёзда" % missing)
		if _flood != null and contacts_y() - (_flood.floor_y + _flood.level) < SPARE_ABOVE and _flood.level > 0.01:
			lines.append("вода у розеток!")
	_label.text = "\n".join(lines)
	_lamp_mat.albedo_color = Color("d23a2a") if short else (Color("4fd65a") if powered() else Color("5a2a24"))

func _process(_dt: float) -> void:
	if panel == null:
		return
	if _flood == null:
		_flood = get_tree().get_first_node_in_group("flood")
	_draw_cable()
	_show_lights()
	if Engine.get_process_frames() % 15 == 0:
		_show()

func _show_lights() -> void:
	var on := powered()
	var blink := sin(_t * 31.0) + sin(_t * 17.0) > 0.4   # неровное мигание
	var any := false
	for i in _sectors.size():
		var lit: bool = on and fuse_in[i]
		if lit and i == warn_sector:
			lit = blink
		any = any or (on and fuse_in[i])
		for l in _sectors[i]:
			(l as Light3D).light_energy = _base.get(l, 1.0) if lit else 0.0
	for l in _center:
		(l as Light3D).light_energy = _base.get(l, 1.0) * (1.0 if any else 0.0)
	if _env != null:
		_env.ambient_light_energy = _env_ambient * (1.0 if any else 0.4)
	if _sun != null:
		_sun.light_energy = _sun_base * (1.0 if any else 0.35)

func _draw_cable() -> void:
	var a := anchor
	var b := panel.global_transform * CABLE_AT
	var span := a.distance_to(b)
	var sag := sqrt(maxf(CABLE_LEN * CABLE_LEN - span * span, 0.0)) * 0.45
	var n := _cable.size()
	var prev := a
	for i in n:
		var t := float(i + 1) / n
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var seg := _cable[i]
		var d := p - prev
		var y := d.normalized() if d.length() > 0.001 else Vector3.UP
		var x := (Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).cross(y).normalized()
		seg.global_transform = Transform3D(Basis(x, y * maxf(d.length(), 0.001), x.cross(y)), (p + prev) * 0.5)
		prev = p

static func _box_mesh(parent: Node, size: Vector3, m: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	parent.add_child(mi)
	if parent is PhysicsBody3D:
		mi.transform = xf          # деталь тела — в его координатах
	else:
		mi.global_transform = xf   # украшение уровня — в мировых
	return mi

static func _cyl(r: float, h: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	return mi

static func _spark_mesh() -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.036
	sm.radial_segments = 4
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("fff1a0")
	m.emission_enabled = true
	m.emission = Color("ffd34a")
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	return sm

static func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m
