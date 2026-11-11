extends AnimatableBody3D
## Клиент на вызове (пока — метрдотель «Глубокой тарелки»): ходит по залу, смотрит,
## стучит по починкам и ворчит. Неуязвим и непреклонен: кинематическое тело,
## ремонтников расталкивает, предметы проходят сквозь (чтобы не ломал трубы и щиток),
## но попадание брошенным он чувствует (сигнал hit). Схватить рукой и примотать лентой — можно.
##
## Ходит только хост (go / look / say / act), у клиентов тело двигают снимки NetWorld,
## а лицо, реплики и жесты приходят через sync_state. Уровень должен создать узел
## прямым ребёнком при постройке — тогда его пронумерует track_tree.
## Начало узла — между ступнями, вперёд — -Z.

signal hit(body: PhysicsBody3D, speed: float)

const HEAD_SHADER := preload("res://characters/kombez/head.gdshader")
const FACES := {
	"snob": preload("res://characters/client/face/snob.svg"),
	"blink": preload("res://characters/client/face/blink.svg"),
	"disgust": preload("res://characters/client/face/disgust.svg"),
	"shock": preload("res://characters/client/face/shock.svg"),
	"wet": preload("res://characters/client/face/wet.svg"),
	"pleased": preload("res://characters/client/face/pleased.svg"),
}
const L_NPC := 16              ## свой слой: в маске Комбеза и рук, но не предметов
const SPEED := 1.6             ## м/с, обычный шаг
const TURN := 5.0              ## рад/с
const HIP_Y := 0.95
const HEAD_Y := 1.84
const HEAD_R := 0.2
const SAY_TIME := 3.6
const HIT_SPEED := 3.5         ## быстрее этого прилетело — «в меня кинули»

var mood := "snob"             ## лицо: snob / disgust / shock / wet / pleased
var speed := SPEED             ## можно ускорить (тесты)
var active := false            ## вышел в зал (до этого спрятан и ни с чем не сталкивается)

var _world: Node
var _pos := Vector3.ZERO       ## где стоит (хост); прямое присваивание позиции такому телу откатывается — только teleport()
var _path: Array[Vector3] = []
var _look := Vector3.ZERO      ## куда повернуться, когда стоит (0 — как стоит)
var _yaw := 0.0
var _say_n := 0
var _say_text := ""
var _act := ""
var _act_n := 0
var _sent := {}

# картинка
var _vis: Node3D
var _head_mat: ShaderMaterial
var _legs: Array[Node3D] = []
var _arm_r: Node3D
var _label: Label3D
var _face := ""
var _blink_in := 2.0
var _blink_left := 0.0
var _say_left := 0.0
var _act_t := 99.0
var _act_seen := 0
var _step := 0.0
var _speed := 0.0
var _last_pos := Vector3.ZERO
var _wobble := 0.0
var _cool := {}                ## тело -> когда снова можно считать попадание

static func create(level: Node3D, at: Vector3, yaw: float) -> AnimatableBody3D:
	var n: AnimatableBody3D = load("res://characters/client/client_npc.gd").new()
	n.position = at
	n.rotation.y = yaw
	level.add_child(n)
	n.teleport(at, yaw)
	return n

func _init() -> void:
	sync_to_physics = true
	collision_layer = 0
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.95
	cs.shape = cap
	cs.position = Vector3(0, 0.98, 0)
	add_child(cs)
	_build_visual()
	var area := Area3D.new()   # чем в него попали
	area.collision_layer = 0
	area.collision_mask = 2 | 4
	var acs := CollisionShape3D.new()
	var acap := CapsuleShape3D.new()
	acap.radius = 0.36
	acap.height = 2.05
	acs.shape = acap
	acs.position = Vector3(0, 1.0, 0)
	area.add_child(acs)
	area.body_entered.connect(_on_body_entered)
	add_child(area)

func _ready() -> void:
	_world = get_tree().get_first_node_in_group("net_world")
	_last_pos = global_position
	_apply_active()

