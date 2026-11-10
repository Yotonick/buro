extends "res://levels/level_base.gd"
## Полигон: комната для обкатки Комбеза — ходьба, прыжки, хват, лазание, нокауты.
## Не игровая локация, а испытательный стенд студии.

const FLOOR_SHADER := preload("res://levels/test_room/floor.gdshader")

var carousel: AnimatableBody3D
var bag: RigidBody3D
var dummies: Array[Kombez] = []

func spawn_point(slot: int) -> Vector3:
	return Vector3((slot - 1.5) * 1.6 if Net.in_session() else 0.0, 1.0, 7)

func _build() -> void:
	_build_world()
	_build_playthings()
	hint = "WASD — идти   ·   Пробел — прыжок   ·   ЛКМ / ПКМ — левая / правая рука (держи)   ·   мышь вверх-вниз — поднять-опустить руки\nCtrl — присесть   ·   E — взять рулон на пояс, дальше E — клеить ленту туда, куда смотришь (жёлтое колечко): раз — конец, второй раз — примотал   ·   Q — бросить рулон\nF — упасть   ·   T — ржать   ·   R — вернуться на старт   ·   Esc — пауза"

func _tick(dt: float) -> void:
	carousel.rotate_y(1.5 * dt)
	for d in dummies:
		if d.global_position.y < -15.0:
			d.teleport(Vector3(4, 1, 2))

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("4a78a8")
	sm.sky_horizon_color = Color("b9d3e6")
	sm.ground_bottom_color = Color("2a3a48")
	sm.ground_horizon_color = Color("b9d3e6")
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	e.ambient_light_sky_contribution = 0.6
	e.ambient_light_color = Color("d8d2c8")
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color("fff3e0")
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)

	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = FLOOR_SHADER
	Kit.block(self, Vector3(0, -0.5, 0), Vector3(44, 1, 44), floor_mat)
	var wall := Kit.mat(Color("7d8c99"))
	for s in [-1.0, 1.0]:
		Kit.block(self, Vector3(s * 22.5, 2.5, 0), Vector3(1, 6, 46), wall)
		Kit.block(self, Vector3(0, 2.5, s * 22.5), Vector3(46, 6, 1), wall)

	var concrete := Kit.mat(Color("a9a294"))
	var accent := Kit.mat(Color("ef9f27"))
	# лестница -> площадка -> уступ -> вышка
	for i in 6:
		Kit.block(self, Vector3(-9, 0.12 + i * 0.24, 2.0 - i * 0.5), Vector3(2.6, 0.24, 0.5), concrete)
	Kit.block(self, Vector3(-9, 0.72, -3.0), Vector3(4, 1.44, 4), concrete)          # верх 1.44
	Kit.block(self, Vector3(-9, 1.2, -7.0), Vector3(4, 2.4, 4), concrete)            # верх 2.4
	Kit.block(self, Vector3(-9, 2.3, -11.0), Vector3(4, 4.6, 4), concrete)           # верх 4.6
	Kit.block(self, Vector3(-9, 4.65, -9.1), Vector3(4, 0.1, 0.2), accent)           # кромка — за неё цепляться
	Kit.sign(self, Vector3(-9, 5.6, -11.0), "ВЫШКА\nпадать больно", 0.0)
	# стенка для лазания
	Kit.block(self, Vector3(-2.5, 1.0, -8.0), Vector3(5, 2.0, 1.2), concrete)
	Kit.sign(self, Vector3(-2.5, 2.6, -8.0), "Залезь руками", 0.0, 48)
	# пандус
	Kit.block(self, Vector3(-15, 0.75, 4), Vector3(3, 0.3, 8), concrete, Vector3(deg_to_rad(12), 0, 0))
	Kit.sign(self, Vector3(0, 3.2, 2.5), "ПОЛИГОН БЮРО", 0.0, 96)

