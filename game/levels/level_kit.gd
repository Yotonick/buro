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
