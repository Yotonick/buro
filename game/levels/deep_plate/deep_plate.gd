extends "res://levels/level_base.gd"
## Вызов №1: подводный ресторан «Глубокая тарелка».
## Стеклянный купол на дне моря, идёт банкет, купол течёт. Бригада входит через
## служебный шлюз. Течи прорываются всё чаще; вода поднимается от каждой открытой.
## Дошла до столов — ресторан затопило. Продержались смену и всё заделано — справились.
## Насос у дальней стены откачивает воду — если собрать его разорванную трубу.
## Щиток у западной стены даёт свет: скачки выбивают пробки и рубильник, вода до розеток — короткое.
## Продержались смену и всё заделано — метрдотель обходит зал (plate_review.gd), итог — звёзды.
## (Осьминог отложен владельцем.)

const LeakScript := preload("res://levels/deep_plate/leak.gd")
const FloodScript := preload("res://levels/deep_plate/flood.gd")
const ShiftScript := preload("res://levels/shift.gd")
const PumpScript := preload("res://levels/deep_plate/pump.gd")
const BoardScript := preload("res://levels/deep_plate/switchboard.gd")
const SeaLife := preload("res://levels/deep_plate/sea_life.gd")
const ClientNpc := preload("res://characters/client/client_npc.gd")
const ReviewScript := preload("res://levels/deep_plate/plate_review.gd")
const FLOOR_SHADER := preload("res://levels/deep_plate/floor.gdshader")

const R := 10.0                ## радиус купола (внутренняя сторона стекла)
const WALL_H := 3.2            ## высота стеклянной стены, выше — свод
const SEGMENTS := 40           ## стена собрана из плоских стёкол
const DOOR_ANGLE := PI / 2     ## шлюз — со стороны +Z
const PUMP_AT := Vector3(0, 0, -8.6)   ## насосная — у стекла напротив шлюза
const BOARD_ANGLE := PI        ## щиток — у стекла с запада (-X)
const TABLE_H := 0.72          ## вода выше этого — затопило
const SHIFT_LEN := 210.0       ## столько секунд прорываются новые течи
const FIRST_LEAK := 12.0
const GAP_START := 30.0        ## промежуток между прорывами в начале смены…
const GAP_END := 11.0          ## …и в конце
const REVIEW_START := Vector3(0, 0, R + 4.2)   ## метрдотель выходит из глубины шлюза
## Стёкла, где может прорваться: номер стекла и высота дыры над полом.
const LEAK_SPOTS := [[0, 0.7], [3, 1.5], [6, 1.0], [12, 1.8], [15, 0.6], [18, 1.3],
	[21, 0.9], [24, 1.7], [27, 0.6], [30, 1.2], [33, 2.0], [36, 0.8], [38, 1.5], [14, 1.1]]

const FOOD := [
	["res://assets/food/turkey.glb", 0.3, 1.2],
	["res://assets/food/cake-birthday.glb", 0.35, 0.8],
	["res://assets/food/fish.glb", 0.42, 0.6],
	["res://assets/food/whole-ham.glb", 0.4, 1.0],
	["res://assets/food/pie.glb", 0.3, 0.6],
	["res://assets/food/bowl-soup.glb", 0.4, 0.5],
	["res://assets/food/sushi-salmon.glb", 0.9, 0.2],
	["res://assets/food/mussel-open.glb", 1.2, 0.15],
]

var leaks: Array = []
var flood: Node3D
var shift: Node3D
var pump: Node3D
var board: Node3D
var env: Environment
var table_lamps: Array = []
var center_light: OmniLight3D
var sun: DirectionalLight3D
var tables: Array = []         ## {body, center, top, food, dish, sector} — для приёмки
var maitre: AnimatableBody3D   ## метрдотель (client_npc.gd)
var review: Node               ## plate_review.gd (работает только у хоста)

var _next_leak := FIRST_LEAK
var _rng := RandomNumberGenerator.new()

func spawn_point(slot: int) -> Vector3:
	return Vector3((slot - 1.5) * 0.9 if Net.in_session() else 0.0, 1.0, R + 3.0)