# ---------- команды (только хост) ----------

## Переставить мгновенно (стоя, лицом по yaw).
func teleport(at: Vector3, yaw := NAN) -> void:
	_pos = at
	if not is_nan(yaw):
		_yaw = yaw
	_path.clear()
	_look = Vector3.ZERO
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)
	reset_physics_interpolation()

## Выйти в зал / спрятаться.
func set_active(v: bool) -> void:
	active = v
	_apply_active()
	_sync()

## Пойти по точкам (на уровне пола).
func go(points: Array) -> void:
	_path.clear()
	for p in points:
		_path.append(Vector3(p.x, _pos.y, p.z))

func walking() -> bool:
	return not _path.is_empty()

## Где он сейчас (хост — точно, без отката).
func at() -> Vector3:
	return _pos if _world == null or _world.is_authority() else global_position

## Повернуться лицом к точке, когда стоит.
func look(p: Vector3) -> void:
	_look = p

## Сказать реплику (пузырь над головой у всех) и сменить лицо.
func say(text: String, face := "") -> void:
	if face != "":
		mood = face
	_say_text = text
	_say_n += 1
	_sync()

func set_mood(face: String) -> void:
	mood = face
	_sync()

## Жест: "knock" — постучать по стеклу.
func act(what: String) -> void:
	_act = what
	_act_n += 1
	_sync()

func last_line() -> String:
	return _say_text

func net_state(d: Dictionary) -> void:
	active = bool(d.get("on", active))
	mood = str(d.get("m", mood))
	var n := int(d.get("n", _say_n))
	if n != _say_n:
		_say_n = n
		_say_text = str(d.get("s", ""))
		_show_say()
	_act = str(d.get("a", ""))
	_act_n = int(d.get("an", _act_n))
	_apply_active()

func _sync() -> void:
	_show_say_if_new()
	if _world == null:
		return
	var d := {"on": active, "m": mood, "s": _say_text, "n": _say_n, "a": _act, "an": _act_n}
	if d == _sent:
		return
	_sent = d
	_world.sync_state(self, d)

var _shown_say := 0

func _show_say_if_new() -> void:
	if _shown_say != _say_n:
		_show_say()

func _show_say() -> void:
	_shown_say = _say_n
	_label.text = _say_text
	_say_left = SAY_TIME if _say_text != "" else 0.0
	var lvl := get_parent()
	if _say_text != "" and lvl != null and "hud" in lvl and lvl.hud != null and lvl.hud.has_method("show_line"):
		lvl.hud.show_line("Метрдотель: «%s»" % _say_text, SAY_TIME)

func _apply_active() -> void:
	visible = active
	collision_layer = L_NPC if active else 0

# ---------- ход ----------

func _physics_process(dt: float) -> void:
	var p := global_position
	_speed = lerpf(_speed, Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length() / maxf(dt, 0.001), 0.3)
	_last_pos = p
	if _world == null or not _world.is_authority():
		return
	p = _pos
	var want := _yaw
	if not _path.is_empty():
		var to := _path[0] - p
		to.y = 0.0
		var d := to.length()
		var stepd := speed * dt
		if d <= stepd:
			p = Vector3(_path[0].x, p.y, _path[0].z)
			_path.remove_at(0)
		else:
			p += to / d * stepd
		if d > 0.05:
			want = atan2(-to.x, -to.z)
	elif _look != Vector3.ZERO:
		var to := _look - p
		if Vector2(to.x, to.z).length() > 0.1:
			want = atan2(-to.x, -to.z)
	_yaw = rotate_toward(_yaw, want, TURN * dt)
	_pos = p
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), p)

func _on_body_entered(b: Node3D) -> void:
	if not active or _world == null or not _world.is_authority():
		return
	var rb := b as RigidBody3D
	if rb == null or rb.freeze:
		return
	# считается только то, что само летит в него, а не то, на что он наткнулся или что растолкал
	var to_me := _pos + Vector3.UP * 1.0 - rb.global_position
	var v := rb.linear_velocity.dot(to_me.normalized())
	var lim := HIT_SPEED * (2.0 if rb is Kombez else 1.0)
	var now := Time.get_ticks_msec()
	if v < lim or int(_cool.get(rb, 0)) > now:
		return
	_cool[rb] = now + 1200
	hit.emit(rb, v)

