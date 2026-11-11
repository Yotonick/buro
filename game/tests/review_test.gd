extends Node
## Автотест приёмки метрдотелем в «Глубокой тарелке» (без экрана):
##   godot --headless --path game --fixed-fps 60 --disable-render-loop res://tests/review_test.tscn
## Метрдотель ускорен (шаг и паузы), иначе обход идёт ~1.5 минуты.

var lvl: Node3D
var fails := 0

func _ready() -> void:
	await _push()
	await _clean()
	await _mess()
	await _leaks()
	await _rude()
	await _flood()
	print("RESULT ", "PASS" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit(fails)

func _load() -> void:
	if lvl != null:
		lvl.queue_free()
		await get_tree().physics_frame
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	lvl._next_leak = 99999.0
	lvl.board._next_surge = 99999.0
	lvl.maitre.speed = 7.0
	lvl.review.pace = 0.25
	lvl.player.teleport(Vector3(-3.0, 1.0, -1.0))   # на скорости 7 м/с он бы снёс игрока в шлюзе
	await _wait(0.5)

func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await get_tree().physics_frame

func _check(name: String, ok: bool, info := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, info])
	if not ok:
		fails += 1

func _end_shift() -> void:
	lvl.shift.time = lvl.SHIFT_LEN + 1.0
	await _wait(0.3)

## Ждать, пока приёмка не закончится (не дольше sec).
func _until_done(sec: float) -> void:
	for i in int(sec * 4.0):
		if lvl.shift.phase != 3:
			return
		await _wait(0.25)

func _spot(leak: Node3D, side: float, up: float) -> Vector3:
	var t: Vector3 = leak.inward().cross(Vector3.UP)
	return leak.global_position + t * side + Vector3.UP * up

func _patch(leak: Node3D, n: int) -> void:
	for i in n:
		var a := _spot(leak, -0.3, 0.12 * (i - (n - 1) / 2.0))
		var b := _spot(leak, 0.3, -0.12 * (i - (n - 1) / 2.0))
		lvl.world.spawn("tape", {"a": 0, "la": a, "na": leak.inward(), "b": 0, "lb": b, "nb": leak.inward(), "rest": a.distance_to(b)})

func _said(part: String) -> bool:
	for s in lvl.review.said:
		if part in s:
			return true
	return false

# 0. Обычный шаг: игрок стоит в шлюзе у него на пути — отодвигает, без штрафа.
func _push() -> void:
	await _load()
	var k: Kombez = lvl.player
	var m: Node3D = lvl.maitre
	m.speed = m.SPEED
	k.teleport(Vector3(0.1, 1.0, lvl.R + 2.0))
	await _wait(1.0)
	var kp := k.global_position
	await _end_shift()
	await _wait(5.0)
	_check("игрока на пути отодвинул и прошёл в зал", m.global_position.z < lvl.R + 0.5 and k.global_position.distance_to(kp) > 0.3,
		"он %s, игрок сдвинут на %.2f м" % [m.global_position, k.global_position.distance_to(kp)])
	_check("за толкотню в шлюзе штрафа нет", lvl.review._cat.is_empty() and not k.is_ko(), str(lvl.review._cat))

# 1. Всё чисто: обходит все 6 столов, возвращается, 5 звёзд.
func _clean() -> void:
	await _load()
	var m: Node3D = lvl.maitre
	_check("до конца смены метрдотеля не видно и он ни с чем не сталкивается",
		not m.active and not m.visible and m.collision_layer == 0)
	await _end_shift()
	_check("смена кончилась — приёмка, метрдотель вышел", lvl.shift.reviewing() and m.active and m.collision_layer == 16)
	_check("вышел из глубины шлюза", absf(m.global_position.x) < 0.3 and m.global_position.z > lvl.R + 1.0, str(m.global_position))
	await _wait(1.5)
	_check("вошёл из шлюза в зал", Vector2(m.global_position.x, m.global_position.z).length() < lvl.R,
		str(m.global_position))
	var far := 0.0
	var angles := {}
	for i in 200:
		if lvl.shift.phase != 3:
			break
		var p: Vector3 = m.global_position
		far = maxf(far, Vector2(p.x, p.z).length())
		angles[int(fposmod(atan2(p.z, p.x), TAU) / (TAU / 8.0))] = true
		await _wait(0.25)
	_check("обошёл зал по кругу (все 8 сторон) и не вышел за стекло", angles.size() == 8 and far < lvl.R, "сторон %d, дальше всего %.2f" % [angles.size(), far])
	_check("приёмка закончилась победой", lvl.shift.phase == 1, lvl.hud.banner_text())
	_check("осмотрел 6 столов, всё на месте — 5 звёзд", lvl.review.stars() == 5 and lvl.hud.banner_stars() == 5,
		"звёзд %d, сказал: %s" % [lvl.review.stars(), " | ".join(lvl.review.said)])
	var e: Vector3 = lvl.review._entry()
	_check("вернулся к шлюзу", m.global_position.distance_to(e) < 1.0, str(m.global_position))
	_check("реплики видны в строке интерфейса", lvl.hud.line_text().begins_with("Метрдотель"), lvl.hud.line_text())

