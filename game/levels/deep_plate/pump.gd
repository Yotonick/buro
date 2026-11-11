extends Node3D
## Насос откачки «Глубокой тарелки». Откачка сломана: магистраль от приямка в полу
## до насоса разорвана на три куска трубы, и они валяются по залу.
##
## Как починить:
##  1. Уложить три куска между патрубком приямка и патрубком насоса — концы к концам.
##  2. Каждый стык примотать изолентой (лента от куска к куску рядом со стыком;
##     у патрубка — от куска к патрубку/полу рядом с ним).
##  3. Открыть вентиль: схватить штурвал рукой и провернуть против часовой стрелки
##     (по часовой — закрыть).
## Ровный плотный стык — сухой. Кривой (щель, угол) — тоже работает, но брызжет
## и насос качает хуже. Работающий насос трясёт трубу — плохо примотанное может разъехаться.
##
## Узел ставится на уровень, куски трубы и штурвал — физические тела, прямые дети уровня
## (их нумерует NetWorld). Решает всё хост; клиентам уходят «качает/нет» и какие стыки брызжут.

const Kit := preload("res://levels/level_kit.gd")

enum St { BROKEN, CLOSED, RUNNING }

const PIPE_LEN := 1.15
const PIPE_R := 0.09
const FLANGE_R := 0.13         ## труба лежит на фланцах: центр на этой высоте
const PIPE_MASS := 12.0
const DRAIN := 0.0095          ## м/с — столько убирает исправный насос (≈ две открытые течи)
const LOOSE_COST := 0.3        ## каждый кривой стык отнимает столько от производительности
const TIGHT_GAP := 0.09
const TIGHT_DOT := -0.94       ## концы смотрят друг на друга (≈20°)
const LOOSE_GAP := 0.28
const LOOSE_DOT := -0.7        ## ≈45°
const TAPE_NEAR := 0.6         ## лента считается за стык, если оба её конца ближе этого к стыку
const VALVE_FULL := TAU * 0.6  ## провернуть штурвал на 0.6 оборота — открыт полностью
const VALVE_OPEN := 0.8        ## насос запускается с этой доли
const CHECK_EVERY := 0.1
const SHAKE := 22.0            ## Н — тряска трубы, пока насос работает

var state := St.BROKEN
var valve := 0.0               ## 0..1 — насколько открыт вентиль (у клиентов — по сети)
var loose_joints: Array = []   ## [[конец, конец], …] — какие стыки брызжут

var pieces: Array[RigidBody3D] = []
var wheel: RigidBody3D
var wheel_axis := Vector3.FORWARD   ## ось штурвала в мире

## Концы магистрали: 0 — патрубок приямка, 1 — патрубок насоса, 2.. — концы кусков.
## Для патрубков: [null, мировая точка, мировое направление «наружу»];
## для кусков: [тело, точка в его координатах, направление в его координатах].
var _ends: Array = []
var _world: Node
var _acc := 0.0                ## на сколько провернули штурвал, рад (хост)
var _check_t := 0.0
var _sent_valve := -1.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _lamp: MeshInstance3D
var _lamp_mat: StandardMaterial3D
var _label: Label3D
var _motor: Node3D
var _motor_rest := Vector3.ZERO
var _bubbles: CPUParticles3D
var _sprays: Array[CPUParticles3D] = []

