extends Control
## Рабочий планшет ремонтника (Tab). Выезжает снизу «в руках» — резиновый чехол с
## сигнальными углами, трещина в углу экрана, наклейка бюро. Мир при этом не на паузе:
## ходить можно, руки заняты (player_controller.walk_only), подсказки у прицела прячутся.
## Вкладки: Заказ (живой чек-лист и ход приёмки), Бригада (кто где и в каком виде),
## Управление (текущая раскладка), Заметки (служебные записки бюро).
## Данные берёт у уровня: tablet_order(), tablet_crew(), tablet_notes() (level_base.gd).

const Style := preload("res://ui/ui_style.gd")

const DEV_SIZE := Vector2(880, 540)
const SCREEN_INSET := 42.0         ## от края чехла до экрана
const SLIDE := 0.24
const REFRESH := 0.25
const RUBBER := Color("2a2e33")
const RUBBER_HI := Color("3a3f45")
const GLOVE := Color("e0cfa6")
const TABS := ["ЗАКАЗ", "БРИГАДА", "УПРАВЛЕНИЕ", "ЗАМЕТКИ"]

const NOTES := [
	["Начальник бюро", "Напоминаю: изолента — не скотч. Скотч — для слабаков и бухгалтерии."],
	["Бухгалтерия", "Каски выдаются под роспись. Голова — нет, за голову бюро ответственности не несёт."],
	["Отдел кадров", "Стажёров с вышки больше не роняем. Их осталось два. Оба в гипсе и оба обиделись."],
	["Начальник бюро", "Кто примотал меня к стулу на корпоративе — премия будет. Но не вам."],
	["Техника безопасности", "Перед тем как лезть в воду со щитком, подумайте. Потом всё равно полезете, мы знаем."],
	["Склад", "Рулонов выдано: 40. Возвращено: 3 и чей-то ботинок. Чей ботинок?!"],
	["Клиентский отдел", "При клиенте не говорить «нормально». Говорить «в пределах допуска»."],
	["Профсоюз бюро", "Нокаут короче трёх секунд перекуром не считается. Не наглейте."],
	["Начальник бюро", "Фургон — не амфибия. Проверено. Дважды."],
	["Бухгалтерия", "Деньги за вызов начислим после приёмки. Когда-нибудь. Мы над этим работаем."],
]

signal toggled(open: bool)

var hud: Node                      ## game_hud.gd
var level: Node                    ## level_base.gd (может не быть — в тестах интерфейса)
var tab := 0
var open := false