# ---------- картинка ----------

func _process(dt: float) -> void:
	if not visible:
		return
	# лицо и моргание
	_blink_in -= dt
	if _blink_in <= 0.0:
		_blink_in = randf_range(2.0, 5.0)
		_blink_left = 0.13
	_blink_left -= dt
	var f := mood
	if _blink_left > 0.0 and (mood == "snob" or mood == "disgust"):
		f = "blink"
	_set_face(f)
	# реплика
	_say_left -= dt
	_label.visible = _say_left > 0.0
	# ноги: шаг по скорости
	var moving := clampf(_speed / SPEED, 0.0, 1.0)
	_step += dt * _speed * 4.2
	for i in 2:
		var s := sin(_step + i * PI) * 0.5 * moving
		_legs[i].rotation.x = s
	_vis.position.y = absf(sin(_step)) * 0.03 * moving
	# жесты
	if _act_n != _act_seen:
		_act_seen = _act_n
		_act_t = 0.0
		if _act == "wobble":
			_wobble = 1.0
	_act_t += dt
	var arm := Vector3(0.45, 0, -0.2)   # покой: рука с салфеткой у живота
	if _act == "knock" and _act_t < 1.3:
		var tap := absf(sin(_act_t * TAU * 2.3)) * 0.25
		arm = Vector3(1.45 - tap, 0, -0.05)   # вытянул вперёд и стучит
	elif _say_left > SAY_TIME - 1.0:
		arm = Vector3(0.9 + sin(_say_left * 9.0) * 0.2, 0, 0.3)   # жестикулирует
	_arm_r.rotation = _arm_r.rotation.lerp(arm, minf(dt * 10.0, 1.0))
	# от попадания — качнулся
	_wobble = move_toward(_wobble, 0.0, dt * 1.5)
	_vis.rotation.z = sin(_wobble * 30.0) * _wobble * 0.25
	if mood == "wet" or mood == "shock":
		_vis.rotation.x = -0.06
	else:
		_vis.rotation.x = 0.04   # нос кверху

func _set_face(f: String) -> void:
	if f == _face or not FACES.has(f):
		return
	_face = f
	_head_mat.set_shader_parameter("face", FACES[f])