## Построить насос. level — уровень (сюда же лягут трубы и штурвал), xf — место:
## начало — середина между патрубками на полу, -basis.z смотрит к стеклу (насос у стены),
## +basis.x — от насоса к приямку. pieces_at — где изначально валяются куски (мировые).
func build(level: Node3D, xf: Transform3D, pieces_at: Array) -> void:
	level.add_child(self)
	global_transform = xf
	var right := xf.basis.x
	var back := -xf.basis.z
	var gap := PIPE_LEN * 3.0 + 0.05
	var inlet := xf.origin - right * gap * 0.5 + Vector3.UP * FLANGE_R
	var sump := xf.origin + right * gap * 0.5 + Vector3.UP * FLANGE_R
	_ends = [[null, sump, -right], [null, inlet, right]]

	var metal := _mat(Color("5d6b70"), 0.5, 0.4)
	var rust := _mat(Color("7c5a3c"), 0.8, 0.2)
	var dark := _mat(Color("2b3236"), 0.6, 0.3)

	# корпус насоса — модель Kenney на станине, неподвижный
	var body_c := inlet - right * 0.75 + Vector3.UP * (0.55 - FLANGE_R)
	var pump_body := StaticBody3D.new()
	pump_body.collision_layer = 1
	pump_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.1, 1.1, 1.0)
	cs.shape = bs
	pump_body.add_child(cs)
	level.add_child(pump_body)
	pump_body.global_transform = Transform3D(xf.basis, body_c)
	pump_body.set_meta("prompt", func(_k, d: float) -> Array:
		if d > 2.6:
			return []
		match state:
			St.BROKEN:
				return [["", "насосу нужна целая труба от приямка"]]
			St.CLOSED:
				return [[["grab_left", "grab_right"], "штурвал — против часовой"]]
		return [])
	_motor = Node3D.new()
	pump_body.add_child(_motor)
	var model: Node3D = load("res://assets/factory/machine.glb").instantiate()
	var box := Kit.model_aabb(model)
	var k := 1.1 / maxf(box.size.x, box.size.z)
	model.scale = Vector3.ONE * k
	model.position = -box.get_center() * k
	_motor.add_child(model)
	_motor_rest = _motor.position

	# патрубок насоса (короткая труба из корпуса в сторону приямка)
	_static_pipe(level, inlet - right * 0.25, inlet, metal)
	_flange(level, inlet, right, dark)
	# приямок: решётка в полу и патрубок, торчащий из неё к насосу
	var grate := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.7, 0.02, 0.7)
	grate.mesh = gm
	grate.material_override = dark
	level.add_child(grate)
	grate.global_transform = Transform3D(xf.basis, sump + right * 0.45 + Vector3.DOWN * (FLANGE_R - 0.012))
	_static_pipe(level, sump + right * 0.45 + Vector3.DOWN * FLANGE_R, sump + right * 0.45, rust)
	_static_pipe(level, sump + right * 0.45, sump, rust)
	_flange(level, sump, -right, dark)
	var face_yaw := atan2(xf.basis.z.x, xf.basis.z.z)
	Kit.plaque(level, sump + right * 0.45 + back * 0.45 + Vector3.UP * (0.75 - FLANGE_R), "ПРИЯМОК", face_yaw, 0.1,
		{"style": "signal", "mount": "post", "floor": xf.origin.y})
	# выброс: труба из насоса вверх и сквозь стекло наружу
	var top := body_c + Vector3.UP * 0.55
	var up_to := top + Vector3.UP * 1.3
	_static_pipe(level, top, up_to, metal)
	_static_pipe(level, up_to, up_to + back * 1.4, metal)
	_bubbles = CPUParticles3D.new()
	_bubbles.amount = 40
	_bubbles.lifetime = 2.5
	_bubbles.direction = Vector3.UP
	_bubbles.spread = 25.0
	_bubbles.initial_velocity_min = 0.6
	_bubbles.initial_velocity_max = 1.4
	_bubbles.gravity = Vector3(0, 0.6, 0)
	_bubbles.mesh = _drop_mesh(0.05, Color(0.8, 0.95, 1.0, 0.5))
	_bubbles.local_coords = false
	_bubbles.emitting = false
	level.add_child(_bubbles)
	_bubbles.global_position = up_to + back * 1.5

	# лампа и табличка состояния
	_lamp = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	_lamp.mesh = sm
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp.material_override = _lamp_mat
	level.add_child(_lamp)
	_lamp.global_position = top + Vector3.UP * 0.12 + xf.basis.z * 0.3
	# табло — экранчик на стояке выброса, над ним — табличка
	_label = Kit.screen(level, top + Vector3.UP * 0.5 + xf.basis.z * PIPE_R, 0.86, 0.4, face_yaw, 0.064)
	Kit.plaque(level, top + Vector3.UP * 1.05 + xf.basis.z * PIPE_R, "НАСОС ОТКАЧКИ", face_yaw, 0.12)

	# штурвал вентиля — на лицевой стороне корпуса, физический, крутится на оси
	wheel_axis = xf.basis.z
	var wc := body_c + xf.basis.z * 0.62 + Vector3.UP * 0.3
	wheel = RigidBody3D.new()
	wheel.mass = 3.0
	wheel.collision_layer = 2
	wheel.collision_mask = 1 | 2 | 4 | 8
	wheel.angular_damp = 5.0
	wheel.add_to_group("valve")
	wheel.set_meta("prompt", func(_k, d: float) -> Array:
		if d > 2.2:
			return []
		if state == St.BROKEN:
			return [["", "сначала собери трубу"]]
		return [[["grab_left", "grab_right"], "схвати и крути против часовой" if state == St.CLOSED else "по часовой — закрыть"]])
	var red := _mat(Color("b8322a"), 0.5, 0.2)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.26
	tm.rings = 24
	tm.ring_segments = 8
	rim.mesh = tm
	rim.material_override = red
	rim.rotation = Vector3(PI / 2, 0, 0)
	wheel.add_child(rim)
	for i in 3:
		var spoke := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.46, 0.035, 0.035)
		spoke.mesh = sb
		spoke.material_override = red
		spoke.rotation = Vector3(0, 0, i * PI / 3.0)
		wheel.add_child(spoke)
	var wcs := CollisionShape3D.new()
	var wsh := CylinderShape3D.new()
	wsh.radius = 0.26
	wsh.height = 0.06
	wcs.shape = wsh
	wcs.rotation = Vector3(PI / 2, 0, 0)
	wheel.add_child(wcs)
	level.add_child(wheel)
	wheel.global_transform = Transform3D(xf.basis, wc)
	var hinge := HingeJoint3D.new()
	level.add_child(hinge)
	# ось шарнира — локальная Z узла; у штурвала она смотрит от корпуса в зал
	hinge.global_transform = Transform3D(xf.basis, wc)
	hinge.node_a = hinge.get_path_to(pump_body)
	hinge.node_b = hinge.get_path_to(wheel)
	var axle := MeshInstance3D.new()
	var am := CylinderMesh.new()
	am.top_radius = 0.035
	am.bottom_radius = 0.035
	am.height = 0.14
	axle.mesh = am
	axle.material_override = dark
	level.add_child(axle)
	axle.global_transform = Transform3D(xf.basis * Basis(Vector3.RIGHT, PI / 2), wc - xf.basis.z * 0.06)

	# куски трубы
	for i in 3:
		var p := _make_piece(rust, dark)
		level.add_child(p)
		var at: Transform3D = pieces_at[i] if i < pieces_at.size() else Transform3D(Basis.IDENTITY, xf.origin + Vector3.UP)
		p.global_transform = at
		pieces.append(p)
		_ends.append([p, Vector3(0, PIPE_LEN * 0.5, 0), Vector3.UP])
		_ends.append([p, Vector3(0, -PIPE_LEN * 0.5, 0), Vector3.DOWN])
	for i in 4:
		var s := CPUParticles3D.new()
		s.amount = 50
		s.lifetime = 0.6
		s.direction = Vector3.UP
		s.spread = 35.0
		s.initial_velocity_min = 2.5
		s.initial_velocity_max = 4.0
		s.gravity = Vector3(0, -9.8, 0)
		s.mesh = _drop_mesh(0.025, Color(0.75, 0.9, 1.0, 0.7))
		s.local_coords = false
		s.emitting = false
		level.add_child(s)
		_sprays.append(s)
	_show()

