extends RefCounted
## Кирпичики для сборки уровней кодом: стены, ящики, таблички и экранчики. Слои физики — как в Kombez.

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

# ---------- таблички и экранчики ----------
## Текст на уровне — только на предметах: жестяная табличка с рамкой и заклёпками,
## прикрученная к стене / стойке / подвешенная, или экранчик на корпусе машины.

const SIGN_FONT: FontFile = preload("res://ui/theme/fonts/RussoOne-Regular.ttf")
const SCREEN_FONT: FontFile = preload("res://ui/theme/fonts/PTMono-Regular.ttf")
const SIGN_PX_FONT := 64       ## шрифт растрируется крупно, размер в мире задаёт pixel_size
## стиль: лицо, текст, рамка, полоса сверху (null — без неё). Цвета — палитра ui_style.gd.
const SIGN_STYLES := {
	"tin": [Color("1f3654"), Color("f4efe4"), Color("14233a"), Color("f2a81d")],
	"signal": [Color("f2a81d"), Color("14233a"), Color("14233a"), null],
	"paper": [Color("efe6d2"), Color("2b2a33"), Color("7d6f55"), null],
	"red": [Color("c8372d"), Color("f4efe4"), Color("5a1712"), null],
	"navy": [Color("14233a"), Color("f2a81d"), Color("0c1626"), null],
}
const SIGN_METAL := Color("5b6570")

## Табличка. pos — середина задней стороны (её прижимают к стене); лицом смотрит в +Z
## после поворота yaw. line_h — высота строки текста в метрах. Размер таблички — по тексту.
## opts: style ("tin" | "signal" | "paper" | "red" | "navy"), w / h — свой размер,
##   mount: "wall" (по умолчанию, только винты) | "post" (стойка до пола) | "legs" (две стойки) |
##          "hang" (на двух тягах вверх на opts.hang м) | "arm" (кронштейн назад на opts.arm м);
##   floor — высота пола для стоек (0); solid — у стоек есть столкновения; both — текст и с обратной стороны.
## Возвращает Label3D (текст можно менять); сама табличка — его родитель.
static func plaque(parent: Node, pos: Vector3, text: String, yaw := 0.0, line_h := 0.12, opts := {}) -> Label3D:
	var st: Array = SIGN_STYLES[opts.get("style", "tin")]
	var root := Node3D.new()
	root.name = "Plaque"
	root.set_meta("plaque", true)
	parent.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var px := line_h / SIGN_FONT.get_height(SIGN_PX_FONT)
	var tsz := SIGN_FONT.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, SIGN_PX_FONT) * px
	var pad := line_h * 0.42
	var stripe_h: float = line_h * 0.2 if st[3] != null else 0.0
	var w: float = opts.get("w", tsz.x + pad * 2.0)
	var h: float = opts.get("h", tsz.y + pad * 1.3 + stripe_h)
	var b := clampf(line_h * 0.12, 0.012, 0.04)       # ширина рамки
	var d := 0.025                                   # толщина
	var frame_m := mat(st[2], 0.55)
	frame_m.metallic = 0.4
	_mesh_box(root, Vector3(w + b * 2.0, h + b * 2.0, d), frame_m, Vector3(0, 0, d * 0.5))
	_mesh_box(root, Vector3(w, h, 0.006), mat(st[0], 0.7), Vector3(0, 0, d + 0.003))
	if st[3] != null:
		_mesh_box(root, Vector3(w, stripe_h, 0.007), mat(st[3], 0.6), Vector3(0, h * 0.5 - stripe_h * 0.5, d + 0.0035))
	var both: bool = opts.get("both", false)
	if both:
		_mesh_box(root, Vector3(w, h, 0.006), mat(st[0], 0.7), Vector3(0, 0, -0.003))
	# заклёпки по углам
	var rv := clampf(line_h * 0.06, 0.006, 0.02)
	var rivet_m := mat(st[2].lightened(0.35), 0.4)
	rivet_m.metallic = 0.7
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var r := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = rv
			sm.height = rv * 1.2
			sm.radial_segments = 8
			sm.rings = 4
			r.mesh = sm
			r.material_override = rivet_m
			r.position = Vector3(sx * (w * 0.5 + b * 0.5), sy * (h * 0.5 + b * 0.5), d)
			root.add_child(r)
	var l := _sign_label(text, px, st[1], Vector3(0, -stripe_h * 0.5, d + 0.0075))
	root.add_child(l)
	if both:
		var back := _sign_label(text, px, st[1], Vector3(0, -stripe_h * 0.5, -0.0075))
		back.rotation.y = PI
		root.add_child(back)
		l.set_meta("back", back)
		l.tree_exiting.connect(back.queue_free)
	_mount(root, opts.get("mount", "wall"), w, h + b * 2.0, pos, opts)
	return l

## Поменять текст таблички (с обеих сторон, если она двусторонняя).
static func set_plaque_text(l: Label3D, text: String) -> void:
	l.text = text
	if l.has_meta("back"):
		(l.get_meta("back") as Label3D).text = text