var _dev: Control                  ## сам планшет (чехол + экран)
var _screen: Control
var _content: Control
var _tabbar: TabBar
var _phase: Label
var _clock: Label
var _tween: Tween
var _refresh_t := 0.0
var _sig := ""
var _notes: Array = []
var _glove := GLOVE
var _sleeve := Color("378add")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_dev = Control.new()
	_dev.size = DEV_SIZE
	_dev.pivot_offset = DEV_SIZE * Vector2(0.5, 1.0)
	_dev.mouse_filter = Control.MOUSE_FILTER_STOP
	_dev.draw.connect(_draw_case)
	add_child(_dev)

	var sr := Rect2(Vector2.ONE * SCREEN_INSET, DEV_SIZE - Vector2.ONE * SCREEN_INSET * 2.0)
	_screen = Control.new()
	_screen.position = sr.position
	_screen.size = sr.size
	_screen.clip_contents = true
	_screen.draw.connect(_draw_screen_bg)
	_dev.add_child(_screen)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 18)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 12)
	_screen.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	m.add_child(col)

	var bar := HBoxContainer.new()   # строка состояния
	bar.add_theme_constant_override("separation", 12)
	col.add_child(bar)
	bar.add_child(Style.label("БНР · ПЛАНШЕТ ПОЛЕВОЙ", 14, Style.MUTED))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	_phase = Style.title("", 15, Style.NAVY)
	bar.add_child(_pill(_phase))
	_clock = Style.typed("", 15, Style.TEXT)
	bar.add_child(_clock)
	bar.add_child(_battery())

	_tabbar = TabBar.new()
	for t in TABS:
		_tabbar.add_tab(t)
	_tabbar.focus_mode = Control.FOCUS_NONE
	_tabbar.tab_changed.connect(func(i: int):
		tab = i
		_sig = ""
		_refresh())
	col.add_child(_tabbar)
	var line := ColorRect.new()
	line.color = Style.SIGNAL
	line.custom_minimum_size = Vector2(0, 2)
	col.add_child(line)
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("margin_top", 6)
	col.add_child(_content)

	var crack := Control.new()   # трещина поверх экрана, в правом верхнем углу
	crack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crack.draw.connect(_draw_crack.bind(crack))
	_screen.add_child(crack)

	var stick := Style.logo(70)   # наклейка бюро на угол чехла
	var badge := Control.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(DEV_SIZE.x - 120, -26)
	badge.size = Vector2(80, 80)
	badge.pivot_offset = Vector2(40, 40)
	badge.rotation_degrees = 12.0
	badge.draw.connect(func():
		badge.draw_circle(Vector2(41, 43), 39, Color(0, 0, 0, 0.35))
		badge.draw_circle(Vector2(40, 40), 39, Style.PAPER)
		badge.draw_arc(Vector2(40, 40), 36, 0, TAU, 48, Style.SIGNAL_DK, 2.0, true))
	stick.position = Vector2(5, 5)
	badge.add_child(stick)
	_dev.add_child(badge)
	var inv := Style.typed("ИНВ. № 0042 · НЕ РОНЯТЬ", 11, Style.MUTED)
	inv.position = Vector2(112, 11)
	_dev.add_child(inv)

	var hands := Control.new()   # большие пальцы перчаток поверх чехла
	hands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hands.size = DEV_SIZE
	hands.draw.connect(_draw_hands.bind(hands))
	_dev.add_child(hands)

	get_viewport().size_changed.connect(_place)
	_place()

## Открыть/закрыть (со звуком и «выездом» снизу).
func set_open(v: bool) -> void:
	if v == open:
		return
	open = v
	if v:
		visible = true
		_sig = ""
		if _notes.is_empty():
			_pick_notes()
		_take_colors()
		_refresh()
		UiSound.play("open")
	else:
		UiSound.play("close")
	_place()
	if _tween:
		_tween.kill()
	var rest := _rest_y()
	var away := get_viewport_rect().size.y + 30.0
	_tween = create_tween().set_trans(Tween.TRANS_BACK if v else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT if v else Tween.EASE_IN)
	if v:
		_dev.position.y = away
		_dev.rotation_degrees = 4.0
		_tween.tween_property(_dev, "position:y", rest, SLIDE)
		_tween.parallel().tween_property(_dev, "rotation_degrees", -1.2, SLIDE)
	else:
		_tween.tween_property(_dev, "position:y", away, SLIDE * 0.8)
		_tween.parallel().tween_property(_dev, "rotation_degrees", 5.0, SLIDE * 0.8)
		_tween.tween_callback(func(): visible = false)
	toggled.emit(v)

func set_tab(i: int) -> void:
	_tabbar.current_tab = clampi(i, 0, TABS.size() - 1)

func _rest_y() -> float:
	return get_viewport_rect().size.y - DEV_SIZE.y + 26.0

func _place() -> void:
	var vs := get_viewport_rect().size
	_dev.position.x = (vs.x - DEV_SIZE.x) / 2.0
	if open and (_tween == null or not _tween.is_running()):
		_dev.position.y = _rest_y()

func _take_colors() -> void:
	if level != null and is_instance_valid(level.get("player")):
		_sleeve = level.player.suit_color

func _process(dt: float) -> void:
	if not open:
		return
	_refresh_t -= dt
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH
		_refresh()

# ---------- содержимое ----------

## Текст текущей вкладки (для тестов).
var shown_text := ""

func _refresh() -> void:
	var t := Time.get_time_dict_from_system()
	_clock.text = "%02d:%02d" % [t["hour"], t["minute"]]
	var order := _order()
	_phase.text = str(order.get("phase", ""))
	_phase.get_parent().visible = _phase.text != ""
	var data: Variant
	match tab:
		0: data = order
		1: data = level.tablet_crew() if level != null else []
		2: data = str(Settings.bindings)   # перерисовать при переназначении
		_: data = _notes
	var sig := str(tab) + str(data)
	if sig == _sig:
		return
	_sig = sig
	for c in _content.get_children():
		c.queue_free()
	var page: Control
	match tab:
		0: page = _order_page(order)
		1: page = _crew_page(data)
		2: page = _controls_page()
		_: page = _notes_page()
	_content.add_child(page)
	shown_text = _collect(page)

func _order() -> Dictionary:
	return level.tablet_order() if level != null else {}

func _collect(n: Node) -> String:
	var parts: Array[String] = []
	if n is Label:
		parts.append(n.text)
	for c in n.get_children():
		var s := _collect(c)
		if s != "":
			parts.append(s)
	return " | ".join(parts)

func _order_page(o: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(270, 0)
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	left.add_child(Style.label("ОБЪЕКТ", 13, Style.MUTED))
	var cl := Style.title(str(o.get("client", "")), 23, Style.TEXT)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cl.custom_minimum_size = Vector2(270, 0)
	left.add_child(cl)
	left.add_child(Style.label(str(o.get("who", "")), 15, Style.MUTED))
	left.add_child(Style.spacer(2))
	left.add_child(Style.label("ЧТО СЛОМАНО", 13, Style.MUTED))
	var task := Style.label(str(o.get("task", "")), 17, Style.TEXT)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task.custom_minimum_size = Vector2(270, 0)
	left.add_child(task)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(fill)
	var st := int(o.get("stars", -1))
	if st >= 0:
		left.add_child(_stars(st))
	if str(o.get("pay", "")) != "":
		var pay := Style.typed(str(o.get("pay", "")), 14, Style.SIGNAL)
		left.add_child(pay)

	var sep := ColorRect.new()
	sep.color = Color(Style.STEEL, 0.5)
	sep.custom_minimum_size = Vector2(2, 0)
	row.add_child(sep)

	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = false
	row.add_child(sc)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	sc.add_child(right)
	var review: Array = o.get("review", [])
	if not review.is_empty():
		right.add_child(_section("ПРИЁМКА — ОБХОД МЕТРДОТЕЛЯ"))
		for it in review:
			right.add_child(_check_row(it, true))
		right.add_child(Style.spacer(6))
	var items: Array = o.get("items", [])
	right.add_child(_section("ЧЕК-ЛИСТ" + ("  ·  " + str(o.get("time", "")) if str(o.get("time", "")) != "" else "")))
	if items.is_empty():
		right.add_child(Style.label("Пусто. Подозрительно.", 17, Style.MUTED))
	for it in items:
		right.add_child(_check_row(it, not review.is_empty()))
	return row

func _section(text: String) -> Control:
	var l := Style.title(text, 15, Style.SIGNAL)
	return l

func _check_row(it: Dictionary, compact := false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var st := str(it.get("state", "info"))
	var box := Control.new()
	box.custom_minimum_size = Vector2(22, 22)
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.draw.connect(_draw_check.bind(box, st))
	row.add_child(box)
	var txt := VBoxContainer.new()
	txt.add_theme_constant_override("separation", 0)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(txt)
	var col: Color = {"ok": Style.TEXT, "bad": Color("ff8a7a"), "warn": Style.SIGNAL_HI}.get(st, Style.TEXT)
	txt.add_child(Style.label(str(it.get("text", "")), 16 if compact else 18, col))
	var note := str(it.get("note", ""))
	if note != "":
		txt.add_child(Style.typed(note, 13 if compact else 14, Style.MUTED))
	return row

func _draw_check(c: Control, st: String) -> void:
	var r := Rect2(1, 2, 20, 20)
	match st:
		"ok":
			c.draw_rect(r, Style.OK)
			c.draw_polyline(PackedVector2Array([Vector2(5, 12), Vector2(9.5, 16.5), Vector2(17, 7)]), Style.NAVY_DEEP, 3.0, true)
		"bad":
			c.draw_rect(r, Style.STAMP)
			c.draw_line(Vector2(6, 7), Vector2(16, 17), Style.TEXT, 3.0, true)
			c.draw_line(Vector2(16, 7), Vector2(6, 17), Style.TEXT, 3.0, true)
		"warn":
			c.draw_rect(r, Style.SIGNAL)
			c.draw_rect(Rect2(9.5, 5, 3, 9), Style.NAVY_DEEP)
			c.draw_rect(Rect2(9.5, 16, 3, 3), Style.NAVY_DEEP)
		_:
			c.draw_rect(r, Style.STEEL, false, 2.0)

func _stars(n: int) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(180, 34)
	row.draw.connect(func():
		for i in 5:
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI / 2 + k * PI / 5
				var r := 15.0 if k % 2 == 0 else 6.5
				pts.append(Vector2(17 + i * 34, 18) + Vector2(cos(a), sin(a)) * r)
			row.draw_colored_polygon(pts, Style.SIGNAL if i < n else Style.PANEL_HI))
	return row

func _crew_page(crew: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	if crew.is_empty():
		box.add_child(Style.label("Никого. Бригада ушла на обед.", 18, Style.MUTED))
	for p in crew:
		box.add_child(_crew_row(p))
	var empty := 4 - crew.size()
	for i in maxi(empty, 0):
		var l := Style.typed("— свободное место в бригаде —", 15, Color(Style.MUTED, 0.5))
		box.add_child(l)
	return box

func _crew_row(p: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Style.PANEL, 0.85)
	sb.set_corner_radius_all(6)
	sb.border_width_left = 6
	sb.border_color = p.get("color", Style.STEEL)
	sb.content_margin_left = 14
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var helm := Control.new()   # каска цвета игрока
	helm.custom_minimum_size = Vector2(34, 30)
	var col: Color = p.get("color", Style.STEEL)
	var ko: bool = p.get("ko", false)
	helm.draw.connect(func():
		helm.draw_circle(Vector2(17, 18), 13, col)
		helm.draw_rect(Rect2(2, 18, 30, 5), col.darkened(0.25))
		if ko:   # звёздочки над головой
			for i in 3:
				helm.draw_circle(Vector2(8 + i * 9, 3 + (i % 2) * 2), 2.5, Style.SIGNAL_HI))
	helm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(helm)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.custom_minimum_size = Vector2(190, 0)
	row.add_child(names)
	var nm := HBoxContainer.new()
	nm.add_theme_constant_override("separation", 8)
	names.add_child(nm)
	nm.add_child(Style.title(str(p.get("name", "")), 19, Style.TEXT))
	if p.get("me", false):
		var me := Style.label("это ты", 13, Style.NAVY)
		nm.add_child(_pill(me, Style.SIGNAL))
	names.add_child(Style.typed(str(p.get("where", "")), 14, Style.MUTED))
	var status := Style.label(str(p.get("status", "")), 17, Color("ff8a7a") if ko else Style.TEXT)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status)
	var d := float(p.get("dist", -1.0))
	var dl := Style.typed("%d м" % int(round(d)) if d >= 0.0 else "", 17, Style.SIGNAL)
	dl.custom_minimum_size = Vector2(52, 0)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dl)
	return panel

func _controls_page() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 3)
	for pair in Controls.ACTIONS:
		if pair[0] in ["move_forward", "move_back", "move_left", "move_right"]:
			continue
		grid.add_child(Style.key_hint(pair[0], String(pair[1]).to_lower(), 17))
	var moves := HBoxContainer.new()
	moves.add_theme_constant_override("separation", 4)
	for a in ["move_forward", "move_left", "move_back", "move_right"]:
		moves.add_child(Style.key(a, 29))
	var ml := Style.outlined(Style.label("ходить", 17), 6)
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	moves.add_child(Style.spacer(0))
	moves.add_child(ml)
	grid.add_child(moves)
	var esc := HBoxContainer.new()
	esc.add_theme_constant_override("separation", 8)
	var k := Style.key_text("Esc", 29)
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	esc.add_child(k)
	var el := Style.outlined(Style.label("перекур и настройки", 17), 6)
	el.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	esc.add_child(el)
	grid.add_child(esc)
	var wheel := HBoxContainer.new()
	wheel.add_theme_constant_override("separation", 8)
	var wk := Style.key_text("колёсико", 29)
	wk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wheel.add_child(wk)
	var wl := Style.outlined(Style.label("камера ближе / дальше", 17), 6)
	wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wheel.add_child(wl)
	grid.add_child(wheel)
	var box := VBoxContainer.new()
	box.add_child(grid)
	var foot := Style.typed("Переназначить — Esc → Настройки → Управление", 14, Style.MUTED)
	box.add_child(Style.spacer(2))
	box.add_child(foot)
	return box

func _pick_notes() -> void:
	var pool := NOTES.duplicate()
	pool.shuffle()
	_notes = []
	if level != null:
		_notes.append_array(level.tablet_notes())
	for n in pool:
		if _notes.size() >= 4:
			break
		_notes.append(n)

func _notes_page() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	for i in _notes.size():
		var n: Array = _notes[i]
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(Style.PANEL, 0.9)
		sb.set_corner_radius_all(6)
		sb.border_width_top = 4
		sb.border_color = Style.SIGNAL if i == 0 else Style.STEEL
		sb.set_content_margin_all(12)
		p.add_theme_stylebox_override("panel", sb)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size = Vector2(355, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		p.add_child(v)
		var head := HBoxContainer.new()
		head.add_child(Style.label(str(n[0]), 16, Style.SIGNAL))
		var g := Control.new()
		g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(g)
		head.add_child(Style.typed("вх. %03d" % (117 + i * 23), 13, Style.MUTED))
		v.add_child(head)
		var t := Style.label(str(n[1]), 16, Style.TEXT)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(330, 0)
		v.add_child(t)
		grid.add_child(p)
	return grid

func _pill(l: Label, c := Style.SIGNAL) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	l.add_theme_color_override("font_color", Style.NAVY)
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

func _battery() -> Control:
	var b := Control.new()
	b.custom_minimum_size = Vector2(62, 18)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.draw.connect(func():
		b.draw_rect(Rect2(0, 2, 26, 13), Style.MUTED, false, 1.5)
		b.draw_rect(Rect2(26, 6, 3, 5), Style.MUTED)
		b.draw_rect(Rect2(2.5, 4.5, 4, 8), Style.STAMP)
		b.draw_string(Style.MONO, Vector2(33, 14), "13%", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Style.MUTED))
	return b

# ---------- рисунок чехла ----------

func _rbox(c: Color, r: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(r))
	sb.anti_aliasing = true
	return sb

func _draw_case() -> void:
	var full := Rect2(Vector2.ZERO, DEV_SIZE)
	var shadow := _rbox(Color(0, 0, 0, 0), 38)
	shadow.shadow_color = Color(0, 0, 0, 0.5)
	shadow.shadow_size = 22
	shadow.shadow_offset = Vector2(0, 10)
	_dev.draw_style_box(shadow, full)
	_dev.draw_style_box(_rbox(RUBBER, 38), full)
	# сигнальные резиновые углы
	var cs := 104.0
	for corner in 4:
		var sb := _rbox(Style.SIGNAL_DK, 0)
		var right := corner % 2 == 1
		var bottom := corner >= 2
		sb.corner_radius_top_left = 38 if (not right and not bottom) else 6
		sb.corner_radius_top_right = 38 if (right and not bottom) else 6
		sb.corner_radius_bottom_left = 38 if (not right and bottom) else 6
		sb.corner_radius_bottom_right = 38 if (right and bottom) else 6
		var pos := Vector2(DEV_SIZE.x - cs if right else 0.0, DEV_SIZE.y - cs if bottom else 0.0)
		_dev.draw_style_box(sb, Rect2(pos, Vector2(cs, cs)))
		var hi := sb.duplicate()
		hi.bg_color = Style.SIGNAL
		_dev.draw_style_box(hi, Rect2(pos + Vector2(3, 3), Vector2(cs - 6, cs - 8)))
	# рифление по бокам
	for side in [12.0, DEV_SIZE.x - 22.0]:
		for i in 9:
			var y := DEV_SIZE.y * 0.3 + i * 16.0
			_dev.draw_rect(Rect2(side, y, 10, 5), RUBBER_HI)
	# рамка экрана
	var bez := Rect2(Vector2.ONE * (SCREEN_INSET - 14.0), DEV_SIZE - Vector2.ONE * (SCREEN_INSET - 14.0) * 2.0)
	_dev.draw_style_box(_rbox(Color("101215"), 18), bez)
	_dev.draw_circle(Vector2(DEV_SIZE.x / 2.0, SCREEN_INSET - 7.0), 3.5, Color("2c3640"))   # камера
	var btn := _rbox(RUBBER_HI, 6)   # кнопка внизу
	_dev.draw_style_box(btn, Rect2(DEV_SIZE.x / 2.0 - 34, DEV_SIZE.y - 22, 68, 9))

func _draw_screen_bg() -> void:
	var s := _screen.size
	_screen.draw_rect(Rect2(Vector2.ZERO, s), Style.NAVY_DEEP)
	var y := 0.0
	while y < s.y:   # еле заметные строки, как у дешёвого экрана
		_screen.draw_line(Vector2(0, y), Vector2(s.x, y), Color(Style.STEEL, 0.06), 1.0)
		y += 3.0
	_screen.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, 34)), Color(Style.PANEL, 0.6))

func _draw_crack(c: Control) -> void:
	var o := Vector2(c.size.x, 0)   # угол экрана — оттуда расходятся трещины
	var col := Color(1, 1, 1, 0.42)
	var lines := [
		[Vector2(0, 0), Vector2(-38, 22), Vector2(-61, 30), Vector2(-104, 58), Vector2(-122, 86)],
		[Vector2(-38, 22), Vector2(-44, 52), Vector2(-70, 82)],
		[Vector2(-61, 30), Vector2(-92, 26), Vector2(-140, 34)],
		[Vector2(0, 0), Vector2(-12, 40), Vector2(-8, 74), Vector2(-24, 110)],
		[Vector2(-104, 58), Vector2(-96, 76)],
	]
	for l in lines:
		var pts := PackedVector2Array()
		for p in l:
			pts.append(o + p)
		c.draw_polyline(pts, Color(0, 0, 0, 0.35), 3.0, true)
		c.draw_polyline(pts, col, 1.3, true)
	c.draw_circle(o + Vector2(-8, 6), 10, Color(1, 1, 1, 0.08))

func _draw_hands(c: Control) -> void:
	# снизу по бокам: рукав комбеза, перчатка, большой палец — поверх чехла
	for right in [false, true]:
		var x := DEV_SIZE.x - 20.0 if right else 20.0
		var s := -1.0 if right else 1.0
		var palm := Vector2(x - s * 6.0, DEV_SIZE.y - 70.0)
		c.draw_circle(palm + Vector2(-s * 22, 64), 64, _sleeve.darkened(0.1))   # рукав
		c.draw_circle(palm, 50, _glove.darkened(0.12))
		c.draw_circle(palm + Vector2(s * 4, -4), 46, _glove)
		var thumb := PackedVector2Array()
		var base := palm + Vector2(s * 20, -38)
		for i in 21:   # большой палец — вытянутый овал наискосок
			var a := i * TAU / 20.0
			var p := Vector2(cos(a) * 15.0, sin(a) * 34.0).rotated(s * 0.75)
			thumb.append(base + Vector2(s * 16, -22) + p)
		c.draw_colored_polygon(thumb, _glove)
		thumb.append(thumb[0])
		c.draw_polyline(thumb, _glove.darkened(0.3), 2.0, true)
		c.draw_line(palm + Vector2(s * 30, -6), palm + Vector2(s * 40, 10), _glove.darkened(0.3), 2.0, true)
