extends RigidBody3D
## Рулон изоленты — главный инструмент Бюро.
## Возьми в руку, поднеси к чему-нибудь и нажми «использовать» (E): конец ленты прилипнет.
## Донеси рулон до второго предмета (или стены) и нажми ещё раз — лента натянется между ними.
## Нажал в пустоту или отошёл слишком далеко — конец отрывается. Рулон не бесконечный.

const Tape := preload("res://physics/tape.gd")

const LENGTH := 15.0           ## метров ленты в новом рулоне
const MAX_SPAN := 6.0          ## дальше одним куском не тянется
const AIM_REACH := 3.0       ## с пояса лента достаёт на столько по взгляду игрока
const REACH := 0.7             ## на таком расстоянии от рулона лента «достаёт» до поверхности
const MIN_PIECE := 0.3         ## меньше на один кусок не тратится
const MIN_PATCH := 0.15        ## заплатка по стене/стеклу (оба конца на неподвижном) — не короче
const R_FULL := 0.115
const R_CORE := 0.06

var left := LENGTH
var puppet := false
var end_on := false            ## конец ленты уже прилеплен, тянем ко второму предмету
var end_id := 0                ## к чему: номер тела в NetWorld, 0 — неподвижный мир
var end_local := Vector3.ZERO
var end_normal := Vector3.UP
var holder: Kombez             ## у кого рулон висит на поясе (только хост)
var holder_id := 0             ## то же номером в NetWorld — знают все

var _world: Node
var _strip: MeshInstance3D
var _patch: MeshInstance3D
var _ring: MeshInstance3D
var _mark: MeshInstance3D      ## подсказка «сюда прилипнет» — видит только тот, у кого рулон на поясе

static func create(_params: Dictionary) -> RigidBody3D:
	return load("res://tools/tape_roll.gd").new()

func set_puppet(v: bool) -> void:
	puppet = v
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = v

func _ready() -> void:
	add_to_group("tape_roll")
	add_to_group("tool")
	_world = get_tree().get_first_node_in_group("net_world")
	mass = 0.6
	collision_layer = 2
	collision_mask = 1 | 2 | 4 | 8
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = R_FULL
	sh.height = 0.07
	cs.shape = sh
	add_child(cs)
	_ring = _cyl(1.0, 0.06, Tape.COLOR, 0.45)
	_cyl(R_CORE, 0.066, Color("c9a26b"), 0.9)
	_cyl(R_CORE - 0.012, 0.07, Color("3a2f25"), 0.9)
	_strip = Tape.make_strip(self)
	_patch = Tape.make_strip(self)
	_mark = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.05
	tm.outer_radius = 0.075
	tm.rings = 20
	tm.ring_segments = 6
	_mark.mesh = tm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color("ffe14a")
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark.material_override = mm
	_mark.top_level = true
	_mark.visible = false
	_mark.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_mark)
	_refresh()

## Повесить на пояс: руки свободны, рулон ездит на боку. Только хост.
func attach_to(k: Kombez) -> void:
	if puppet or holder != null:
		return
	for other in get_tree().get_nodes_in_group("kombez"):
		for h in [other.hand_l, other.hand_r]:
			if h.held == self:
				h.release()
	holder = k
	k.tool = self
	holder_id = _world.id_of(k) if _world != null else 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	global_transform = k.belt_global()
	reset_physics_interpolation()
	_sync()

## Снять с пояса; toss — бросить вперёд.
func detach(toss := false) -> void:
	if holder_id == 0:
		return
	var k: Kombez = holder if is_instance_valid(holder) else null
	holder = null
	holder_id = 0
	collision_layer = 2
	collision_mask = 1 | 2 | 4 | 8
	freeze = false
	if k != null:
		if k.tool == self:
			k.tool = null
		var fwd := Basis(Vector3.UP, k.in_aim_yaw) * Vector3.FORWARD
		global_position = k.global_position + fwd * 0.6 + Vector3.UP * 0.25
		linear_velocity = k.linear_velocity + (fwd * 2.2 + Vector3.UP * 1.8 if toss else Vector3.ZERO)
		reset_physics_interpolation()
	_sync()

## Подсказка, когда на рулон смотрят (лежит или в чужой руке).
func prompt_hint(_k: Node, dist: float) -> Array:
	if holder_id != 0 or dist > AIM_REACH:
		return []
	return [["use", "на пояс"], [["grab_left", "grab_right"], "взять в руку", true]]

## Подсказка своему игроку, пока рулон у него на поясе (колечко считается в _process).
func belt_hint(k: Node) -> Array:
	if holder_id == 0 or _world == null or _world.node_of(holder_id) != k:
		return []
	if left < 0.05:
		return [["drop_tool", "рулон кончился — бросить"]]
	if _mark.visible:
		return [["use", "примотать сюда" if end_on else "приклеить конец"]]
	if end_on:
		return [["", "тяни ленту ко второму предмету (до %d м)" % int(minf(MAX_SPAN, left))]]
	return []

