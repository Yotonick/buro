extends Node3D
## Внешний вид Комбеза: собирается из простых объёмных сегментов (без ткани),
## рисованное лицо меняется по состоянию, руки и ноги тянутся за физикой.
## Только картинка — на физику не влияет.

const HEAD_SHADER := preload("res://characters/kombez/head.gdshader")
const FACES := {
	"idle": preload("res://characters/kombez/face/idle.svg"),
	"blink": preload("res://characters/kombez/face/blink.svg"),
	"effort": preload("res://characters/kombez/face/effort.svg"),
	"panic": preload("res://characters/kombez/face/panic.svg"),
	"ko": preload("res://characters/kombez/face/ko.svg"),
	"joy": preload("res://characters/kombez/face/joy.svg"),
}
const HEAD_Y := 0.56
const HEAD_R := 0.31
const HIP := Vector3(0.17, -0.36, 0.0)
const FOOT_REST_Y := -0.72

var body: RigidBody3D
var _puff: Node3D
var _head_mat: ShaderMaterial
var _helmet: Node3D
var _arms: Array[MeshInstance3D] = []
var _legs: Array[MeshInstance3D] = []
var _feet: Array[MeshInstance3D] = []
var _face := ""
var _blink_in := 2.0
var _blink_left := 0.0
var _step := 0.0
var _time := 0.0

func setup(b: RigidBody3D) -> void:
	body = b
	var suit := _mat(b.suit_color)
	var suit_dark := _mat(b.suit_color.darkened(0.35))
	var yellow := _mat(Color("f2c230"))
	_puff = Node3D.new()
	add_child(_puff)

	var torso := _sphere(0.42, suit, _puff, Vector3(0, -0.08, 0))
	torso.scale = Vector3(1.0, 1.08, 0.95)
	var collar := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.29
	tm.rings = 24
	tm.ring_segments = 12
	collar.mesh = tm
	collar.material_override = suit_dark
	collar.position = Vector3(0, 0.25, 0)
	collar.scale = Vector3(1, 0.7, 1)
	_puff.add_child(collar)
	_box(Vector3(0.24, 0.17, 0.05), suit_dark, _puff, Vector3(0, -0.04, -0.395))
	_box(Vector3(0.09, 0.05, 0.02), yellow, _puff, Vector3(0.05, 0.0, -0.425))
	_sphere(0.035, yellow, _puff, Vector3(0.15, 0.13, -0.355))
	_sphere(0.035, yellow, _puff, Vector3(-0.15, 0.13, -0.355))
	# петля на спине — за неё таскают
	var loop := MeshInstance3D.new()
	var lm := TorusMesh.new()
	lm.inner_radius = 0.055
	lm.outer_radius = 0.1
	loop.mesh = lm
	loop.material_override = _mat(Color("e8762c"))
	loop.position = Vector3(0, 0.1, 0.42)
	loop.rotation = Vector3(0, 0, PI / 2)
	_puff.add_child(loop)
	for s in [-1.0, 1.0]:
		_sphere(0.15, suit, _puff, Vector3(s * 0.33, 0.19, 0))

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = HEAD_R
	hm.height = HEAD_R * 2.0
	head.mesh = hm
	_head_mat = ShaderMaterial.new()
	_head_mat.shader = HEAD_SHADER
	head.material_override = _head_mat
	head.position = Vector3(0, HEAD_Y, 0)
	_puff.add_child(head)
	_set_face("idle")
	refresh_helmet()

	for s in [-1.0, 1.0]:
		_arms.append(_cyl(0.09, suit))
		_legs.append(_cyl(0.115, suit_dark))
		var foot := _sphere(1.0, _mat(Color("3a2a22")), self, Vector3.ZERO)
		foot.scale = Vector3(0.13, 0.085, 0.19)
		_feet.append(foot)

