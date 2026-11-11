extends Node
## Автотест «Глубокой тарелки»: течи, заделка, вода, итог смены (без экрана):
##   godot --headless --path game --fixed-fps 60 --disable-render-loop res://tests/leak_test.tscn

const Kit := preload("res://levels/level_kit.gd")
const LeakScript := preload("res://levels/deep_plate/leak.gd")
const S := LeakScript.S

var lvl: Node3D
var k: Kombez
var fails := 0

func _ready() -> void:
	await _part_a()
	await _part_b()
	print("RESULT ", "PASS" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit(fails)

func _load() -> void:
	if lvl != null:
		lvl.queue_free()
		await get_tree().physics_frame
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	k = lvl.player
	lvl._next_leak = 99999.0   # течи прорывает сам тест
	await _wait(0.5)

func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await get_tree().physics_frame

func _check(name: String, ok: bool, info := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, info])
	if not ok:
		fails += 1

func _spot(leak: Node3D, side: float, up: float) -> Vector3:
	var t: Vector3 = leak.inward().cross(Vector3.UP)
	return leak.global_position + t * side + Vector3.UP * up

func _patch(leak: Node3D, a: Vector3, b: Vector3) -> void:
	lvl.world.spawn("tape", {"a": 0, "la": a, "na": leak.inward(), "b": 0, "lb": b, "nb": leak.inward(), "rest": a.distance_to(b)})

