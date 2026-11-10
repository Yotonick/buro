extends Node3D
## Кусок изоленты между двумя телами (или телом и стеной/полом).
## Ведёт себя как короткий ремень: не даёт точкам крепления разойтись дальше, чем
## они были в момент намотки, а ближе — пожалуйста. Перегрузили — рвётся.
## Создаётся только через NetWorld.spawn("tape", …), поэтому одинаков у всех игроков;
## физику считает хост, у клиентов — только картинка.

const COLOR := Color("2456c8")     ## синяя, какая же ещё
const WIDTH := 0.06
const THICK := 0.008
const STIFF_MAX := 6000.0          ## жёсткость ремня, Н/м (для лёгких предметов берётся меньше)
const STRENGTH := 1000.0           ## рвётся, если дольше мгновения тянут сильнее, Н
const BREAK_STRETCH := 0.45        ## или если растянули больше, м
const BREAK_TIME := 0.15

var a_id := 0                      ## номер тела в NetWorld; 0 — неподвижный мир
var b_id := 0
var a_local := Vector3.ZERO        ## точка крепления в координатах тела (для мира — мировая)
var b_local := Vector3.ZERO
var a_normal := Vector3.UP
var b_normal := Vector3.UP
var rest := 0.1
var puppet := false
var tension := 0.0                 ## с какой силой сейчас натянута, Н

var _world: Node
var _strip: MeshInstance3D
var _patch_a: MeshInstance3D
var _patch_b: MeshInstance3D
var _over := 0.0
var _age := 0.0

static func create(params: Dictionary) -> Node3D:
	var t: Node3D = load("res://physics/tape.gd").new()
	t.a_id = int(params.get("a", 0))
	t.b_id = int(params.get("b", 0))
	t.a_local = params.get("la", Vector3.ZERO)
	t.b_local = params.get("lb", Vector3.ZERO)
	t.a_normal = params.get("na", Vector3.UP)
	t.b_normal = params.get("nb", Vector3.UP)
	t.rest = float(params.get("rest", 0.1))
	return t

func set_puppet(v: bool) -> void:
	puppet = v

func _ready() -> void:
	add_to_group("tape")
	_world = get_tree().get_first_node_in_group("net_world")
	_strip = make_strip(self)
	_patch_a = make_strip(self)
	_patch_b = make_strip(self)

## Полоска ленты; ставится на место функцией place_strip.
static func make_strip(parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = COLOR
	m.roughness = 0.45
	mi.material_override = m
	mi.top_level = true
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.visible = false
	parent.add_child(mi)
	return mi

## Растянуть полоску от точки a до точки b.
static func place_strip(mi: MeshInstance3D, a: Vector3, b: Vector3, width := WIDTH) -> void:
	var d := b - a
	var l := d.length()
	mi.visible = l > 0.005
	if not mi.visible:
		return
	var z := d / l
	var x := (Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).cross(z).normalized()
	mi.global_transform = Transform3D(Basis(x * width, z.cross(x) * THICK, z * l), (a + b) * 0.5)

## Заплатка в точке крепления: квадратик ленты, лежащий на поверхности.
static func place_patch(mi: MeshInstance3D, at: Vector3, normal: Vector3) -> void:
	var n := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var x := (Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).cross(n).normalized()
	mi.visible = true
	mi.global_transform = Transform3D(Basis(x * 0.14, n * 0.012, x.cross(n) * 0.14), at + n * 0.004)

func _body(id: int) -> Node3D:
	if id == 0 or _world == null:
		return null
	var n: Node3D = _world.node_of(id)
	return n if is_instance_valid(n) else null

## Где сейчас точка крепления: [точка, нормаль]. smooth — для картинки (между тиками физики).
static func anchor(body: Node3D, local: Vector3, normal: Vector3, smooth: bool) -> Array:
	if body == null:
		return [local, normal]
	var xf := body.get_global_transform_interpolated() if smooth else body.global_transform
	return [xf * local, xf.basis * normal]

func _physics_process(dt: float) -> void:
	if puppet:
		return
	_age += dt
	var a := _body(a_id)
	var b := _body(b_id)
	# тело, к которому примотано, исчезло — лента больше ни к чему
	if (a_id != 0 and a == null) or (b_id != 0 and b == null):
		queue_free()
		return
	var pa: Vector3 = anchor(a, a_local, a_normal, false)[0]
	var pb: Vector3 = anchor(b, b_local, b_normal, false)[0]
	var d := pa.distance_to(pb)
	var stretch := d - rest
	tension = 0.0
	if stretch <= 0.0 or d < 0.001:
		_over = 0.0
		return
	var ra := a as RigidBody3D
	var rb := b as RigidBody3D
	if ra != null and ra.freeze:
		ra = null
	if rb != null and rb.freeze:
		rb = null
	var n := (pb - pa) / d
	var inv := (1.0 / ra.mass if ra != null else 0.0) + (1.0 / rb.mass if rb != null else 0.0)
	if inv > 0.0:
		# Жёсткость подбирается под массу, чтобы лёгкие предметы не трясло.
		var m := 1.0 / inv
		var k := minf(STIFF_MAX, 0.2 * m / (dt * dt))
		var c := 2.0 * sqrt(k * m) * 0.7
		var va := _vel_at(a, pa)
		var vb := _vel_at(b, pb)
		tension = k * stretch
		var f := clampf(tension + c * (vb - va).dot(n), 0.0, STRENGTH * 1.5)
		if ra != null:
			ra.apply_force(n * f, pa - ra.global_position)
		if rb != null:
			rb.apply_force(-n * f, pb - rb.global_position)
	if tension > STRENGTH:
		_over += dt
	else:
		_over = 0.0
	if _over > BREAK_TIME or stretch > BREAK_STRETCH:
		queue_free()   # порвалась; NetWorld сам уберёт её у всех

static func _vel_at(body: Node3D, point: Vector3) -> Vector3:
	var rb := body as RigidBody3D
	if rb == null:
		return body.get_meta(&"net_vel", Vector3.ZERO) if body != null else Vector3.ZERO
	return rb.linear_velocity + rb.angular_velocity.cross(point - rb.global_position)

func _process(_dt: float) -> void:
	var a := _body(a_id)
	var b := _body(b_id)
	if (a_id != 0 and a == null) or (b_id != 0 and b == null):
		_strip.visible = false
		_patch_a.visible = false
		_patch_b.visible = false
		return
	var ea := anchor(a, a_local, a_normal, true)
	var eb := anchor(b, b_local, b_normal, true)
	place_strip(_strip, ea[0], eb[0])
	place_patch(_patch_a, ea[0], ea[1])
	place_patch(_patch_b, eb[0], eb[1])