## Каска как отдельный узел — её же использует слетевшая каска-предмет.
static func build_helmet(color: Color) -> Node3D:
	var root := Node3D.new()
	var m := _mat(color)
	m.roughness = 0.35
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.34
	dm.height = 0.3
	dm.is_hemisphere = true
	dome.mesh = dm
	dome.material_override = m
	root.add_child(dome)
	var brim := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.4
	bm.bottom_radius = 0.41
	bm.height = 0.03
	brim.mesh = bm
	brim.material_override = m
	brim.position = Vector3(0, 0.0, -0.04)
	root.add_child(brim)
	var ridge := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.07, 0.05, 0.5)
	ridge.mesh = rm
	ridge.material_override = m
	ridge.position = Vector3(0, 0.285, 0)
	root.add_child(ridge)
	return root

func refresh_helmet() -> void:
	if _helmet != null:
		_helmet.queue_free()
		_helmet = null
	if body.has_helmet:
		_helmet = build_helmet(body.helmet_color)
		_helmet.position = Vector3(0, HEAD_Y + 0.17, 0.02)
		_helmet.rotation = Vector3(-0.06, 0, 0.07)
		_puff.add_child(_helmet)

func tick(dt: float) -> void:
	_time += dt
	# лицо
	_blink_in -= dt
	if _blink_in <= 0.0:
		_blink_in = randf_range(1.8, 4.5)
		_blink_left = 0.12
	_blink_left -= dt
	var face := "idle"
	if body.is_ko():
		face = "ko"
	elif body.laugh_time > 0.0:
		face = "joy"
	elif body.air_time > 0.55 or (not body.grounded and body.visual_velocity().y < -5.5):
		face = "panic"
	elif body.effort() > 0.5:
		face = "effort"
	elif _blink_left > 0.0:
		face = "blink"
	_set_face(face)

	# «сдувается» в нокауте, трясётся от смеха
	var want := Vector3.ONE
	if body.is_ko():
		want = Vector3(1.14, 0.74, 1.14)
	elif body.laugh_time > 0.0:
		var k := sin(_time * 28.0) * 0.06
		want = Vector3(1.0 - k * 0.5, 1.0 + k, 1.0 - k * 0.5)
	_puff.scale = _puff.scale.lerp(want, 1.0 - exp(-dt * 12.0))

	# руки
	var hands: Array = [body.hand_l, body.hand_r]
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var a := Vector3(s * 0.34, 0.2, 0)
		var b: Vector3 = to_local(hands[i].global_position)
		_stretch(_arms[i], a, b)

	# ноги: шагают, когда идёт; болтаются в воздухе
	var local_vel: Vector3 = body.global_basis.inverse() * body.visual_velocity()
	local_vel.y = 0.0
	var speed := local_vel.length()
	var walking: bool = body.grounded and not body.is_ko()
	if walking:
		_step += speed * dt * 4.2
	var dir := local_vel / speed if speed > 0.3 else Vector3.ZERO
	var amount := clampf(speed / 3.0, 0.0, 1.0)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var ph := _step + (PI if i == 1 else 0.0)
		var foot := Vector3(s * HIP.x, FOOT_REST_Y, 0.0)
		if walking:
			foot.y = -body.ground_dist + 0.07 + maxf(cos(ph), 0.0) * 0.14 * amount
			foot += dir * sin(ph) * 0.2 * amount
		elif not body.is_ko():
			foot.y = -0.6 + sin(_time * 9.0 + s) * 0.04
			foot.z = 0.08 * s * sin(_time * 7.0)
		_feet[i].position = foot + Vector3(0, 0, -0.05)
		_stretch(_legs[i], Vector3(s * HIP.x, HIP.y, 0), foot + Vector3(0, 0.04, 0))

func _set_face(face: String) -> void:
	if face == _face:
		return
	_face = face
	_head_mat.set_shader_parameter("face", FACES[face])

static func _stretch(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := maxf(d.length(), 0.01)
	var y := d / l
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)

static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m

func _sphere(r: float, m: Material, parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

func _box(size: Vector3, m: Material, parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

func _cyl(r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 1.0
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	add_child(mi)
	return mi