static func _sign_label(text: String, px: float, c: Color, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = SIGN_FONT
	l.font_size = SIGN_PX_FONT
	l.pixel_size = px
	l.outline_size = 0
	l.modulate = c
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = at
	return l

static func _mount(root: Node3D, kind: String, w: float, h: float, pos: Vector3, opts: Dictionary) -> void:
	var metal := mat(SIGN_METAL, 0.45)
	metal.metallic = 0.6
	match kind:
		"post", "legs":
			var bottom := -h * 0.5
			var floor_l: float = float(opts.get("floor", 0.0)) - pos.y
			var len := bottom - floor_l + h * 0.75   # стойка заходит за табличку
			if len <= 0.02:
				return
			var xs: Array = [0.0] if kind == "post" else [-w * 0.5 + 0.08, w * 0.5 - 0.08]
			var rad := 0.025 if kind == "post" else 0.045
			for x in xs:
				var at := Vector3(x, floor_l + len * 0.5, -rad)
				if opts.get("solid", false):
					var sb := StaticBody3D.new()
					sb.collision_layer = L_WORLD
					sb.collision_mask = 0
					var cs := CollisionShape3D.new()
					var sh := CylinderShape3D.new()
					sh.radius = rad
					sh.height = len
					cs.shape = sh
					sb.add_child(cs)
					sb.position = at
					root.add_child(sb)
					sb.add_child(_cyl_mesh(rad, len, metal))
				else:
					var c := _cyl_mesh(rad, len, metal)
					c.position = at
					root.add_child(c)
				var foot := _cyl_mesh(rad * 3.2, 0.02, metal)
				foot.position = Vector3(x, floor_l + 0.01, -rad)
				root.add_child(foot)
		"hang":
			var up: float = opts.get("hang", 0.3)
			for x in [-w * 0.35, w * 0.35]:
				var c := _cyl_mesh(0.008, up, metal)
				c.position = Vector3(x, h * 0.5 + up * 0.5, 0.0125)
				root.add_child(c)
		"arm":
			var back: float = opts.get("arm", 0.3)
			var arm := _cyl_mesh(0.015, back + 0.04, metal)
			arm.rotation.x = PI / 2
			arm.position = Vector3(0, h * 0.5 + 0.08, 0.0125 - back * 0.5)
			root.add_child(arm)
			for x in [-w * 0.35, w * 0.35]:
				var c := _cyl_mesh(0.006, 0.09, metal)
				c.position = Vector3(x * 0.6, h * 0.5 + 0.04, 0.0125)
				root.add_child(c)
		_:
			pass

## Экранчик на корпусе машины (табло насоса, щитка): рамка, тёмное стекло, светящийся
## моноширинный текст с переносом. pos — середина задней стороны, лицом в +Z после yaw.
static func screen(parent: Node, pos: Vector3, w: float, h: float, yaw := 0.0, line_h := 0.04,
		glow := Color("ffc24a")) -> Label3D:
	var root := Node3D.new()
	root.name = "Screen"
	root.set_meta("plaque", true)
	parent.add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var bezel := mat(Color("1b2026"), 0.5)
	bezel.metallic = 0.3
	_mesh_box(root, Vector3(w + 0.05, h + 0.05, 0.03), bezel, Vector3(0, 0, 0.015))
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color("0c1714").lerp(glow, 0.06)
	_mesh_box(root, Vector3(w, h, 0.004), glass, Vector3(0, 0, 0.032))
	var px := line_h / SCREEN_FONT.get_height(SIGN_PX_FONT)
	var l := Label3D.new()
	l.font = SCREEN_FONT
	l.font_size = SIGN_PX_FONT
	l.pixel_size = px
	l.outline_size = 0
	l.modulate = glow
	l.shaded = false
	l.double_sided = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = (w - line_h * 0.8) / px
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = Vector3(0, 0, 0.0345)
	root.add_child(l)
	return l

## Плоская фигура (наклейка на корпусе): точки в метрах в плоскости XY, лицом в +Z.
static func decal(parent: Node, points: PackedVector2Array, c: Color, at: Vector3, yaw := 0.0) -> MeshInstance3D:
	var idx := Geometry2D.triangulate_polygon(points)
	var verts := PackedVector3Array()
	for i in idx:
		verts.append(Vector3(points[i].x, points[i].y, 0.0))
	var am := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	nrm.fill(Vector3.BACK)
	arr[Mesh.ARRAY_NORMAL] = nrm
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	var m := mat(c, 0.7)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	parent.add_child(mi)
	mi.position = at
	mi.rotation.y = yaw
	return mi

## Стрелка-треугольник (под табличкой «крюк ↓» и т.п.): острие вниз, лицом в +Z.
static func arrow_down(parent: Node, at: Vector3, size: float, c: Color, yaw := 0.0) -> MeshInstance3D:
	var s := size
	return decal(parent, PackedVector2Array([Vector2(-s * 0.25, s * 0.5), Vector2(s * 0.25, s * 0.5),
		Vector2(s * 0.25, 0.05 * s), Vector2(s * 0.5, 0.05 * s), Vector2(0, -s * 0.5),
		Vector2(-s * 0.5, 0.05 * s), Vector2(-s * 0.25, 0.05 * s)]), c, at, yaw)

static func _mesh_box(parent: Node, size: Vector3, m: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi

static func _cyl_mesh(r: float, h: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	return mi

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