# 2. Бардак: еда на полу, стул упал, темно, вода — звёзд меньше, жалобы по делу.
func _mess() -> void:
	await _load()
	var t0: Dictionary = lvl.tables[0]
	var c0: Vector3 = (t0["body"] as Node3D).global_position
	var moved := 0
	for f in get_tree().get_nodes_in_group("food"):
		var fb := f as RigidBody3D
		if Vector2(fb.global_position.x - c0.x, fb.global_position.z - c0.z).length() < 1.0:
			fb.global_position = c0 * 0.4 + Vector3.UP * 0.3   # на пол ближе к колонне
			moved += 1
	var t3: Dictionary = lvl.tables[3]
	var c3: Vector3 = (t3["body"] as Node3D).global_position
	for ch in get_tree().get_nodes_in_group("chair"):
		var cb := ch as RigidBody3D
		if Vector2(cb.global_position.x - c3.x, cb.global_position.z - c3.z).length() < 1.9:
			cb.global_transform = Transform3D(Basis(Vector3.RIGHT, PI / 2), cb.global_position + Vector3.UP * 0.2)   # на боку
			break
	var b: Node3D = lvl.board
	b.warn_sector = 1
	b.surge()   # пробка сектора 1 вылетает, рубильник падает — темно везде
	await _wait(1.0)
	lvl.flood.level = 0.2
	await _end_shift()
	await _until_done(120.0)
	var cat: Dictionary = lvl.review._cat
	_check("убрали еду со стола 1 — заметил пропажу", moved > 0 and float(cat.get("еда", 0.0)) >= 0.3 * moved, "блюд %d, %s" % [moved, str(cat)])
	_check("стул на боку — заметил", float(cat.get("мебель", 0.0)) >= 0.1, str(cat))
	_check("свет не горит — ругается у каждого стола", float(cat.get("свет", 0.0)) >= 0.4 * 6 - 0.01, str(cat))
	_check("вода по щиколотку — штраф в конце", float(cat.get("вода", 0.0)) >= 0.9, str(cat))
	_check("итог плохой (≤ 1 звезды) и есть «больше всего не понравилось»",
		lvl.shift.phase == 1 and lvl.review.stars() <= 1 and "не понравилось" in lvl.hud.banner_text(),
		"звёзд %d: %s" % [lvl.review.stars(), lvl.hud.banner_text()])

# 3. Течи: хлипкая заплатка отклеивается от стука и окатывает его, крепкая держит.
func _leaks() -> void:
	await _load()
	lvl.review.peel_three = 1.0
	var weak: Node3D = lvl.leaks[0]
	var strong: Node3D = lvl.leaks[6]
	weak.burst()
	strong.burst()
	_patch(weak, 3)
	_patch(strong, 5)
	await _wait(0.5)
	_check("обе течи заделаны (3 и 5 полосок)", weak.flow() == 0.0 and strong.flow() == 0.0)
	await _end_shift()
	var stops: Array = lvl.review._stops.filter(func(s): return s["kind"] == "leak")
	_check("в обходе есть обе заделанные течи", stops.size() == 2)
	await _until_done(120.0)
	_check("от стука отклеилась полоска — сочится", weak.crossing_tapes().size() == 2 and weak.flow() > 0.0,
		"полосок %d" % weak.crossing_tapes().size())
	_check("крепкая (5 полосок) не отклеилась", strong.crossing_tapes().size() == 5 and strong.flow() == 0.0)
	_check("за развалившуюся заплатку — штраф и жалоба", float(lvl.review._cat.get("течи", 0.0)) >= 0.3 and _said("Сочится"),
		" | ".join(lvl.review.said))
	_check("про крепкую — «крепко»", _said("Крепко"))
	_check("за отклеившуюся заплатку уже не 5 звёзд", lvl.review.stars() <= 4, "звёзд %d" % lvl.review.stars())

# 4. Хамство: кинули тарелкой, примотали к стулу.
func _rude() -> void:
	await _load()
	await _end_shift()
	for i in 200:   # кидаем, когда стоит у стола
		if lvl.review._step == "look":
			break
		await get_tree().physics_frame
	var m: Node3D = lvl.maitre
	var plate: RigidBody3D = get_tree().get_nodes_in_group("dish")[0]
	var at: Vector3 = m.global_position + Vector3.UP * 1.3
	plate.global_position = at + Vector3(1.2, 0, 0)
	plate.linear_velocity = Vector3(-9.0, 0, 0)
	await _wait(0.4)
	_check("попали тарелкой — заметил", float(lvl.review._cat.get("хамство", 0.0)) >= 0.4, " | ".join(lvl.review.said))
	var chair: RigidBody3D = get_tree().get_nodes_in_group("chair")[0]
	var w: Node = lvl.world
	var lc: Vector3 = Vector3.ZERO
	var lm: Vector3 = Vector3(0, 1.0, 0)
	w.spawn("tape", {"a": w.id_of(m), "la": lm, "na": Vector3.FORWARD, "b": w.id_of(chair), "lb": lc, "nb": Vector3.UP,
		"rest": (m.global_transform * lm).distance_to(chair.global_position)})
	await _wait(0.3)
	_check("примотали лентой — возмущён", _said("примотан") and float(lvl.review._cat.get("хамство", 0.0)) >= 1.0, str(lvl.review._cat))
	var cp := chair.global_position
	await _wait(2.0)
	_check("примотанный стул тащится за ним (или лента порвалась)", chair.global_position.distance_to(cp) > 0.5
		or get_tree().get_nodes_in_group("tape").is_empty(), "%.2f м" % chair.global_position.distance_to(cp))

# 5. Затопило прямо при нём — провал, обход останавливается.
func _flood() -> void:
	await _load()
	await _end_shift()
	await _wait(1.0)
	lvl.flood.level = lvl.TABLE_H + 0.01
	await _wait(0.5)
	_check("вода до столов во время приёмки — провал", lvl.shift.phase == 2 and not lvl.review.running, lvl.hud.banner_text())
	lvl.queue_free()
	await get_tree().physics_frame