func _part_a() -> void:
	await _load()
	var w: Node = lvl.world
	_check("течи на месте, все целы", lvl.leaks.size() >= 10 and lvl.leaks.all(func(l): return not l.is_burst()), "%d шт." % lvl.leaks.size())
	_check("в шлюзе 4 рулона и 8 заглушек", get_tree().get_nodes_in_group("tape_roll").size() == 4 and get_tree().get_nodes_in_group("plug").size() == 8)
	await _wait(2.0)
	_check("пока целы — воды нет", lvl.flood.level == 0.0)

	# 1. прорыв: вода пошла, струя толкает тарелку
	var leak: Node3D = lvl.leaks[0]
	var n: Vector3 = leak.inward()
	var plate := Kit.prop_box(lvl, leak.global_position + n * 0.8, Vector3(0.25, 0.25, 0.25), 0.5, Color.WHITE)
	plate.gravity_scale = 0.0
	w.track(plate)
	leak.burst()
	await _wait(1.0)
	_check("прорвало — течь открыта", leak.state == S.OPEN)
	_check("вода поднимается", lvl.flood.level > 0.003 and lvl.flood.rate > 0.0, "уровень %.3f, скорость %.4f" % [lvl.flood.level, lvl.flood.rate])
	var moved: float = (plate.global_position - leak.global_position).dot(n)
	_check("струя отбросила предмет от дыры", moved > 1.3, "%.2f м" % moved)
	plate.queue_free()

	# 2. заглушка: прижата — держит; отпустили — давлением выбило; примотали — держит
	var plug: RigidBody3D = get_tree().get_nodes_in_group("plug")[0]
	plug.global_transform = Transform3D(Basis.looking_at(n) * Basis(Vector3.RIGHT, PI / 2), leak.global_position + n * 0.035)
	plug.freeze = true
	await _wait(0.3)
	_check("прижатая заглушка затыкает дыру", leak.state == S.SEALED and leak.cover == plug)
	var lvl_before: float = lvl.flood.level
	await _wait(1.0)
	_check("пока заткнуто — вода не прибывает", absf(lvl.flood.level - lvl_before) < 0.0005)
	plug.freeze = false
	await _wait(1.5)
	_check("отпустили — давлением выбило", leak.state == S.OPEN, "заглушка в %.2f м от дыры" % plug.global_position.distance_to(leak.global_position))
	plug.global_transform = Transform3D(Basis.looking_at(n) * Basis(Vector3.RIGHT, PI / 2), leak.global_position + n * 0.035)
	plug.linear_velocity = Vector3.ZERO
	plug.angular_velocity = Vector3.ZERO
	plug.freeze = true
	await _wait(0.1)
	for side in [-1.0, 1.0]:
		var on_plug: Vector3 = plug.global_transform.affine_inverse() * (plug.global_position + leak.inward().cross(Vector3.UP) * side * 0.12)
		var on_wall: Vector3 = _spot(leak, side * 0.4, 0.0)
		w.spawn("tape", {"a": w.id_of(plug), "la": on_plug, "na": Vector3.UP, "b": 0, "lb": on_wall, "nb": n,
			"rest": (plug.global_transform * on_plug).distance_to(on_wall)})
	plug.freeze = false
	await _wait(3.0)
	_check("примотанная заглушка держится", leak.state == S.SEALED and leak.cover == plug, "заглушка в %.2f м от дыры" % plug.global_position.distance_to(leak.global_position))

	# 3. заплатка из ленты прямо по стеклу: 1 полоска — сочится, 3 — держит
	var l2: Node3D = lvl.leaks[2]
	l2.burst()
	await _wait(0.2)
	_patch(l2, _spot(l2, -0.3, 0.05), _spot(l2, 0.3, -0.05))
	await _wait(0.2)
	_check("одна полоска по дыре — сочится", l2.state == S.DRIP)
	_patch(l2, _spot(l2, -0.25, -0.25), _spot(l2, 0.25, 0.25))
	_patch(l2, _spot(l2, -0.25, 0.25), _spot(l2, 0.25, -0.25))
	await _wait(0.2)
	_check("три полоски крест-накрест — держит", l2.state == S.SEALED)

	# 4. по-настоящему: рулон на поясе, игрок клеит по стеклу туда, куда смотрит
	var l3: Node3D = lvl.leaks[4]
	l3.burst()
	var n3: Vector3 = l3.inward()
	var roll: RigidBody3D = get_tree().get_nodes_in_group("tape_roll")[0]
	k.teleport(Vector3(l3.global_position.x, 0.9, l3.global_position.z) + n3 * 1.3 + n3.cross(Vector3.UP) * 0.9)
	await _wait(0.6)
	roll.attach_to(k)
	var tapes_before := _tapes()
	for target in [_spot(l3, -0.35, -0.2), _spot(l3, 0.35, 0.2)]:
		_aim_at(target)
		await _wait(0.1)
		k.use()
		await _wait(0.1)
	_check("лента по стеклу с пояса — заплатка встала", _tapes() == tapes_before + 1 and l3.state == S.DRIP, "лент %d -> %d, течь %d" % [tapes_before, _tapes(), l3.state])

	# 5. вода выталкивает лёгкое, тяжёлое стоит
	var chair: RigidBody3D = null
	var table: RigidBody3D = null
	for c in lvl.get_children():
		if c is RigidBody3D and c.get_meta("float", 0.0) == 2.5 and chair == null:
			chair = c
		if c is RigidBody3D and c.mass == 30.0 and table == null:
			table = c
	var cy := chair.global_position.y
	var ty := table.global_position.y
	lvl.flood.level = 0.6
	await _wait(2.0)
	_check("стул всплыл", chair.global_position.y > cy + 0.15, "%.2f -> %.2f" % [cy, chair.global_position.y])
	_check("стол остался на полу", absf(table.global_position.y - ty) < 0.1)
	lvl.flood.level = 0.0
	lvl.flood.rate = 0.0

	# 6. смена отработана и всё заделано — справились
	for l in lvl.leaks:
		if l.is_burst() and l.flow() > 0.0:
			for i in 3:
				_patch(l, _spot(l, -0.3, 0.1 * (i - 1)), _spot(l, 0.3, -0.1 * (i - 1)))
	lvl.shift.time = lvl.SHIFT_LEN + 1.0
	await _wait(0.5)
	_check("смена окончена, всё заделано — началась приёмка", lvl.shift.reviewing() and lvl.maitre.active, lvl.hud.banner_text())
	lvl.maitre.speed = 12.0   # обход целиком проверяет review_test; здесь — только что смена закончится
	lvl.review.pace = 0.05
	for i in 60:
		if lvl.shift.phase != 3:
			break
		await _wait(0.5)
	_check("приёмка закончилась — успех со звёздами", lvl.shift.phase == 1 and lvl.hud.banner_stars() >= 0,
		"%s, звёзд %d" % [lvl.hud.banner_text(), lvl.hud.banner_stars()])

func _part_b() -> void:
	await _load()
	lvl.leaks[1].burst()
	lvl.flood.level = lvl.TABLE_H - 0.01
	await _wait(3.0)
	_check("вода дошла до столов — провал", lvl.shift.phase == 2, lvl.hud.banner_text())
	var t0: float = lvl.shift.time
	await _wait(0.5)
	_check("после итога течи больше не льют", lvl.flood.rate == 0.0 and lvl.shift.time == t0)
	lvl.queue_free()
	await get_tree().physics_frame

func _tapes() -> int:
	return get_tree().get_nodes_in_group("tape").filter(func(t): return not t.is_queued_for_deletion()).size()

## Развернуть взгляд игрока на точку.
func _aim_at(p: Vector3) -> void:
	var d := (p - k.aim_origin()).normalized()
	k.in_aim_yaw = atan2(-d.x, -d.z)
	k.in_aim_pitch = asin(clampf(d.y, -1.0, 1.0))