func _ready() -> void:
	add_to_group("pump")
	_world = get_tree().get_first_node_in_group("net_world")
	_rng.seed = 11

## Сколько воды сейчас убирает насос, м/с (хост).
func drain() -> float:
	if state != St.RUNNING:
		return 0.0
	return DRAIN * maxf(1.0 - LOOSE_COST * loose_joints.size(), 0.25)

func running() -> bool:
	return state == St.RUNNING

## Где сейчас конец магистрали: [точка, направление наружу].
func end_at(i: int) -> Array:
	var e: Array = _ends[i]
	var b: Node3D = e[0]
	if b == null:
		return [e[1], e[2]]
	var xf := b.global_transform
	return [xf * (e[1] as Vector3), xf.basis * (e[2] as Vector3)]

func net_state(d: Dictionary) -> void:
	state = int(d.get("s", St.BROKEN)) as St
	valve = float(d.get("v", 0.0))
	loose_joints = d.get("j", [])
	_show()

func _physics_process(dt: float) -> void:
	_t += dt
	if _world == null or not _world.is_authority() or wheel == null:
		return
	# вентиль: копим поворот штурвала вокруг его оси
	# против часовой (если смотреть на штурвал спереди) — открывается
	_acc = clampf(_acc + wheel.angular_velocity.dot(wheel_axis) * dt, 0.0, VALVE_FULL)
	valve = _acc / VALVE_FULL
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = CHECK_EVERY
		_evaluate()
	if state == St.RUNNING:
		for p in pieces:
			if not p.freeze:
				p.apply_central_force(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 1), _rng.randf_range(-1, 1)) * SHAKE)
		for j in loose_joints:
			_spray_push(end_at(j[0])[0])

