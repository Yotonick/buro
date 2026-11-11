extends Node3D
## Вода в зале: общий уровень, который поднимают все течи сразу.
## Это и есть таймер смены без цифр: дошла вода до столов — ресторан затопило.
##
## Хост считает уровень и выталкивает предметы (лёгкое всплывает, тяжёлое тонет,
## в воде всё вязнет), клиенты получают уровень и скорость подъёма и двигают
## картинку сами между обновлениями.

const RISE := 0.0045           ## м/с подъёма от одной открытой течи
const SYNC_EVERY := 0.5
const G := 9.8

var radius := 9.9
var level := 0.0               ## высота воды над полом
var rate := 0.0                ## м/с, сейчас
var floor_y := 0.0

var _world: Node
var _surface: MeshInstance3D
var _mat: StandardMaterial3D
var _sync_t := 0.0

func _ready() -> void:
	add_to_group("flood")
	_world = get_tree().get_first_node_in_group("net_world")
	_surface = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 1.0
	cm.radial_segments = 48
	cm.rings = 1
	_surface.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.42, 0.55, 0.2)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_surface.material_override = m
	_mat = m
	_surface.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface)
	_show()

## Поставить скорость подъёма: total — сумма течей, drain — сколько откачивает насос (м/с). Только хост.
func set_flow(total: float, drain := 0.0) -> void:
	rate = total * RISE - (drain if level > 0.0 else 0.0)

func net_state(d: Dictionary) -> void:
	level = float(d.get("l", level))
	rate = float(d.get("r", rate))
	_show()

func _physics_process(dt: float) -> void:
	level = maxf(level + rate * dt, 0.0)
	if _world == null or not _world.is_authority():
		return
	_sync_t += dt
	if _sync_t >= SYNC_EVERY:
		_sync_t = 0.0
		_world.sync_state(self, {"l": level, "r": rate})
	if level > 0.01:
		_buoyancy()

func _process(_dt: float) -> void:
	_show()

func _show() -> void:
	_surface.visible = level > 0.005
	_surface.scale = Vector3(1, maxf(level, 0.005), 1)
	_surface.position = Vector3(0, floor_y + level * 0.5, 0)
	_mat.albedo_color.a = clampf(0.18 + level * 0.8, 0.18, 0.6)   # мелкая вода — почти прозрачная

## Насколько тело в воде: 0..1.
func depth_of(body: Node3D) -> float:
	var half: float = body.get_meta("half", 0.15)
	var bottom := body.global_position.y - half
	return clampf((floor_y + level - bottom) / (half * 2.0), 0.0, 1.0)

func _buoyancy() -> void:
	for c in get_parent().get_children():
		var rb := c as RigidBody3D
		if rb == null or rb.freeze:
			continue
		var flat := Vector2(rb.global_position.x, rb.global_position.z)
		if flat.length() > radius + 0.5:
			continue   # шлюз и коридор не затапливает
		var f := depth_of(rb)
		if f <= 0.0:
			continue
		var lift: float = rb.get_meta("float", 0.7)
		if rb.sleeping:
			rb.sleeping = false
		rb.apply_central_force(Vector3.UP * f * lift * rb.mass * G - rb.linear_velocity * f * rb.mass * 1.6)