func _build_playthings() -> void:
	var wood := Color("c08a4e")
	for i in 6:
		Kit.prop_box(self, Vector3(5.0 + (i % 3) * 0.55, 0.26 + (i / 3) * 0.52, 3.0), Vector3.ONE * 0.5, 4.0, wood.lightened(0.1 * (i % 2)))
	Kit.prop_box(self, Vector3(8, 0.36, 4), Vector3.ONE * 0.7, 14.0, Color("8a6a3a"))
	Kit.prop_box(self, Vector3(9, 0.36, 5.2), Vector3.ONE * 0.7, 14.0, Color("8a6a3a"))
	Kit.prop_box(self, Vector3(11, 0.5, 2), Vector3.ONE, 70.0, Color("5b6570"))
	Kit.sign(self, Vector3(11, 1.5, 2), "70 кг", 0.0, 40)
	Kit.prop_box(self, Vector3(6, 0.1, 6.5), Vector3(3.0, 0.12, 0.4), 9.0, wood)
	for i in 3:
		Kit.prop_ball(self, Vector3(3.0 + i * 0.8, 0.4, 9.0), 0.3, 3.0, [Color("d85a30"), Color("1d9e75"), Color("ef9f27")][i])
	Kit.prop_cylinder(self, Vector3(8, 0.46, 8), 0.35, 0.9, 18.0, Color("2f6f9f"))

	# стол с изолентой: главный инструмент Бюро
	Kit.block(self, Vector3(-4.5, 0.4, 5.0), Vector3(2.2, 0.8, 0.8), Kit.mat(Color("6b4f34")))
	for i in 3:
		var roll: RigidBody3D = TapeRoll.create({})
		roll.position = Vector3(-5.2 + i * 0.7, 0.86, 5.0)
		add_child(roll)
	Kit.sign(self, Vector3(-4.5, 1.7, 5.0), "ИЗОЛЕНТА\nвозьми и жми E", 0.0, 48)

	# груша для битья: висит на шарнире, раскачай и получи
	var steel := Kit.mat(Color("5b6570"), 0.5)
	for s in [-1.0, 1.0]:
		Kit.block(self, Vector3(7.0 + s * 1.6, 1.8, -6), Vector3(0.25, 3.6, 0.25), steel)
	var beam := Kit.block(self, Vector3(7.0, 3.7, -6), Vector3(3.6, 0.25, 0.25), steel)
	bag = Kit.prop_cylinder(self, Vector3(7.0, 1.55, -6), 0.32, 1.3, 35.0, Color("a23b3b"))
	var chain := Kit.prop_cylinder(self, Vector3(7.0, 2.9, -6), 0.04, 1.3, 2.0, Color("333333"))
	_pin(beam, chain, Vector3(7.0, 3.55, -6))
	_pin(chain, bag, Vector3(7.0, 2.25, -6))
	Kit.sign(self, Vector3(7.0, 4.2, -6), "Груша. Бьёт в ответ", 0.0, 48)

	# карусель: вращающаяся балка, сбивает с ног
	Kit.block(self, Vector3(0, 0.45, -14), Vector3(0.5, 0.9, 0.5), steel)
	carousel = AnimatableBody3D.new()
	carousel.collision_layer = 1
	carousel.collision_mask = 0
	Kit._add_box(carousel, Vector3(7.0, 0.3, 0.3), Kit.mat(Color("d85a30")))
	carousel.position = Vector3(0, 1.05, -14)
	add_child(carousel)
	Kit.sign(self, Vector3(0, 2.4, -14), "Карусель дураков", 0.0, 48)

	# стажёры: их можно таскать за что попало и швырять
	var colors := [Color("9aa3ab"), Net.PLAYER_COLORS[2]]
	for i in 2:
		var d := Kombez.new()
		d.suit_color = colors[i]
		d.position = Vector3(3.0 + i * 1.6, 1.0, 1.0)
		d.rotation.y = PI
		add_child(d)
		dummies.append(d)
	Kit.sign(self, Vector3(3.8, 2.3, 1.0), "Стажёры", PI, 40)

func _pin(a: PhysicsBody3D, b: PhysicsBody3D, at: Vector3) -> void:
	var j := PinJoint3D.new()
	add_child(j)
	j.position = at
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
