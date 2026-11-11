extends Node
## Автотест шага 2 визуала: таблички, всплывающие подсказки, советы-стикеры, пузырь, имена (без экрана):
##   godot --headless --path game --fixed-fps 60 --disable-render-loop res://tests/prompt_test.tscn

const Prompts := preload("res://ui/world_prompts.gd")

var lvl: Node3D
var k: Kombez
var fails := 0

func _ready() -> void:
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	lvl._next_leak = 99999.0
	lvl.board._next_surge = 99999.0
	k = lvl.player
	await _wait(0.5)

	_check("в уровне нет летающих надписей (весь текст — на табличках и экранах)", _floating_labels() == 0, str(_floating_labels()))
	_check("в начале смены — совет-стикер", lvl.hud.tips_shown().size() >= 1, str(lvl.hud.tips_shown()))

	# смотрим на рулон в шлюзе
	var roll: Node3D = get_tree().get_nodes_in_group("tape_roll")[0]
	await _look(Vector3(roll.global_position.x, 1.0, roll.global_position.z - 1.3), roll.global_position + Vector3.UP * 0.04)
	_check("на рулон смотришь — «[E] на пояс»", _has("на пояс"), str(Prompts.gather(k)) + " " + _ray())
	_check("плашка подсказки появилась у прицела", lvl.hud.prompts.rows.size() > 0 and _rows_text().contains("на пояс"), _rows_text())
	k.use()
	await _wait(0.3)
	_check("рулон на поясе", roll.holder == k)

	# течь рядом
	var lk = lvl.leaks[0]
	lk.burst()
	await _look(lk.global_position + lk.inward() * 1.5 + Vector3.DOWN * 0.4, lk.global_position + lk.inward() * 0.02)
	await _wait(0.3)
	var rows := _rows_text()
	_check("у течи — «прижми» / «заклей»", rows.contains("прижми") or rows.contains("заклей") or rows.contains("приклеить"), rows)
	_check("рулон на поясе и смотришь на стекло у течи — «приклеить конец»", _has("приклеить конец"), str(Prompts.gather(k)))
	await _wait(1.0)
	_check("совет про течь поставлен в очередь или показан", lvl.hud._seen_tips.has("leak"))

	# выключили подсказки — пусто
	Settings.show_hints = false
	await _wait(0.4)
	_check("подсказки выключены — плашек нет", lvl.hud.prompts.rows.is_empty())
	Settings.show_hints = true

	# щиток: смотришь на вылетевшую пробку
	var b = lvl.board
	b.surge()
	await _wait(3.5)
	var lost := -1
	for i in 3:
		if not b.fuse_in[i]:
			lost = i
	_check("скачок выбил пробку", lost >= 0)
	if lost >= 0:
		var fz: Node3D = b.fuses[lost]
		fz.global_position = Vector3(-3.5, 0.1, 2.0)   # куда бы ни улетела — кладём на видное место
		fz.linear_velocity = Vector3.ZERO
		await _wait(0.5)
		var fp: Vector3 = fz.global_position
		var away := Vector3(fp.x, 0, fp.z).normalized() * -1.3
		await _look(Vector3(fp.x + away.x, 1.0, fp.z + away.z), fp)
		_check("на пробку смотришь — «в пустое гнездо»", _has("гнезду"), str(Prompts.gather(k)) + " " + _ray() + " fuse " + str(fz.global_position))

	# пузырь метрдотеля
	var m = lvl.maitre
	m.active = true
	m._apply_active()
	m.teleport(Vector3(2.5, 0, 4.5), 0.0)
	await _look(Vector3(0.5, 1, 8.0), Vector3(2.5, 1.8, 4.5))
	m.say("Проверка пузыря", "snob")
	await _wait(0.3)
	_check("реплика — пузырь над метрдотелем", lvl.hud.overlay.bubble_visible())
	_check("строка внизу спрятана, пока пузырь виден", lvl.hud.line_hidden and lvl.hud.line_text().contains("Проверка"))
	await _look(Vector3(0.5, 1, 8.0), Vector3(-6, 1.6, 8.0))
	m.say("А теперь сзади", "snob")
	await _wait(0.3)
	_check("метрдотель вне экрана — строка внизу", not lvl.hud.overlay.bubble_visible() and not lvl.hud.line_hidden)

	# имя напарника (подделываем второго игрока из стажёра)
	var mate: Kombez = Kombez.new()
	mate.peer_id = 9
	mate.player_name = "Петя"
	mate.position = Vector3(0, 1, 5.5)
	lvl.add_child(mate)
	await _look(Vector3(0, 1, 9.0), Vector3(0, 1.4, 5.5))
	await _wait(0.5)
	_check("смотришь на напарника — плашка с именем", lvl.hud.overlay.tag_visible(mate))
	await _look(Vector3(0, 1, 9.0), Vector3(-8, 1.4, 9.0))
	mate.teleport(Vector3(-6, 1, -6))
	await _wait(0.8)
	_check("далеко и не смотришь — имя спрятано", not lvl.hud.overlay.tag_visible(mate))

	print("RESULT ", "PASS" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit(fails)

func _floating_labels() -> int:
	var n := 0
	for l in lvl.find_children("*", "Label3D", true, false):
		var p: Node = l.get_parent()
		if p == null or not p.has_meta("plaque"):
			n += 1
			print("  летающая надпись: ", l.get_path(), " «", l.text, "»")
	return n

func _look(from: Vector3, target: Vector3) -> void:
	k.teleport(from)
	await _wait(0.15)
	var d: Vector3 = target - k.aim_origin()
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	k.in_aim_yaw = yaw
	k.in_aim_pitch = pitch
	lvl.camera.yaw = yaw
	lvl.camera.pitch = pitch
	lvl.camera.snap()
	await _wait(0.3)

func _ray() -> String:
	var q := PhysicsRayQueryParameters3D.create(k.aim_origin(), k.aim_origin() + k.aim_dir() * 3.0, 1 | 2 | 4 | 16)
	q.exclude = [k.get_rid(), k.hand_l.get_rid(), k.hand_r.get_rid()]
	var hit := k.get_world_3d().direct_space_state.intersect_ray(q)
	return "луч: " + ("мимо" if hit.is_empty() else "%s %s" % [hit["collider"], hit["position"]]) + " от " + str(k.aim_origin())

func _has(text: String) -> bool:
	for r in Prompts.gather(k):
		if str(r[1]).contains(text):
			return true
	return false

func _rows_text() -> String:
	var s := ""
	for r in lvl.hud.prompts.rows:
		s += str(r[1]) + "; "
	return s

func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await get_tree().physics_frame

func _check(name: String, ok: bool, info := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, info])
	if not ok:
		fails += 1
