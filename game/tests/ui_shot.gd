extends Node
## Кадры экранов интерфейса (меню, настройки — 3 вкладки и конфликт, лобби, образец кирпичиков,
## пауза, настройки из паузы, табличка итога):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##     --write-movie /tmp/ui/f.png --fixed-fps 30 res://tests/ui_shot.tscn
## Номер кадра печатается в строке SHOT (файлы сдвинуты — смотри соседние).
const Style := preload("res://ui/ui_style.gd")
var cur: Node

func _ready():
	await f(5)
	show_scene(load("res://ui/main_menu.tscn").instantiate())
	await f(10); shot("menu")
	# настройки поверх меню: три вкладки, конфликт и ожидание клавиши
	cur.open_settings()
	var sm = cur.settings_menu
	await f(10); shot("settings_controls")
	var e := InputEventKey.new(); e.physical_keycode = KEY_E; e.pressed = true
	sm._start_wait("jump", 1); sm.feed_binding(e)
	sm._start_wait("flop", 1)
	await f(10); shot("settings_conflict")
	sm._waiting = []
	Controls.reset_action("jump")
	sm.tabs.current_tab = 1
	await f(10); shot("settings_graphics")
	sm.tabs.current_tab = 2
	await f(10); shot("settings_audio")
	sm.close()
	await f(2)
	# лобби: имитируем сессию хоста с тремя игроками
	Net.set("_in_session", true)
	Net.players = {1: {"name": "Ёжик", "slot": 0}, 2: {"name": "Толян", "slot": 1}, 3: {"name": "Маринка", "slot": 2}}
	show_scene(load("res://ui/lobby.tscn").instantiate())
	await f(10); shot("lobby")
	Net.set("_in_session", false)
	Net.players = {}
	show_scene(kit())
	await f(10); shot("kit")
	var hud = load("res://ui/game_hud.gd").new()
	show_scene(hud)
	hud.set_paused(true)
	await f(10); shot("pause")
	hud.open_settings()
	await f(10); shot("pause_settings")
	hud.settings_menu.close()
	hud.set_paused(false)
	hud.show_banner("КУПОЛ ДЕРЖИТСЯ", "Метрдотель: «Сносно. Для подводных людей.»", true, 3)
	hud.show_line("Метрдотель: «Руки! Уберите руки!»")
	await f(10); shot("banner")
	await f(5)
	get_tree().quit()

func show_scene(n: Node) -> void:
	if cur:
		cur.queue_free()
	cur = n
	add_child(n)

## Образец кирпичиков стиля на одном экране.
func kit() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = Style.make_theme()
	root.add_child(Style.background())
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	root.add_child(m)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	m.add_child(cols)
	# 1: жестянка с кнопками и полями
	var p := Style.plate(true)
	p.custom_minimum_size = Vector2(380, 0)
	cols.add_child(p)
	var b := VBoxContainer.new()
	p.add_child(b)
	b.add_child(Style.title("ЖЕСТЯНКА", 30))
	b.add_child(Style.button("Главное действие", Callable(), "primary"))
	b.add_child(Style.button("Обычная кнопка"))
	var dis := Style.button("Недоступно")
	dis.disabled = true
	b.add_child(dis)
	b.add_child(Style.button("Опасное", Callable(), "danger"))
	b.add_child(Style.button("тихая ссылка", Callable(), "flat"))
	var le := LineEdit.new()
	le.placeholder_text = "поле ввода"
	b.add_child(le)
	var cb := CheckBox.new(); cb.text = "Галочка"; cb.button_pressed = true
	b.add_child(cb)
	var cs := CheckButton.new(); cs.text = "Переключатель"
	b.add_child(cs)
	var sl := HSlider.new(); sl.value = 65
	b.add_child(sl)
	var ob := OptionButton.new()
	for it in ["Низко", "Средне", "Высоко"]: ob.add_item(it)
	ob.select(1)
	b.add_child(ob)
	# 2: клавиши и подсказки
	var p2 := Style.plate()
	p2.custom_minimum_size = Vector2(330, 0)
	cols.add_child(p2)
	var b2 := VBoxContainer.new()
	p2.add_child(b2)
	b2.add_child(Style.title("КЛАВИШИ", 30))
	var keys := HBoxContainer.new()
	for a in ["use", "drop_tool", "jump", "crouch", "grab_left", "grab_right"]:
		keys.add_child(Style.key(a, 40))
	b2.add_child(keys)
	var keys2 := HBoxContainer.new()
	for t in ["Esc", "Tab", "Shift", "F1"]:
		keys2.add_child(Style.key_text(t, 32))
	b2.add_child(keys2)
	b2.add_child(Style.key_hint("use", "на пояс"))
	b2.add_child(Style.key_hint("grab_left", "схватить"))
	b2.add_child(Style.key_hint("drop_tool", "бросить рулон"))
	b2.add_child(Style.stripe(14))
	b2.add_child(Style.label("Обычный текст Rubik — ёжик, щиток, «кавычки».", 18))
	var mu := Label.new(); mu.text = "Приглушённый текст"; mu.theme_type_variation = "MutedLabel"
	b2.add_child(mu)
	b2.add_child(Style.logo(90))
	# 3: бумага и стикер
	var b3 := VBoxContainer.new()
	b3.add_theme_constant_override("separation", 22)
	cols.add_child(b3)
	var pa := Style.paper()
	pa.custom_minimum_size = Vector2(380, 0)
	b3.add_child(pa)
	var pb := VBoxContainer.new()
	pa.add_child(pb)
	pb.add_child(Style.title("АКТ ПРИЁМКИ № 0042", 26, Style.INK))
	var ty := Style.typed("Объект: «Глубокая тарелка»\nЗаказчик: метрдотель\nПретензии: стул на боку, сыро.", 18)
	pb.add_child(ty)
	pb.add_child(Style.hand("Подпись: ~ Бонифаций ~", 30, Style.STAMP))
	var st := Style.sticker("Не забыть: щиток на крюк!!!", 3.0, 240.0)
	st.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b3.add_child(st)
	return root

func shot(n):
	print("SHOT %s frame=%d" % [n, Engine.get_frames_drawn()])
	await f(2)
func f(n):
	for i in n: await get_tree().process_frame