func _build() -> void:
	_rng.seed = Time.get_ticks_usec()
	_build_env()
	_build_dome()
	_build_airlock()
	_build_hall()
	_build_pump()
	_build_board()
	_build_maitre()
	world.spawned.connect(_on_kombez_spawned)
	hint = "Купол течёт! Прижми к дыре что угодно (заглушку, тарелку, ладонь) и примотай лентой — или заклей дыру лентой крест-накрест (3 полоски)\nНасос у дальней стены: 3 куска трубы от приямка до насоса, стыки — лентой, вентиль — против часовой\nЩиток: пробки — обратно в гнёзда, рубильник — вверх (падает — держи или примотай), вода у розеток — повесь щиток на крюк\nПосле смены — приёмка: метрдотель обходит зал (еда, посуда, свет, заплатки) и ставит звёзды\nВода до столов — затопило   ·   E — рулон на пояс / клеить   ·   Q — бросить   ·   ЛКМ/ПКМ — руки   ·   Ctrl — присесть   ·   R — в шлюз   ·   Esc — пауза"

func _on_kombez_spawned(node: Node, kind: String, _params: Dictionary) -> void:
	if kind == "kombez":
		node.set_meta("half", 0.75)
		node.set_meta("float", 0.55)

# ---------- ход смены (только хост) ----------

func _tick(dt: float) -> void:
	if not shift.working():
		flood.set_flow(0.0, 0.0)
		return
	var total := 0.0
	var open := 0
	for l in leaks:
		total += l.flow()
		if l.flow() > 0.0:
			open += 1
	flood.set_flow(total, pump.drain())
	if flood.level >= TABLE_H:
		shift.finish(false, "ЗАТОПИЛО", "Банкет поплыл. Метрдотель вызывает другую бригаду.")
		return
	var crew := clampi(Net.players.size() if Net.in_session() else 1, 1, 4)
	var k: float = [1.4, 1.0, 0.85, 0.75][crew - 1]
	if shift.time < SHIFT_LEN:
		board.work(dt, k, shift.time / SHIFT_LEN)
		_next_leak -= dt
		if _next_leak <= 0.0:
			_burst_one()
			_next_leak = lerpf(GAP_START, GAP_END, shift.time / SHIFT_LEN) * k
	elif open == 0 and not shift.reviewing():
		shift.start_review("ПРИЁМКА", "Метрдотель обходит зал. Приберись там, куда он ещё не дошёл!")
		review.start()

func _burst_one() -> void:
	var whole := leaks.filter(func(l): return not l.is_burst())
	if whole.is_empty():
		return
	whole[_rng.randi() % whole.size()].burst()

# ---------- постройка (одинаково у всех) ----------

func _build_env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("06222e")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("7fa6b8")
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color("0b3a4a")
	e.fog_density = 0.018
	we.environment = e
	add_child(we)
	env = e
	sun = DirectionalLight3D.new()   # свет с поверхности моря
	sun.rotation_degrees = Vector3(-70, 20, 0)
	sun.light_energy = 0.75
	sun.light_color = Color("bfe6ff")
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	# морское дно вокруг купола
	var sand := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	sand.mesh = pm
	sand.material_override = Kit.mat(Color("8c8466"))
	sand.position = Vector3(0, -0.35, 0)
	add_child(sand)
	var rock := Kit.mat(Color("4a5450"))
	for i in 14:
		var a := i * TAU / 14.0 + 0.2
		var d := R + 4.0 + fmod(i * 7.3, 9.0)
		var s := 0.8 + fmod(i * 1.7, 2.2)
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = s
		sm.height = s * 1.2
		sm.radial_segments = 8
		sm.rings = 4
		m.mesh = sm
		m.material_override = rock
		m.position = Vector3(cos(a) * d, -0.3, sin(a) * d)
		add_child(m)
	var life := SeaLife.new()
	life.dome_radius = R
	add_child(life)