func _build_visual() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	var black := _mat(Color("1d1d24"), 0.45)
	var white := _mat(Color("f3f1ea"), 0.7)
	var red := _mat(Color("b32630"), 0.5)
	var shoe := _mat(Color("101014"), 0.15)
	# ноги (поворачиваются от бедра)
	for s in [-1.0, 1.0]:
		var hip := MeshInstance3D.new()
		var holder := Node3D.new()
		holder.position = Vector3(s * 0.1, HIP_Y, 0)
		_vis.add_child(holder)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.075
		cm.bottom_radius = 0.06
		cm.height = HIP_Y - 0.04
		hip.mesh = cm
		hip.material_override = black
		hip.position = Vector3(0, -(HIP_Y - 0.04) / 2.0, 0)
		holder.add_child(hip)
		var foot := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.11, 0.07, 0.26)
		foot.mesh = fm
		foot.material_override = shoe
		foot.position = Vector3(0, -HIP_Y + 0.04, -0.06)
		holder.add_child(foot)
		_legs.append(holder)
	# туловище — фрак
	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.23
	tm.height = 0.95
	torso.mesh = tm
	torso.material_override = black
	torso.position = Vector3(0, 1.32, 0)
	torso.scale = Vector3(1.0, 1.0, 0.8)
	_vis.add_child(torso)
	var tails := MeshInstance3D.new()   # фалды
	var tbm := BoxMesh.new()
	tbm.size = Vector3(0.34, 0.5, 0.04)
	tails.mesh = tbm
	tails.material_override = black
	tails.position = Vector3(0, 0.92, 0.17)
	tails.rotation.x = 0.18
	_vis.add_child(tails)
	var shirt := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.17, 0.42, 0.04)
	shirt.mesh = sm
	shirt.material_override = white
	shirt.position = Vector3(0, 1.47, -0.175)
	shirt.rotation.x = 0.1
	_vis.add_child(shirt)
	for s in [-1.0, 1.0]:   # бабочка
		var bow := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.1, 0.09, 0.04)
		bow.mesh = pm
		bow.material_override = red
		bow.position = Vector3(s * 0.05, 1.67, -0.2)
		bow.rotation.z = s * PI / 2
		_vis.add_child(bow)
	# левая рука — за спиной
	var arm_l := _cyl(0.06, 0.62, black)
	arm_l.position = Vector3(-0.27, 1.38, 0.1)
	arm_l.rotation = Vector3(0.5, 0, 0.25)
	_vis.add_child(arm_l)
	# правая рука — с салфеткой, двигается
	_arm_r = Node3D.new()
	_arm_r.position = Vector3(0.27, 1.62, 0)
	_vis.add_child(_arm_r)
	var arm := _cyl(0.06, 0.62, black)
	arm.position = Vector3(0, -0.31, 0)
	_arm_r.add_child(arm)
	var glove := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.065
	gm.height = 0.13
	glove.mesh = gm
	glove.material_override = white
	glove.position = Vector3(0, -0.64, 0)
	_arm_r.add_child(glove)
	var napkin := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.02, 0.26, 0.15)
	napkin.mesh = nm
	napkin.material_override = white
	napkin.position = Vector3(0.07, -0.42, 0)
	_arm_r.add_child(napkin)
	# голова: рисованное лицо, прилизанные волосы, монокль
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = HEAD_R
	hm.height = HEAD_R * 2.0
	head.mesh = hm
	_head_mat = ShaderMaterial.new()
	_head_mat.shader = HEAD_SHADER
	_head_mat.set_shader_parameter("skin", Color(0.93, 0.79, 0.7))
	_head_mat.set_shader_parameter("face_size", 0.8)
	_head_mat.set_shader_parameter("face_drop", 0.05)
	head.material_override = _head_mat
	head.position = Vector3(0, HEAD_Y, 0)
	head.scale = Vector3(0.95, 1.1, 1.0)   # лицо вытянутое
	_vis.add_child(head)
	_set_face("snob")
	var hair := MeshInstance3D.new()
	var hsm := SphereMesh.new()
	hsm.radius = HEAD_R * 1.04
	hsm.height = HEAD_R * 1.04
	hsm.is_hemisphere = true
	hair.mesh = hsm
	hair.material_override = _mat(Color("1a1410"), 0.2)
	hair.position = Vector3(0, HEAD_Y + 0.06, 0.03)
	hair.rotation.x = 0.35
	_vis.add_child(hair)
	var mono := MeshInstance3D.new()
	var mtm := TorusMesh.new()
	mtm.inner_radius = 0.042
	mtm.outer_radius = 0.052
	mtm.rings = 16
	mtm.ring_segments = 6
	mono.mesh = mtm
	mono.material_override = _mat(Color("d8b44a"), 0.2)
	mono.position = Vector3(-0.07, HEAD_Y + 0.045, -0.2)
	mono.rotation.x = PI / 2
	_vis.add_child(mono)
	# пузырь с репликой
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.outline_size = 12
	_label.pixel_size = 0.0045
	_label.modulate = Color("fff6e0")
	_label.outline_modulate = Color("2a1a14")
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = 620.0
	_label.position = Vector3(0, 2.45, 0)
	_label.no_depth_test = true
	_label.visible = false
	_label.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_label)

static func _mat(c: Color, rough := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

static func _cyl(r: float, h: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 0.85
	cm.height = h
	mi.mesh = cm
	mi.material_override = m
	return mi