func _cyl(radius: float, height: float, color: Color, rough: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 24
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	mi.material_override = m
	add_child(mi)
	return mi

## Сколько ленты осталось — видно по толщине рулона.
func _refresh() -> void:
	var r := lerpf(R_CORE + 0.008, R_FULL, clampf(left / LENGTH, 0.0, 1.0))
	_ring.scale = Vector3(r, 1.0, r)
	_ring.visible = left > 0.05

## Инструментом пользуются: user — Комбез, hand — рука, которая держит рулон. Только хост.
func use_tool(user: Kombez, hand: Node3D) -> void:
	if puppet or _world == null or left < 0.05:
		return
	var hit := _find_surface(user, hand)
	if hit.is_empty():
		if end_on:   # нажали в пустоту — конец оторвали
			end_on = false
			_sync()
		return
	var body: Node3D = hit["collider"]
	var id: int = _world.id_of(body)
	if id == 0 and not body is StaticBody3D:
		return   # что-то, чего нет в общем мире (чужая рука и т.п.)
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var local := point
	var local_n := normal
	if id != 0:
		local = body.global_transform.affine_inverse() * point
		local_n = body.global_basis.inverse() * normal
	if not end_on:
		end_on = true
		end_id = id
		end_local = local
		end_normal = local_n
	else:
		var from: Vector3 = Tape.anchor(_end_body(), end_local, end_normal, false)[0]
		var span := from.distance_to(point)
		if id == end_id and (id != 0 or span < MIN_PATCH):
			return   # оба конца на одном предмете — так ничего не скрепить (по стене можно: это заплатка)
		_world.spawn("tape", {"a": end_id, "la": end_local, "na": end_normal,
			"b": id, "lb": local, "nb": local_n, "rest": maxf(span, 0.05)})
		left = maxf(left - maxf(span, MIN_PIECE), 0.0)
		end_on = false
	_sync()

func _end_body() -> Node3D:
	if end_id == 0 or _world == null:
		return null
	var n: Node3D = _world.node_of(end_id)
	return n if is_instance_valid(n) else null

## Ближайшая поверхность, до которой дотягивается рулон: сначала по направлению руки,
## потом — просто то, во что рулон упёрт.
func _find_surface(user: Kombez, hand: Node3D) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid(), user.get_rid(), user.hand_l.get_rid(), user.hand_r.get_rid()]
	if hand == null:   # рулон на поясе: клеим туда, куда смотрит игрок
		var aq := PhysicsRayQueryParameters3D.create(user.aim_origin(), user.aim_origin() + user.aim_dir() * AIM_REACH, 1 | 2 | 4 | 16)
		aq.exclude = exclude
		return space.intersect_ray(aq)
	var from: Vector3 = user.shoulder_global(hand.side)
	var dir := global_position - from
	dir = dir.normalized() if dir.length() > 0.05 else -user.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(global_position - dir * 0.2, global_position + dir * REACH, 1 | 2 | 4 | 16)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit
	var sq := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.45
	sq.shape = sph
	sq.transform = Transform3D(Basis.IDENTITY, global_position)
	sq.collision_mask = 1 | 2 | 4 | 16
	sq.exclude = exclude
	var rest := space.get_rest_info(sq)
	if rest.is_empty():
		return {}
	return {"collider": instance_from_id(rest["collider_id"]), "position": rest["point"], "normal": rest["normal"]}

func _sync() -> void:
	_refresh()
	_world.sync_state(self, {"left": left, "on": end_on, "id": end_id, "p": end_local, "n": end_normal, "who": holder_id})

## Состояние от хоста (у клиентов).
func net_state(d: Dictionary) -> void:
	left = float(d.get("left", left))
	end_on = bool(d.get("on", false))
	end_id = int(d.get("id", 0))
	end_local = d.get("p", Vector3.ZERO)
	end_normal = d.get("n", Vector3.UP)
	holder_id = int(d.get("who", 0))
	_refresh()

func _physics_process(_dt: float) -> void:
	if puppet:
		return
	if holder_id != 0:
		if not is_instance_valid(holder):
			detach()
		else:
			global_transform = holder.belt_global()
	if not end_on:
		return
	if end_id != 0 and _end_body() == null:
		end_on = false
		_sync()
		return
	var from: Vector3 = Tape.anchor(_end_body(), end_local, end_normal, false)[0]
	if from.distance_to(global_position) > minf(MAX_SPAN, left):
		end_on = false   # ленты не хватило — конец оторвался
		_sync()

func _process(_dt: float) -> void:
	_update_mark()
	var body := _end_body()
	if not end_on or (end_id != 0 and body == null):
		_strip.visible = false
		_patch.visible = false
		return
	var e := Tape.anchor(body, end_local, end_normal, true)
	Tape.place_strip(_strip, e[0], get_global_transform_interpolated().origin)
	Tape.place_patch(_patch, e[0], e[1])

## Жёлтое колечко там, куда прилипнет лента, — только у того, кто носит этот рулон.
func _update_mark() -> void:
	_mark.visible = false
	if holder_id == 0 or _world == null or left < 0.05:
		return
	var k: Kombez = _world.local_kombez
	if k == null or not is_instance_valid(k) or _world.node_of(holder_id) != k or k.is_ko():
		return
	var hit := _find_surface(k, null)
	if hit.is_empty():
		return
	# пока конец не прилеплен, пол и стены не подсвечиваем — иначе колечко маячит под ногами всё время
	var hid: int = _world.id_of(hit["collider"])
	var hp: Vector3 = hit["position"]
	if not end_on and hid == 0 and not _hinted(hp):
		return
	if end_on and hid == end_id and hid != 0:
		return   # на тот же предмет второй конец не клеится
	var n: Vector3 = hit["normal"]
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
	_mark.global_transform = Transform3D(Basis.looking_at(n, up) * Basis(Vector3.RIGHT, -PI / 2), (hit["position"] as Vector3) + n * 0.015)
	_mark.visible = true

## Есть ли рядом что-то, что просит ленту (например, течь в стекле).
func _hinted(p: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group("tape_hint"):
		if n.wants_tape(p):
			return true
	return false