func _build_dome() -> void:
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = FLOOR_SHADER
	var fl := StaticBody3D.new()
	fl.collision_layer = Kit.L_WORLD
	fl.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = R + 0.3
	cyl.height = 0.4
	cs.shape = cyl
	fl.add_child(cs)
	var fm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = R + 0.3
	cm.bottom_radius = R + 0.3
	cm.height = 0.4
	cm.radial_segments = 64
	fm.mesh = cm
	fm.material_override = floor_mat
	fl.add_child(fm)
	add_child(fl)
	fl.position = Vector3(0, -0.2, 0)

	# стена — плоские стёкла по кругу (по ним удобно клеить), в проёме — шлюз
	var step := TAU / SEGMENTS
	var width := 2.0 * (R + 0.15) * tan(step / 2.0) + 0.06
	var invisible := StandardMaterial3D.new()
	invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	invisible.albedo_color = Color(0, 0, 0, 0)
	for i in SEGMENTS:
		var a := (i + 0.5) * step
		if absf(angle_difference(a, DOOR_ANGLE)) < step * 0.9:
			continue
		var b := Kit.block(self, Vector3(cos(a) * (R + 0.15), WALL_H / 2.0, sin(a) * (R + 0.15)),
			Vector3(width, WALL_H, 0.3), invisible, Vector3(0, -a + PI / 2, 0))
		b.get_child(1).visible = false   # видно стекло (ниже), а это — только твёрдая часть
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.8, 0.9, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wall := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = R / cos(step / 2.0)   # грани совпадают с плоскими стёклами
	wm.bottom_radius = R / cos(step / 2.0)
	wm.height = WALL_H
	wm.cap_top = false
	wm.cap_bottom = false
	wm.radial_segments = SEGMENTS
	wall.mesh = wm
	wall.material_override = glass
	wall.position = Vector3(0, WALL_H / 2.0, 0)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)
	# свод
	var cap := StaticBody3D.new()
	cap.collision_layer = Kit.L_WORLD
	cap.collision_mask = 0
	var sm := SphereMesh.new()
	sm.radius = R / cos(step / 2.0)
	sm.height = 10.0
	sm.is_hemisphere = true
	sm.radial_segments = SEGMENTS
	sm.rings = 10
	var capm := MeshInstance3D.new()
	capm.mesh = sm
	capm.material_override = glass
	capm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.add_child(capm)
	var ccs := CollisionShape3D.new()
	var tri: ConcavePolygonShape3D = sm.create_trimesh_shape()
	tri.backface_collision = true
	ccs.shape = tri
	cap.add_child(ccs)
	add_child(cap)
	cap.position = Vector3(0, WALL_H, 0)
	# рёбра каркаса
	var steel := Kit.mat(Color("8a969c"), 0.35)
	for i in 10:
		var a := i * TAU / 10.0 + step * 0.5
		if absf(angle_difference(a, DOOR_ANGLE)) < 0.3:
			continue
		var rib := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, WALL_H, 0.14)
		rib.mesh = bm
		rib.material_override = steel
		rib.position = Vector3(cos(a) * (R + 0.05), WALL_H / 2.0, sin(a) * (R + 0.05))
		add_child(rib)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = R - 0.05
	tm.outer_radius = R + 0.15
	tm.rings = 64
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = steel
	ring.position = Vector3(0, WALL_H, 0)
	add_child(ring)

	# течи — по стёклам
	for spot in LEAK_SPOTS:
		var a: float = (int(spot[0]) + 0.5) * step
		var leak := LeakScript.new()
		var p := Vector3(cos(a) * R, float(spot[1]), sin(a) * R)
		add_child(leak)
		leak.position = p
		leak.basis = Basis.looking_at(-p * Vector3(1, 0, 1), Vector3.UP)
		world.track(leak)
		leaks.append(leak)

	flood = FloodScript.new()
	flood.radius = R - 0.05
	add_child(flood)
	world.track(flood)
	shift = ShiftScript.new()
	add_child(shift)
	world.track(shift)

