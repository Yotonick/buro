extends Node3D
## Течь в стекле купола. Пока цела — просто трещинка. Прорвалась — бьёт струя:
## толкает всё, что попадётся, и в зал льётся вода (см. flood.gd).
##
## Как заделать (решает только хост):
##  - прижать к дыре что угодно — тарелку, заглушку, стул, ладонь, напарника:
##    пока дыра закрыта, вода не идёт, но давление отталкивает затычку —
##    без ленты её надо держать;
##  - заклеить лентой прямо по стеклу (оба конца на стекле, полоска через дыру):
##    одна-две полоски — только сочится, три и больше — держит.
##
## Положение: начало узла — дыра на стекле, -basis.z смотрит внутрь зала.

enum S { WHOLE, OPEN, DRIP, SEALED }

const COVER_R := 0.13          ## насколько близко к дыре должна быть затычка
const CROSS_R := 0.14          ## полоска ленты проходит ближе — считается заклеенной
const STRIPS_TO_SEAL := 3
const PUSH := 45.0             ## давление на затычку, Н
const JET_LEN := 2.6
const JET_FORCE := 170.0       ## струя толкает первое, во что бьёт, Н (у самой дыры)…
const JET_ACCEL := 40.0        ## …но лёгкое не разгоняет сильнее этого, м/с²
const FLOW := {S.WHOLE: 0.0, S.OPEN: 1.0, S.DRIP: 0.25, S.SEALED: 0.0}

var state := S.WHOLE
var cover: Node3D              ## чем сейчас заткнута (только хост)

var _world: Node
var _jet: CPUParticles3D
var _crack: MeshInstance3D
var _ring: MeshInstance3D
var _t := 0.0

func _ready() -> void:
	add_to_group("leak")
	add_to_group("tape_hint")
	add_to_group("prompt_near")
	_world = get_tree().get_first_node_in_group("net_world")
	_crack = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.34)
	_crack.mesh = q
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = _crack_texture()
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_crack.material_override = cm
	_crack.position = Vector3(0, 0, -0.02)
	add_child(_crack)
	# тёмное колечко дыры — видно издалека, куда бежать
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.07
	tm.outer_radius = 0.1
	tm.rings = 16
	tm.ring_segments = 6
	_ring.mesh = tm
	_ring.material_override = _flat(Color("10202c"))
	_ring.rotation = Vector3(PI / 2, 0, 0)
	_ring.position = Vector3(0, 0, -0.03)
	add_child(_ring)
	_jet = CPUParticles3D.new()
	_jet.amount = 110
	_jet.lifetime = 0.5
	_jet.direction = Vector3(0, 0, -1)
	_jet.spread = 7.0
	_jet.initial_velocity_min = 5.5
	_jet.initial_velocity_max = 7.0
	_jet.gravity = Vector3(0, -9.8, 0)
	_jet.scale_amount_min = 0.6
	_jet.scale_amount_max = 1.4
	var sm := SphereMesh.new()
	sm.radius = 0.028
	sm.height = 0.14
	sm.radial_segments = 6
	sm.rings = 3
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.75, 0.9, 1.0, 0.7)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = wm
	_jet.mesh = sm
	_jet.local_coords = false
	_jet.particle_flag_align_y = true   # капли вытянуты по ходу струи
	_jet.position = Vector3(0, 0, -0.04)
	add_child(_jet)
	_show()

## Прорвать (только хост).
func burst() -> void:
	if state == S.WHOLE:
		_set_state(S.OPEN)

func is_burst() -> bool:
	return state != S.WHOLE

## Сколько воды льётся: 0 — нисколько, 1 — открытая дыра.
func flow() -> float:
	return FLOW[state]

func inward() -> Vector3:
	return -global_basis.z

## Для изоленты: подсвечивать ли колечко на стекле в этой точке.
func wants_tape(p: Vector3) -> bool:
	return state != S.WHOLE and p.distance_to(global_position) < 0.6

## Всплывающая подсказка, когда стоишь рядом с открытой течью.
func near_hint(k: Node3D) -> Array:
	if (state != S.OPEN and state != S.DRIP) or k.global_position.distance_to(global_position) > 2.6:
		return []
	if state == S.DRIP:
		return [["use", "сочится — ещё полоску ленты поперёк"]]
	return [[["grab_left", "grab_right"], "прижми к дыре что угодно"], ["use", "или заклей лентой: 3 полоски"]]

