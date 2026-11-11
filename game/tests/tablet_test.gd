extends Node
## Автотест шага 3 визуала: рабочий планшет (Tab) в «Глубокой тарелке» (без экрана):
##   godot --headless --path game --fixed-fps 60 --disable-render-loop res://tests/tablet_test.tscn

const Prompts := preload("res://ui/world_prompts.gd")
const PumpScript := preload("res://levels/deep_plate/pump.gd")

var lvl: Node3D
var k: Kombez
var tab: Control
var fails := 0

func _ready() -> void:
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl._next_leak = 99999.0
	lvl.board._next_surge = 99999.0
	k = lvl.player
	tab = lvl.hud.tablet
	await _wait(0.5)

	_check("действие «Планшет» есть в раскладке (Tab) и в настройках", InputMap.has_action("tablet")
		and Controls.title_of("tablet") == "Планшет" and Controls.codes("tablet")[0] == "key:%d" % KEY_TAB)
	_check("в начале — совет про планшет", lvl.hud._seen_tips.has("tablet"))
	_check("планшет закрыт", not tab.open and not tab.visible)

	# смотрим на рулон — подсказка есть; открыли планшет — пропала
	var roll: Node3D = get_tree().get_nodes_in_group("tape_roll")[0]
	await _look(Vector3(roll.global_position.x, 1.0, roll.global_position.z - 1.3), roll.global_position + Vector3.UP * 0.04)
	_check("до планшета у рулона — подсказка", lvl.hud.prompts.rows.size() > 0)
	_press("tablet")
	await _wait(0.5)
	_check("Tab — планшет открыт и выехал", tab.open and tab.visible and absf(tab._dev.position.y - tab._rest_y()) < 2.0, str(tab._dev.position))
	_check("руки заняты планшетом, ходить можно (walk_only)", lvl.controller.walk_only)
	_check("пока открыт — подсказок у прицела нет", lvl.hud.prompts.rows.is_empty())
	_check("мир не на паузе", not lvl.hud.is_paused() and not get_tree().paused)

	# вкладка «Заказ»
	var txt: String = tab.shown_text
	_check("«Заказ»: объект и заказчик", txt.contains("Глубокая тарелка") and txt.contains("метрдотель"), txt.left(160))
	_check("«Заказ»: чек-лист — смена, течи, вода, насос, свет", txt.contains("Продержаться смену") and txt.contains("Течи")
		and txt.contains("Вода в зале") and txt.contains("Насос: труба разорвана") and txt.contains("Свет: 3/3"), txt)
	_check("«Заказ»: место под оплату", txt.contains("Оплата"))
	lvl.leaks[0].burst()
	await _wait(0.6)
	_check("прорвало течь — «открыто 1» (галочка красная)", tab.shown_text.contains("Течи: открыто 1") and _state_of("Течи") == "bad", _items_dbg())
	lvl.flood.level = 0.2
	await _wait(0.6)
	_check("вода 20 см — в чек-листе", tab.shown_text.contains("Вода в зале: 20 см"), _items_dbg())
	lvl.flood.level = 0.0
	lvl.board.surge()
	await _wait(3.6)
	_check("скачок — «Свет: 2/3» или меньше, причина рядом", (tab.shown_text.contains("Свет: 2/3") or tab.shown_text.contains("Свет: 0/3"))
		and (tab.shown_text.contains("нет пробки") or tab.shown_text.contains("рубильник")), _items_dbg())
	var o: Dictionary = lvl.tablet_order()
	var t0 := str(o["items"][0]["note"])
	await _wait(2.0)
	_check("время смены в чек-листе идёт", str(lvl.tablet_order()["items"][0]["note"]) != t0, t0)

	# пока открыт — Комбез ходит (руками не хватает)
	await _look(Vector3(0, 1, 6.5), Vector3(0, 1, 0))
	var p0 := k.global_position
	Input.action_press("move_forward")
	Input.action_press("grab_left")
	await _wait(1.0)
	Input.action_release("move_forward")
	Input.action_release("grab_left")
	_check("с планшетом в руках ходит", Vector2(k.global_position.x - p0.x, k.global_position.z - p0.z).length() > 0.8,
		str(k.global_position - p0))
	_check("…а рука не хватает", not k.in_grab_l)

	# вкладка «Бригада»
	tab.set_tab(1)
	await _wait(0.4)
	txt = tab.shown_text
	_check("«Бригада»: свой Комбез, где он и «в строю»", txt.contains("это ты") and txt.contains("в строю")
		and (txt.contains("шлюз") or txt.contains("в зале")), txt)
	k.flop()
	await _wait(0.5)
	_check("нокаут — «в нокауте»", tab.shown_text.contains("в нокауте"), tab.shown_text)
	await _wait(3.0)
	lvl.flood.level = 0.5
	await _wait(0.6)
	_check("в воде — пишет", tab.shown_text.contains("воде") or tab.shown_text.contains("мочит"), tab.shown_text)
	lvl.flood.level = 0.0

	# «Управление» — из текущей раскладки
	tab.set_tab(2)
	await _wait(0.4)
	_check("«Управление»: все действия, в т.ч. планшет и Esc", tab.shown_text.contains("планшет") and tab.shown_text.contains("перекур")
		and tab.shown_text.contains("использовать"), tab.shown_text)
	var caps := tab.find_children("*", "Control", true, false).filter(func(c): return c.get("action") == "tablet")
	_check("колпачок клавиши планшета подписан «Tab»", not caps.is_empty() and KeyCap_label("tablet") == "Tab", KeyCap_label("tablet"))

	# «Заметки»
	tab.set_tab(3)
	await _wait(0.4)
	_check("«Заметки»: служебные записки (и от метрдотеля)", tab.shown_text.contains("Метрдотель — бюро") and tab.shown_text.count("вх.") == 4, tab.shown_text.left(200))

	# Esc закрывает планшет, а не открывает паузу
	_press("pause")
	await _wait(0.5)
	_check("Esc — планшет убран, паузы нет", not tab.open and not lvl.hud.is_paused() and not lvl.controller.walk_only)

	# переназначили — открывается новой клавишей
	var e := InputEventKey.new()
	e.physical_keycode = KEY_J
	Controls.set_binding("tablet", 0, e)
	_press_key(KEY_TAB)
	await _wait(0.3)
	_check("Tab переназначен на J — Tab больше не открывает", not tab.open)
	_press_key(KEY_J)
	await _wait(0.4)
	_check("J — открывает", tab.open)
	Controls.reset_action("tablet")

	# пауза поверх планшета
	lvl.hud.set_paused(true)
	await _wait(0.4)
	_check("пауза убирает планшет", not tab.open and lvl.hud.is_paused())
	_press("tablet")
	await _wait(0.3)
	_check("на паузе Tab не открывает", not tab.open)
	lvl.hud.set_paused(false)

	# приёмка: ход обхода в планшете
	for l in lvl.leaks:
		if l.is_burst():
			l.queue_free()
	lvl.leaks = lvl.leaks.filter(func(l): return is_instance_valid(l) and not l.is_queued_for_deletion())
	lvl.review.pace = 0.2
	lvl.shift.start_review("ПРИЁМКА")
	lvl.review.start()
	tab.set_tab(0)
	_press("tablet")
	await _wait(1.0)
	txt = tab.shown_text
	_check("приёмка: в планшете фаза и «Столы проверены: 0/6»", tab._phase.text == "ПРИЁМКА" and txt.contains("Столы проверены: 0/6"), txt.left(300))
	var food: Array = get_tree().get_nodes_in_group("food")
	for f in food:   # еду убрали — будет претензия
		(f as Node3D).global_position = Vector3(0, -40, 0)
		(f as RigidBody3D).freeze = true
	await _wait_until(func(): return int(lvl.shift.progress.get("rv_i", -1)) >= 2, 40.0)
	txt = tab.shown_text
	_check("обход идёт — счётчик растёт", not txt.contains("Столы проверены: 0/6") and txt.contains("Столы проверены"), _items_dbg())
	_check("претензия «пропала еда» — в планшете", txt.contains("пропала еда"), txt)
	await _wait_until(func(): return lvl.shift.phase == lvl.ShiftScript.P.WON, 80.0)
	await _wait(0.6)
	txt = tab.shown_text
	_check("итог: «ПРИНЯТО», все столы проверены, звёзды", tab._phase.text == "ПРИНЯТО" and txt.contains("Столы проверены: 6/6") and tab._order().get("stars", -1) >= 0, txt.left(300))

	print("RESULT ", "PASS" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit(fails)

func KeyCap_label(a: String) -> String:
	return preload("res://ui/theme/key_cap.gd").action_label(a)

func _state_of(prefix: String) -> String:
	for it in lvl.tablet_order()["items"]:
		if str(it["text"]).begins_with(prefix):
			return str(it["state"])
	return ""

func _items_dbg() -> String:
	var o: Dictionary = lvl.tablet_order()
	var s := ""
	for it in o.get("review", []) + o.get("items", []):
		s += "%s [%s] %s; " % [it["text"], it["state"], it["note"]]
	return s

func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)

func _press_key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event.call_deferred(up)

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
	await _wait(0.4)

func _wait_until(cond: Callable, limit: float) -> void:
	var t := 0.0
	while t < limit and not cond.call():
		await get_tree().physics_frame
		t += 1.0 / 60.0

func _wait(sec: float) -> void:
	var n := int(sec * 60.0)
	for i in n:
		await get_tree().physics_frame

func _check(what: String, ok: bool, extra := "") -> void:
	if not ok:
		fails += 1
	print("PASS  " if ok else "FAIL  ", what, "  ", extra if not ok else "")