func _build_airlock() -> void:
	# короткий служебный коридор за проёмом, в нём — инструменты бригады
	var metal := Kit.mat(Color("6c7a80"), 0.6)
	var dark := Kit.mat(Color("3d474c"), 0.7)
	var z0 := R - 0.4
	var z1 := R + 5.0
	var zc := (z0 + z1) / 2.0
	var w := 3.4
	Kit.block(self, Vector3(0, -0.2, zc), Vector3(w + 0.6, 0.4, z1 - z0), dark)
	Kit.block(self, Vector3(0, 3.15, zc + 0.2), Vector3(w + 0.6, 0.3, z1 - z0 + 0.4), metal)
	for s in [-1.0, 1.0]:
		Kit.block(self, Vector3(s * (w / 2.0 + 0.15), 1.5, zc), Vector3(0.3, 3.0, z1 - z0), metal)
	Kit.block(self, Vector3(0, 1.5, z1 + 0.15), Vector3(w + 0.6, 3.0, 0.3), metal)
	Kit.block(self, Vector3(0, 2.95, R + 0.15), Vector3(w + 0.4, 0.5, 0.4), metal)   # притолока
	Kit.sign(self, Vector3(0, 2.45, R + 0.4), "ШЛЮЗ №2 · СЛУЖЕБНЫЙ", 0.0, 44)
	Kit.sign(self, Vector3(0, 2.0, z1 - 0.01), "БЮРО НЕВОЗМОЖНОГО РЕМОНТА\nвызов: «Глубокая тарелка», купол течёт", PI, 40)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.7, zc)
	lamp.light_color = Color("f4f0e0")
	lamp.light_energy = 1.2
	lamp.omni_range = 6.0
	add_child(lamp)
	# стеллаж: изолента и заглушки
	Kit.block(self, Vector3(-1.2, 0.4, z1 - 0.6), Vector3(0.9, 0.8, 0.8), Kit.mat(Color("6b4f34")))
	Kit.block(self, Vector3(1.2, 0.4, z1 - 0.6), Vector3(0.9, 0.8, 0.8), Kit.mat(Color("6b4f34")))
	for i in 4:
		var roll: RigidBody3D = TapeRoll.create({})
		roll.position = Vector3(-1.45 + (i % 2) * 0.5, 0.86, z1 - 0.8 + (i / 2) * 0.4)
		add_child(roll)
	Kit.sign(self, Vector3(-1.2, 1.35, z1 - 0.6), "ИЗОЛЕНТА", PI, 36)
	for i in 8:
		var plug := Kit.prop_cylinder(self, Vector3(0.95 + (i % 3) * 0.25, 0.84 + (i / 3) * 0.07, z1 - 0.7 + (i % 2) * 0.2),
			0.14, 0.06, 0.4, Color("b8322a"))
		plug.add_to_group("plug")
		plug.set_meta("half", 0.03)
		plug.set_meta("float", 1.6)
	Kit.sign(self, Vector3(1.2, 1.35, z1 - 0.6), "ЗАГЛУШКИ", PI, 36)

func _build_pump() -> void:
	# куски трубы: два валяются у насосной, третий унесло в зал
	var lying := func(at: Vector3, yaw: float) -> Transform3D:
		return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI / 2), at + Vector3.UP * PumpScript.FLANGE_R)
	pump = PumpScript.new()
	pump.build(self, Transform3D(Basis.IDENTITY, PUMP_AT),
		[lying.call(Vector3(-1.0, 0, -7.4), 0.4), lying.call(Vector3(1.3, 0, -7.2), -0.6), lying.call(Vector3(2.2, 0, 1.8), 1.1)])
	world.track(pump)

func _build_board() -> void:
	board = BoardScript.new()
	var at := Vector3(cos(BOARD_ANGLE), 0, sin(BOARD_ANGLE)) * R
	var into := -at.normalized()
	board.build(self, Transform3D(Basis(Vector3.UP, atan2(into.x, into.z)), at))
	world.track(board)
	# пробка i — столы 2i и 2i+1; общий свет горит, пока есть хоть один сектор
	var sectors: Array = []
	for i in 3:
		sectors.append([table_lamps[i * 2], table_lamps[i * 2 + 1]])
	board.set_lights(sectors, [center_light], env, sun)

func _build_maitre() -> void:
	maitre = ClientNpc.create(self, REVIEW_START, 0.0)
	review = ReviewScript.new()
	review.name = "Review"
	add_child(review)
	review.setup(self, maitre)

