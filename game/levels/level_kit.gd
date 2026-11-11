extends RefCounted
## Кирпичики для сборки уровней кодом: стены, ящики, таблички. Слои физики — как в Kombez.

const L_WORLD := 1
const L_PROP := 2
const PROP_MASK := 1 | 2 | 4 | 8

static func mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

## Неподвижный блок (пол, стена, платформа). pos — центр.
static func block(parent: Node, pos: Vector3, size: Vector3, material: Material, rot := Vector3.ZERO) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = L_WORLD
	b.collision_mask = 0
	_add_box(b, size, material)
	parent.add_child(b)
	b.position = pos
	b.rotation = rot
	return b

static func prop_box(parent: Node, pos: Vector3, size: Vector3, mass: float, color: Color) -> RigidBody3D:
	var b := _prop(mass)
	_add_box(b, size, mat(color))
	parent.add_child(b)
	b.position = pos
	return b

static func prop_ball(parent: Node, pos: Vector3, radius: float, mass: float, color: Color) -> RigidBody3D:
	var b := _prop(mass)
	b.physics_material_override.bounce = 0.6
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = radius
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = mat(color, 0.5)
	b.add_child(mi)
	parent.add_child(b)
	b.position = pos
	return b

static func prop_cylinder(parent: Node, pos: Vector3, radius: float, height: float, mass: float, color: Color) -> RigidBody3D:
	var b := _prop(mass)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat(color)
	b.add_child(mi)
	parent.add_child(b)
	b.position = pos
	return b

## Физический предмет из готовой модели (паки Kenney): модель ставится донышком на pos,
## коробка столкновений — по габаритам модели (box_scale — чуть уже/ниже, если надо).
static func model_prop(parent: Node, path: String, pos: Vector3, scale: float, mass: float,
		yaw := 0.0, box_scale := Vector3.ONE) -> RigidBody3D:
	var b := _prop(mass)
	var model: Node3D = load(path).instantiate()
	model.scale = Vector3.ONE * scale
	var box := model_aabb(model)
	model.position = -box.get_center()
	b.add_child(model)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = (box.size * box_scale).max(Vector3.ONE * 0.03)
	cs.shape = sh
	b.add_child(cs)
	b.set_meta("half", box.size.y * 0.5)
	parent.add_child(b)
	b.position = pos + Vector3.UP * box.size.y * 0.5
	b.rotation.y = yaw
	return b

## Модель без физики (украшение). Ставится донышком на pos.
static func model(parent: Node, path: String, pos: Vector3, scale: float, yaw := 0.0) -> Node3D:
	var m: Node3D = load(path).instantiate()
	m.scale = Vector3.ONE * scale
	var box := model_aabb(m)
	var holder := Node3D.new()
	holder.add_child(m)
	m.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	parent.add_child(holder)
	holder.position = pos
	holder.rotation.y = yaw
	return holder

## Габариты модели (в её собственных координатах, с учётом её масштаба).
static func model_aabb(n: Node3D) -> AABB:
	var acc: Array = [null]
	_aabb(n, n.transform, acc)
	return acc[0] if acc[0] != null else AABB(Vector3.ZERO, Vector3.ONE * 0.1)

static func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	if n is MeshInstance3D:
		var a: AABB = xf * (n as MeshInstance3D).get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for c in n.get_children():
		_aabb(c, xf * c.transform if c is Node3D else xf, acc)

static func sign(parent: Node, pos: Vector3, text: String, yaw := 0.0, size := 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 14
	l.pixel_size = 0.006
	l.modulate = Color("f1efe8")
	l.outline_modulate = Color("12202e")
	l.double_sided = true
	parent.add_child(l)
	l.position = pos
	l.rotation.y = yaw
	return l

static func _prop(mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass
	b.collision_layer = L_PROP
	b.collision_mask = PROP_MASK
	b.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.1
	b.physics_material_override = pm
	return b

static func _add_box(b: PhysicsBody3D, size: Vector3, material: Material) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	b.add_child(mi)