## Проверить магистраль и вентиль, разослать, если что-то поменялось.
func _evaluate() -> void:
	var path: Variant = _best_path()
	var next := St.BROKEN
	var loose: Array = []
	if path != null:
		loose = path
		next = St.RUNNING if valve >= VALVE_OPEN else St.CLOSED
	var v_step := snappedf(valve, 0.05)
	if next != state or loose != loose_joints or absf(v_step - snappedf(_sent_valve, 0.05)) > 0.001:
		state = next
		loose_joints = loose
		_sent_valve = valve
		_show()
		_world.sync_state(self, {"s": state, "v": v_step, "j": loose_joints})

## Качество стыка двух концов: 0 — нет, 1 — кривой (брызжет), 2 — плотный.
func joint_quality(i: int, j: int) -> int:
	var bi: Node3D = _ends[i][0]
	var bj: Node3D = _ends[j][0]
	if bi == bj:
		return 0   # оба патрубка или два конца одного куска
	var ei := end_at(i)
	var ej := end_at(j)
	var gap := (ei[0] as Vector3).distance_to(ej[0])
	var dot := (ei[1] as Vector3).dot(ej[1])
	var q := 0
	if gap < TIGHT_GAP and dot < TIGHT_DOT:
		q = 2
	elif gap < LOOSE_GAP and dot < LOOSE_DOT:
		q = 1
	if q == 0 or not _taped(bi, bj, ((ei[0] as Vector3) + (ej[0] as Vector3)) * 0.5):
		return 0
	return q

## Есть ли лента между этими телами рядом со стыком (null — патрубок: лента к миру).
func _taped(a: Node3D, b: Node3D, at: Vector3) -> bool:
	var ia: int = 0 if a == null else _world.id_of(a)
	var ib: int = 0 if b == null else _world.id_of(b)
	for t in get_tree().get_nodes_in_group("tape"):
		if t.is_queued_for_deletion():
			continue
		var ta: Vector3 = t.end_point(true)
		var tb: Vector3 = t.end_point(false)
		if ta.distance_to(at) > TAPE_NEAR or tb.distance_to(at) > TAPE_NEAR:
			continue
		if (t.a_id == ia and t.b_id == ib) or (t.a_id == ib and t.b_id == ia):
			return true
	return false

## Магистраль от приямка (0) до насоса (1): список кривых стыков на лучшем пути
## (пустой — все плотные) или null, если трубы от приямка до насоса нет.
func _best_path() -> Variant:
	var n := _ends.size()
	var q := {}
	for i in n:
		for j in range(i + 1, n):
			var v := joint_quality(i, j)
			if v > 0:
				q[Vector2i(i, j)] = v
				q[Vector2i(j, i)] = v
	var best: Array = [null]
	_dfs(0, {0: true}, [], q, best)
	return best[0]

## Обход: из конца cur переходим на другой конец того же куска, оттуда — по стыку.
func _dfs(cur: int, used: Dictionary, loose: Array, q: Dictionary, best: Array) -> void:
	for nxt in _ends.size():
		if used.has(nxt) or not q.has(Vector2i(cur, nxt)):
			continue
		var l2 := loose.duplicate()
		if q[Vector2i(cur, nxt)] == 1:
			l2.append([cur, nxt])
		if nxt == 1:
			if best[0] == null or l2.size() < (best[0] as Array).size():
				best[0] = l2
			continue
		if nxt < 2:
			continue
		var other := nxt + 1 if nxt % 2 == 0 else nxt - 1
		if used.has(other):
			continue
		var u2 := used.duplicate()
		u2[nxt] = true
		u2[other] = true
		_dfs(other, u2, l2, q, best)