func net_state(d: Dictionary) -> void:
	state = int(d.get("s", S.WHOLE)) as S
	_show()

func _set_state(s: S) -> void:
	if s == state:
		return
	state = s
	_show()
	if _world != null:
		_world.sync_state(self, {"s": state})

func _show() -> void:
	_crack.visible = state != S.WHOLE
	_ring.visible = state != S.WHOLE and state != S.SEALED
	_jet.emitting = state == S.OPEN or state == S.DRIP
	if state == S.DRIP:
		_jet.amount = 16
		_jet.initial_velocity_min = 0.6
		_jet.initial_velocity_max = 1.6
		_jet.spread = 25.0
	else:
		_jet.amount = 110
		_jet.initial_velocity_min = 5.5
		_jet.initial_velocity_max = 7.0
		_jet.spread = 7.0

func _physics_process(dt: float) -> void:
	if state == S.WHOLE or _world == null or not _world.is_authority():
		return
	_t += dt
	var n := inward()
	cover = _find_cover()
	var next := S.OPEN
	if cover != null:
		next = S.SEALED
		var rb := cover as RigidBody3D
		if rb != null and not rb.freeze:
			rb.apply_force(n * PUSH, global_position - rb.global_position)
	else:
		var strips := _strips()
		if strips >= STRIPS_TO_SEAL:
			next = S.SEALED
		elif strips > 0:
			next = S.DRIP
	_set_state(next)
	if state == S.OPEN:
		_blast(n)

## Что прижато к дыре (ближе COVER_R к точке чуть внутри зала).
func _find_cover() -> Node3D:
	var sq := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = COVER_R
	sq.shape = sph
	sq.transform = Transform3D(Basis.IDENTITY, global_position + inward() * 0.06)
	sq.collision_mask = 2 | 4 | 8
	var hits := get_world_3d().direct_space_state.intersect_shape(sq, 4)
	for h in hits:
		var c: Object = h["collider"]
		if c is PhysicsBody3D:
			return c
	return null

## Сколько полосок ленты проходит через дыру.
func _strips() -> int:
	return crossing_tapes().size()

## Полоски ленты, которые проходят через дыру (для приёмки: их можно отодрать).
func crossing_tapes() -> Array:
	var p := global_position
	var out: Array = []
	for t in get_tree().get_nodes_in_group("tape"):
		if t.is_queued_for_deletion():
			continue
		var a: Vector3 = t.end_point(true)
		var b: Vector3 = t.end_point(false)
		var c := Geometry3D.get_closest_point_to_segment(p, a, b)
		if c.distance_to(p) < CROSS_R:
			out.append(t)
	return out

## Струя бьёт в первое тело на пути.
func _blast(n: Vector3) -> void:
	var from := global_position + n * 0.05
	var q := PhysicsRayQueryParameters3D.create(from, from + n * JET_LEN, 2 | 4 | 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var rb := hit["collider"] as RigidBody3D
	if rb == null or rb.freeze:
		return
	var d := from.distance_to(hit["position"])
	var f := minf(JET_FORCE, rb.mass * JET_ACCEL) * (1.0 - d / JET_LEN * 0.7) * (1.0 + 0.25 * sin(_t * 23.0))
	rb.apply_force(n * f, (hit["position"] as Vector3) - rb.global_position)

static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.4
	return m

## Трещина: лучи из центра, рисуется один раз на все течи.
static var _crack_tex: ImageTexture

static func _crack_texture() -> ImageTexture:
	if _crack_tex != null:
		return _crack_tex
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for ray in 9:
		var ang := ray * TAU / 9.0 + rng.randf_range(-0.3, 0.3)
		var p := Vector2(s / 2.0, s / 2.0)
		var steps := rng.randi_range(18, 30)
		for i in steps:
			ang += rng.randf_range(-0.35, 0.35)
			p += Vector2(cos(ang), sin(ang)) * 2.0
			var w := 1 if i > steps / 2 else 2
			for dx in range(-w + 1, w):
				for dy in range(-w + 1, w):
					var x := int(p.x) + dx
					var y := int(p.y) + dy
					if x >= 0 and y >= 0 and x < s and y < s:
						img.set_pixel(x, y, Color(0.92, 0.97, 1.0, 0.9))
	_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex
