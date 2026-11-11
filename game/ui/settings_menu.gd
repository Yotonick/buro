extends Control
## Окно настроек: жестянка с вкладками «Управление», «Графика», «Звук».
## Открывается из главного меню и из паузы (кладётся поверх экрана, сигнал closed — закрылось).
## Всё применяется сразу, на «Готово» (или Esc) — сохраняется в user://settings.cfg.
## «Сбросить вкладку» возвращает заводские значения только открытой вкладки.
##
## Переназначение: клик по гнезду клавиши → «Нажми клавишу…» → любая клавиша или кнопка мыши.
## Esc — отмена, Backspace/Delete — очистить гнездо. Клавиша, занятая двумя действиями,
## подсвечивается красным у обоих, а внизу пишется, где ещё она стоит.

signal closed

const Style := preload("res://ui/ui_style.gd")
const KeyCap := preload("res://ui/theme/key_cap.gd")

const TABS := ["Управление", "Графика", "Звук"]

var tabs: TabContainer
var _slots := {}                  ## [действие, место] -> Button
var _waiting: Array = []          ## [действие, место], пока ждём нажатия
var _conflict_label: Label
var _sens: HSlider
var _sens_val: Label
var _invert: CheckButton
var _hints: CheckButton
var _view: OptionButton
var _g := {}                      ## элементы вкладки «Графика»
var _vol := {}                    ## шина -> [HSlider, Label]
var _filling := false             ## заполняем элементы из настроек — не считать это правкой

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(Style.NAVY_DEEP, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := Style.plate(true)
	panel.custom_minimum_size = Vector2(1000, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	head.add_child(Style.title("НАСТРОЙКИ", 30))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var note := Style.sticker("крутить можно всё, кроме гаек", 2.5, 0.0, 22)
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(note)

	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 470)
	tabs.use_hidden_tabs_for_min_size = true   # окно одного размера на всех вкладках
	box.add_child(tabs)
	tabs.add_child(_controls_tab())
	tabs.add_child(_graphics_tab())
	tabs.add_child(_audio_tab())
	for i in TABS.size():
		tabs.set_tab_title(i, TABS[i])

	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	var reset := Style.button("Сбросить вкладку", _reset_tab, "danger")
	bottom.add_child(reset)
	var gap2 := Control.new()
	gap2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap2)
	var done := Style.button("Готово", close, "primary")
	done.set_meta("back", true)
	done.custom_minimum_size = Vector2(200, 0)
	bottom.add_child(done)

	Controls.bindings_changed.connect(_refresh_slots)
	_fill()
	UiSound.play("open")
	done.grab_focus.call_deferred()

func close() -> void:
	_waiting = []
	Settings.save()
	Settings.notify()
	closed.emit()
	queue_free()

# --- Управление ----------------------------------------------------------------

func _controls_tab() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var cap := HBoxContainer.new()
	left.add_child(cap)
	var c1 := _muted("Действие")
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.add_child(c1)
	for t in ["Клавиша", "Запасная"]:
		var c := _muted(t)
		c.custom_minimum_size = Vector2(150, 0)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_child(c)
	cap.add_child(Style.spacer(0))
	var cpad := Control.new()
	cpad.custom_minimum_size = Vector2(40, 0)
	cap.add_child(cpad)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for p in Controls.ACTIONS:
		var r := HBoxContainer.new()
		list.add_child(r)
		var name_l := Style.label(p[1], 20)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(name_l)
		for slot in Controls.SLOTS:
			var b := Button.new()
			b.theme_type_variation = "SlotButton"
			b.custom_minimum_size = Vector2(150, 40)
			b.pressed.connect(_start_wait.bind(p[0], slot))
			r.add_child(b)
			_slots[[p[0], slot]] = b
		var undo := Style.button("↺", Controls.reset_action.bind(p[0]), "flat")
		undo.tooltip_text = "Как было"
		undo.custom_minimum_size = Vector2(40, 0)
		r.add_child(undo)
	_conflict_label = Style.label("", 18, Style.DANGER)
	_conflict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conflict_label.custom_minimum_size = Vector2(0, 24)
	left.add_child(_conflict_label)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(290, 0)
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	right.add_child(Style.title("МЫШЬ", 22, Style.TEXT))
	var sl := _slider_row(right, "Чувствительность", 0.2, 3.0, 0.05)
	_sens = sl[0]
	_sens_val = sl[1]
	_sens.value_changed.connect(func(v):
		_sens_val.text = "×%.2f" % v
		if not _filling:
			Settings.mouse_sens = v
			Settings.notify())
	_invert = CheckButton.new()
	_invert.text = "Инверсия по вертикали"
	_invert.toggled.connect(func(v):
		if not _filling:
			Settings.invert_y = v
			Settings.notify())
	right.add_child(_invert)
	right.add_child(Style.spacer(4))
	right.add_child(Style.title("ПОДСКАЗКИ", 22, Style.TEXT))
	_hints = CheckButton.new()
	_hints.text = "Показывать подсказки"
	_hints.toggled.connect(func(v):
		if not _filling:
			Settings.show_hints = v
			Settings.notify())
	right.add_child(_hints)
	right.add_child(Style.spacer(4))
	right.add_child(Style.title("КАМЕРА", 22, Style.TEXT))
	var vr := HBoxContainer.new()
	vr.add_theme_constant_override("separation", 10)
	var vl := Style.label("Вид в начале", 18)
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vr.add_child(vl)
	_view = OptionButton.new()
	_view.add_item("1-е лицо")
	_view.add_item("3-е лицо")
	_view.item_selected.connect(func(i):
		if not _filling:
			Settings.start_view = "third" if i == 1 else "first"
			Settings.notify())
	vr.add_child(_view)
	right.add_child(vr)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(fill)
	var how := Style.sticker("Клик по гнезду — жми новую клавишу. Esc — передумал, Backspace — убрать.", -2.0, 250.0, 22)
	how.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.add_child(how)
	right.add_child(Style.spacer(6))
	var pause_row := HBoxContainer.new()
	pause_row.add_child(Style.key_text("Esc", 28))
	var pl := _muted("пауза — всегда Esc")
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pause_row.add_child(pl)
	right.add_child(pause_row)
	return row

func _start_wait(action: String, slot: int) -> void:
	_waiting = [action, slot]
	_refresh_slots()

func is_waiting() -> bool:
	return _waiting.size() == 2

## Ввод для гнезда, которое ждёт клавишу (вызывается из _input, а тестами — напрямую).
func feed_binding(e: InputEvent) -> bool:
	if not is_waiting():
		return false
	var action: String = _waiting[0]
	var slot: int = _waiting[1]
	if e is InputEventKey:
		var k: Key = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		if k == KEY_ESCAPE:
			_waiting = []
			_refresh_slots()
			UiSound.play("back")
			return true
		_waiting = []
		if k == KEY_BACKSPACE or k == KEY_DELETE:
			Controls.set_binding(action, slot, null)
		else:
			Controls.set_binding(action, slot, e)
		UiSound.play("confirm")
		return true
	if e is InputEventMouseButton:
		_waiting = []
		Controls.set_binding(action, slot, e)
		UiSound.play("confirm")
		return true
	return false

func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if is_waiting():
		var press: bool = (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventMouseButton and e.pressed)
		if press and feed_binding(e):
			get_viewport().set_input_as_handled()
		elif e is InputEventKey or e is InputEventMouseButton:
			get_viewport().set_input_as_handled()   # отпускания и т.п. — не пускать дальше
		return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func _refresh_slots() -> void:
	if not is_inside_tree():
		return
	var conf: Dictionary = Controls.conflicts()
	var lines: Array[String] = []
	for code in conf:
		var names: Array[String] = []
		for a in conf[code]:
			names.append("«%s»" % Controls.title_of(a))
		lines.append("%s занята дважды: %s" % [KeyCap.event_label(Controls.decode(code)), ", ".join(names)])
	_conflict_label.text = "\n".join(lines)
	for key in _slots:
		var b: Button = _slots[key]
		for c in b.get_children():
			c.queue_free()
		var code: String = Controls.codes(key[0])[key[1]]
		var waiting: bool = is_waiting() and _waiting[0] == key[0] and _waiting[1] == key[1]
		b.text = ""
		if waiting:
			b.theme_type_variation = "SlotWaiting"
			b.text = "Нажми клавишу…"
		elif code == "":
			b.theme_type_variation = "SlotButton"
			b.text = "—"
		else:
			b.theme_type_variation = "SlotConflict" if conf.has(code) else "SlotButton"
			var cap := Style.key_event(Controls.decode(code), 30)
			var cc := CenterContainer.new()
			cc.set_anchors_preset(Control.PRESET_FULL_RECT)
			cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cc.add_child(cap)
			b.add_child(cc)

## Подпись гнезда (для тестов): «E», «ЛКМ», «—» или «Нажми клавишу…».
func slot_text(action: String, slot: int) -> String:
	var b: Button = _slots[[action, slot]]
	if b.text != "":
		return b.text
	for c in b.get_children():
		if not c.is_queued_for_deletion() and c.get_child_count() > 0:
			return c.get_child(0).shown_text()
	return ""

func slot_conflict(action: String, slot: int) -> bool:
	return _slots[[action, slot]].theme_type_variation == "SlotConflict"

func conflict_text() -> String:
	return _conflict_label.text

# --- Графика -------------------------------------------------------------------

func _graphics_tab() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(grid)

	_g.preset = _option(grid, "Качество", ["Низко", "Средне", "Высоко", "Своё"], func(i):
		if i < 3:
			Settings.set_preset(Settings.PRESETS[i])
		_graphics_changed(false))
	_g.shadows = _option(grid, "Тени", Settings.SHADOW_NAMES, func(i):
		Settings.shadows = i
		_graphics_changed(true))
	_g.aa = _option(grid, "Сглаживание", Settings.AA_NAMES, func(i):
		Settings.aa = i
		_graphics_changed(true))
	var sc := _slider_cell(grid, "Масштаб рендера", 0.5, 1.0, 0.05)
	_g.scale = sc
	sc[0].value_changed.connect(func(v):
		sc[1].text = "%d%%" % roundi(v * 100)
		if not _filling:
			Settings.render_scale = v
			_graphics_changed(true))
	var fps_names: Array = []
	for f in Settings.FPS_LIMITS:
		fps_names.append("Без ограничения" if f == 0 else "%d кадров/с" % f)
	_g.fps = _option(grid, "Ограничение FPS", fps_names, func(i):
		Settings.fps_limit = Settings.FPS_LIMITS[i]
		_graphics_changed(false))
	_g.vsync = _check(grid, "V-Sync (без разрывов картинки)", func(v):
		Settings.vsync = v
		_graphics_changed(false))
	_g.full = _check(grid, "Полный экран", func(v):
		Settings.fullscreen = v
		Settings.apply_window())
	var ff := _slider_cell(grid, "Обзор от 1-го лица", 65.0, 110.0, 1.0)
	_g.fov_fp = ff
	ff[0].value_changed.connect(func(v):
		ff[1].text = "%d°" % roundi(v)
		if not _filling:
			Settings.fov_fp = v
			Settings.notify())
	var fv := _slider_cell(grid, "Обзор от 3-го лица", 50.0, 90.0, 1.0)
	_g.fov = fv
	fv[0].value_changed.connect(func(v):
		fv[1].text = "%d°" % roundi(v)
		if not _filling:
			Settings.fov = v
			Settings.notify())

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(260, 0)
	row.add_child(side)
	side.add_child(Style.spacer(10))
	var tip := Style.sticker("Слабый ноутбук?\nСтавь «Средне».\nВсё равно тормозит —\nмасштаб 75% или\nтени «Выкл».", 2.0, 220.0, 25)
	tip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	side.add_child(tip)
	return row

func _graphics_changed(custom: bool) -> void:
	if _filling:
		return
	if custom:
		Settings.detect_preset()
	Settings.apply_graphics()
	_fill_graphics()

# --- Звук ----------------------------------------------------------------------

func _audio_tab() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(grid)
	for pair in [["Master", "Общая громкость"], ["SFX", "Эффекты"], ["Music", "Музыка"], ["UI", "Интерфейс"]]:
		var bus: String = pair[0]
		var cell := _slider_cell(grid, pair[1], 0.0, 1.0, 0.01, 340.0)
		_vol[bus] = cell
		cell[0].value_changed.connect(func(v):
			cell[1].text = "выкл" if v <= 0.001 else "%d%%" % roundi(v * 100)
			if not _filling:
				Settings.volume[bus] = v
				Settings.apply_audio())
		if bus == "UI":
			cell[0].drag_ended.connect(func(_c): UiSound.play("pop"))
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(260, 0)
	row.add_child(side)
	side.add_child(Style.spacer(10))
	var tip := Style.sticker("Музыки пока нет —\nкомпозитор ушёл\nна перекур.", -2.5, 210.0, 25)
	tip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	side.add_child(tip)
	return row

# --- Заполнение и сброс --------------------------------------------------------

func _fill() -> void:
	_filling = true
	_sens.value = Settings.mouse_sens
	_sens_val.text = "×%.2f" % Settings.mouse_sens
	_invert.button_pressed = Settings.invert_y
	_hints.button_pressed = Settings.show_hints
	_view.select(1 if Settings.start_view == "third" else 0)
	for bus in _vol:
		_vol[bus][0].value = Settings.volume[bus]
		_vol[bus][1].text = "выкл" if Settings.volume[bus] <= 0.001 else "%d%%" % roundi(Settings.volume[bus] * 100)
	_filling = false
	_fill_graphics()
	_refresh_slots()

func _fill_graphics() -> void:
	_filling = true
	_g.preset.select(maxi(0, ["low", "medium", "high", "custom"].find(Settings.preset)))
	_g.shadows.select(Settings.shadows)
	_g.aa.select(Settings.aa)
	_g.scale[0].value = Settings.render_scale
	_g.scale[1].text = "%d%%" % roundi(Settings.render_scale * 100)
	_g.fps.select(maxi(0, Settings.FPS_LIMITS.find(Settings.fps_limit)))
	_g.vsync.button_pressed = Settings.vsync
	_g.full.button_pressed = Settings.fullscreen
	_g.fov[0].value = Settings.fov
	_g.fov[1].text = "%d°" % roundi(Settings.fov)
	_g.fov_fp[0].value = Settings.fov_fp
	_g.fov_fp[1].text = "%d°" % roundi(Settings.fov_fp)
	_filling = false

func _reset_tab() -> void:
	match tabs.current_tab:
		0:
			_waiting = []
			Settings.reset_controls()
			Controls.reload()
		1:
			Settings.reset_graphics()
			Settings.apply_graphics()
			Settings.apply_window()
		2:
			Settings.reset_audio()
			Settings.apply_audio()
	Settings.notify()
	_fill()
	UiSound.play("paper")

# --- Мелкие кирпичики ----------------------------------------------------------

func _muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "MutedLabel"
	return l

func _row_label(grid: GridContainer, text: String) -> void:
	var l := Style.label(text, 20)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)

func _option(grid: GridContainer, text: String, items: Array, on_pick: Callable) -> OptionButton:
	_row_label(grid, text)
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.custom_minimum_size = Vector2(300, 0)
	o.item_selected.connect(func(i):
		if not _filling:
			on_pick.call(i))
	grid.add_child(o)
	return o

func _check(grid: GridContainer, text: String, on_toggle: Callable) -> CheckButton:
	_row_label(grid, text)
	var c := CheckButton.new()
	c.toggled.connect(func(v):
		if not _filling:
			on_toggle.call(v))
	grid.add_child(c)
	return c

## Ползунок с подписью значения справа: [HSlider, Label].
func _slider_cell(grid: GridContainer, text: String, lo: float, hi: float, step: float, width := 220.0) -> Array:
	_row_label(grid, text)
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(width, 30)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var v := Style.title("", 20, Style.SIGNAL)
	v.custom_minimum_size = Vector2(70, 0)
	h.add_child(v)
	grid.add_child(h)
	return [s, v]

func _slider_row(box: VBoxContainer, text: String, lo: float, hi: float, step: float) -> Array:
	box.add_child(Style.label(text, 20))
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 30)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var v := Style.title("", 20, Style.SIGNAL)
	v.custom_minimum_size = Vector2(66, 0)
	h.add_child(v)
	box.add_child(h)
	return [s, v]