func _build_hall() -> void:
	# центральная колонна с отметкой «вода до столов»
	var col := Kit.block(self, Vector3(0, 4.0, 0), Vector3(0.9, 8.0, 0.9), Kit.mat(Color("d9d2bf"), 0.4))
	col.rotation.y = PI / 4
	var mark := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.96, 0.05, 0.96)
	mark.mesh = bm
	mark.material_override = Kit.mat(Color("c8302a"), 0.5)
	mark.position = Vector3(0, TABLE_H, 0)
	mark.rotation.y = PI / 4
	add_child(mark)
	for s in [0.0, PI / 2, PI, PI * 1.5]:
		Kit.sign(self, Vector3(sin(s) * 0.68, TABLE_H + 0.18, cos(s) * 0.68), "вода до сюда — конец", s, 28)
	Kit.sign(self, Vector3(0, 3.3, 0.7), "«ГЛУБОКАЯ ТАРЕЛКА»\nресторан на дне", 0.0, 64)
	center_light = OmniLight3D.new()
	center_light.position = Vector3(0, 3.6, 0)
	center_light.light_color = Color("ffd9a0")
	center_light.light_energy = 1.4
	center_light.omni_range = 9.0
	add_child(center_light)

	# столы банкета: стулья, тарелки, еда — всё физическое
	for t in 6:
		var a := t * TAU / 6.0 + PI / 6.0
		var c := Vector3(cos(a) * 5.6, 0, sin(a) * 5.6)
		var table := Kit.model_prop(self, "res://assets/furniture/tableRound.glb", c, 2.1, 30.0, a)
		table.set_meta("float", 0.3)
		Kit.model(self, "res://assets/furniture/rugRound.glb", c + Vector3(0, 0.005, 0), 2.2, a)
		var top := Kit.model_aabb(table.get_child(0)).size.y
		var rec := {"body": table, "center": c, "top": top, "food": 0, "dish": 1, "sector": t / 2}
		tables.append(rec)
		for s in 3:
			var ca := a + s * TAU / 3.0 + 0.5
			var cp := c + Vector3(cos(ca), 0, sin(ca)) * 1.15
			var chair := Kit.model_prop(self, "res://assets/furniture/chairCushion.glb", cp, 2.0, 6.0, -ca - PI / 2)
			chair.set_meta("float", 2.5)
			chair.add_to_group("chair")
			var pp := c + Vector3(cos(ca), 0, sin(ca)) * 0.42 + Vector3.UP * top
			var plate := Kit.model_prop(self, "res://assets/food/plate.glb", pp, 0.3, 0.5)
			plate.set_meta("float", 2.2)
			plate.add_to_group("dish")
			rec["dish"] += 1
			if (t + s) % 2 == 0:
				var f: Array = FOOD[(t * 3 + s) % FOOD.size()]
				var food := Kit.model_prop(self, f[0], pp + Vector3.UP * 0.03, f[1], f[2], ca)
				food.set_meta("float", 1.5)
				food.add_to_group("food")
				rec["food"] += 1
		var bottle := Kit.model_prop(self, "res://assets/food/wine-red.glb", c + Vector3.UP * top, 0.35, 0.8)
		bottle.set_meta("float", 1.2)
		bottle.add_to_group("dish")
		var lamp := OmniLight3D.new()
		lamp.position = c + Vector3(0, 2.2, 0)
		lamp.light_color = Color("ffcf8a")
		lamp.light_energy = 0.9
		lamp.omni_range = 3.5
		add_child(lamp)
		table_lamps.append(lamp)
	# растения в кадках у стекла
	for i in 8:
		var a := i * TAU / 8.0 + 0.4
		if absf(angle_difference(a, DOOR_ANGLE)) < 0.5 or absf(angle_difference(a, -PI / 2 - 0.4)) < 0.3:
			continue   # проём шлюза и насосная
		var p := Kit.model_prop(self, "res://assets/furniture/pottedPlant.glb", Vector3(cos(a), 0, sin(a)) * (R - 0.8), 2.0, 12.0)
		p.set_meta("float", 0.4)