## Брызги кривого стыка толкают того, кто рядом.
func _spray_push(at: Vector3) -> void:
	var from := at + Vector3.UP * 0.15
	var dir := (Vector3.UP * 1.0 + Vector3(sin(_t * 3.1), 0, cos(_t * 2.3)) * 0.6).normalized()
	var rq := PhysicsRayQueryParameters3D.create(from, from + dir * 1.6, 2 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(rq)
	if hit.is_empty():
		return
	var rb := hit["collider"] as RigidBody3D
	if rb == null or rb.freeze or pieces.has(rb):
		return
	rb.apply_force(dir * minf(70.0, rb.mass * 25.0), (hit["position"] as Vector3) - rb.global_position)

func _show() -> void:
	if _label == null:
		return
	var real_loose := loose_joints
	match state:
		St.BROKEN:
			_label.text = "ТРУБА РАЗОРВАНА\nуложи 3 куска от приямка, стыки примотай"
			_lamp_mat.albedo_color = Color("d23a2a")
		St.CLOSED:
			_label.text = "ТРУБА СОБРАНА\nвентиль против часовой: %d%%" % int(valve * 100.0)
			_lamp_mat.albedo_color = Color("e8b52a")
		St.RUNNING:
			_label.text = "КАЧАЕТ" + ("" if real_loose.is_empty() else "\nно брызжет: %d стык(а)" % real_loose.size())
			_lamp_mat.albedo_color = Color("4fd65a") if real_loose.is_empty() else Color("b7d64f")
	_bubbles.emitting = state == St.RUNNING

func _process(_dt: float) -> void:
	if _motor == null:
		return
	var on := state == St.RUNNING
	_motor.position = _motor_rest + (Vector3(sin(_t * 61.0), sin(_t * 47.0), cos(_t * 53.0)) * 0.008 if on else Vector3.ZERO)
	var real_loose: Array = loose_joints if on else []
	for i in _sprays.size():
		var s := _sprays[i]
		s.emitting = i < real_loose.size()
		if s.emitting:
			s.global_position = end_at(real_loose[i][0])[0]

func _make_piece(rust: Material, dark: Material) -> RigidBody3D:
	var p := RigidBody3D.new()
	p.mass = PIPE_MASS
	p.collision_layer = 2
	p.collision_mask = 1 | 2 | 4 | 8
	p.continuous_cd = true
	p.add_to_group("pipe")
	p.set_meta("prompt", func(_k, d: float) -> Array:
		if d > 2.2:
			return []
		if state != St.BROKEN:
			return [[["grab_left", "grab_right"], "схватить трубу", true]]
		return [[["grab_left", "grab_right"], "уложи от приямка к насосу"], ["use", "стыки — примотать лентой"]])
	p.set_meta("half", FLANGE_R)
	p.set_meta("float", 0.25)   # чугун: в воде не всплывает
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	p.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = PIPE_R
	sh.height = PIPE_LEN - 0.08
	cs.shape = sh
	p.add_child(cs)
	p.add_child(_cyl_mesh(PIPE_R, PIPE_LEN - 0.04, rust, Vector3.ZERO))
	for s in [-1.0, 1.0]:
		var fcs := CollisionShape3D.new()
		var fsh := CylinderShape3D.new()
		fsh.radius = FLANGE_R
		fsh.height = 0.04
		fcs.shape = fsh
		fcs.position = Vector3(0, s * (PIPE_LEN * 0.5 - 0.02), 0)
		p.add_child(fcs)
		p.add_child(_cyl_mesh(FLANGE_R, 0.04, dark, fcs.position))
	return p

## Неподвижная труба от a до b (твёрдая: к ней можно приматывать).
func _static_pipe(level: Node3D, a: Vector3, b: Vector3, m: Material) -> void:
	var d := b - a
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.add_child(_cyl_mesh(PIPE_R, d.length() + PIPE_R, m, Vector3.ZERO))
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = PIPE_R
	sh.height = d.length()
	cs.shape = sh
	sb.add_child(cs)
	var y := d.normalized()
	var x := (Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).cross(y).normalized()
	level.add_child(sb)
	sb.global_transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)

func _flange(level: Node3D, at: Vector3, out: Vector3, m: Material) -> void:
	var mi := _cyl_mesh(FLANGE_R, 0.04, m, Vector3.ZERO)
	var x := (Vector3.UP if absf(out.y) < 0.95 else Vector3.RIGHT).cross(out).normalized()
	level.add_child(mi)
	mi.global_transform = Transform3D(Basis(x, out, x.cross(out)), at - out * 0.02)

static func _cyl_mesh(r: float, h: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	return mi

static func _drop_mesh(r: float, c: Color) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	return sm

static func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

