extends CanvasLayer
## Игровой интерфейс поверх мира: прицел, всплывающие подсказки по месту (world_prompts.gd),
## стикеры-советы (tip), имена и пузыри (world_overlay.gd), большая табличка итога и пауза (Esc).
## Мир на паузе не останавливается — просто отпускается мышь.
## Висящего текста по управлению больше нет: клавиши — в подсказках и в паузе.

const Style := preload("res://ui/ui_style.gd")
const SettingsMenu := preload("res://ui/settings_menu.gd")
const PromptsScript := preload("res://ui/world_prompts.gd")
const OverlayScript := preload("res://ui/world_overlay.gd")
const KeyCap := preload("res://ui/theme/key_cap.gd")

const TIP_TIME := 8.0
const TIP_MAX := 2              ## одновременно на экране

## Какие советы уже показывали (за запуск игры) — второй раз не надоедаем.
static var _seen_tips := {}

var prompts: Control            ## world_prompts.gd
var overlay: Control            ## world_overlay.gd
var line_hidden := false        ## говорящий на экране — пузырь вместо строки внизу

var _tips: VBoxContainer
var _tip_queue: Array = []
var _tip_cd := 0.0
var _pause: Control
var _root: Control
var _banner: VBoxContainer
var _line: Label
var _line_left := 0.0
var _banner_left := 0.0

func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = Style.make_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	overlay = OverlayScript.new()
	overlay.hud = self
	_root.add_child(overlay)
	prompts = PromptsScript.new()
	prompts.hud = self
	_root.add_child(prompts)
	_tips = VBoxContainer.new()
	_tips.add_theme_constant_override("separation", 14)
	_tips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tips.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tips.offset_left = -360
	_tips.offset_right = -28
	_tips.offset_top = 96
	_root.add_child(_tips)

	var dot := ColorRect.new()   # точка прицела: туда тянутся руки и клеится лента
	dot.color = Color(1, 1, 1, 0.75)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.offset_left = -2
	dot.offset_top = -2
	dot.offset_right = 2
	dot.offset_bottom = 2
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dot)

	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0.05, 0.1, 0.15, 0.7)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_root.add_child(_pause)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	center.add_child(row)
	var panel := Style.plate(true)
	panel.custom_minimum_size = Vector2(380, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Style.title("ПЕРЕКУР", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Style.label("Мир не стоит — бригада работает без тебя", 17, Style.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(Style.spacer(4))
	box.add_child(Style.button("Продолжить", set_paused.bind(false), "primary"))
	box.add_child(Style.button("Настройки", open_settings))
	if Net.in_session() and Net.is_host():
		box.add_child(Style.button("Вернуть бригаду в лобби", func(): Game.back_to_lobby()))
	var quit := Style.button("В меню", _to_menu, "danger")
	quit.set_meta("back", true)
	box.add_child(quit)
	row.add_child(_controls_card())
	set_paused(false)

	_banner = VBoxContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 90
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_root.add_child(_banner)

	_line = Style.outlined(Style.label("", 22, Style.TEXT), 8)   # реплика клиента — чтобы было слышно и издалека
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_line.offset_left = -420
	_line.offset_right = 420
	_line.offset_top = -170
	_line.offset_bottom = -110
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.visible = false
	_root.add_child(_line)

## Карточка управления в паузе — клавиши из текущей раскладки.
func _controls_card() -> Control:
	var card := Style.plate()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	box.add_child(Style.title("УПРАВЛЕНИЕ", 22, Style.TEXT))
	var moves := HBoxContainer.new()
	moves.add_theme_constant_override("separation", 4)
	for a in ["move_forward", "move_left", "move_back", "move_right"]:
		moves.add_child(Style.key(a, 30))
	var ml := Style.label("ходить", 18)
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	moves.add_child(Style.spacer(0))
	moves.add_child(ml)
	box.add_child(moves)
	for pair in [["grab_left", "левая рука"], ["grab_right", "правая рука"], ["jump", "прыжок"],
			["use", "использовать / на пояс"], ["drop_tool", "бросить инструмент"], ["crouch", "присесть"],
			["flop", "упасть"], ["laugh", "ржать"], ["respawn", "встать на место"]]:
		box.add_child(Style.key_hint(pair[0], pair[1], 18))
	return card

## Мир, с которым работают подсказки и имена (уровень зовёт сразу после создания HUD).
func attach_world(w: Node) -> void:
	prompts.world = w
	overlay.world = w

## Стикер-совет справа сверху: id — чтобы не повторять; показывается один раз за запуск.
## С выключенными подсказками не показывается (и не считается показанным).
func tip(id: String, text: String, sec := TIP_TIME) -> void:
	if _seen_tips.has(id) or not Settings.show_hints:
		return
	_seen_tips[id] = true
	_tip_queue.append([text, sec])

## Подпись клавиши действия из текущей раскладки — для текста советов («E», «ЛКМ»…).
static func key_name(action: String) -> String:
	return KeyCap.action_label(action)

## Тексты советов, которые сейчас на экране (для тестов).
func tips_shown() -> Array:
	var out: Array = []
	for c in _tips.get_children():
		if not c.is_queued_for_deletion():
			out.append(str(c.get_meta("text", "")))
	return out

func _show_tip(text: String, sec: float) -> void:
	var st := Style.sticker(text, randf_range(-3.0, 1.5), 290, 25)
	st.size_flags_horizontal = Control.SIZE_SHRINK_END
	st.set_meta("text", text)
	st.set_meta("left", sec)
	st.modulate.a = 0.0
	_tips.add_child(st)
	UiSound.play("paper")

func _tick_tips(dt: float) -> void:
	_tip_cd -= dt
	if not Settings.show_hints:
		_tip_queue.clear()
	var live := 0
	for c in _tips.get_children():
		if c.is_queued_for_deletion():
			continue
		live += 1
		var left: float = c.get_meta("left") - dt
		c.set_meta("left", left)
		c.modulate.a = clampf(minf(left / 0.6, c.modulate.a + dt * 4.0), 0.0, 1.0)
		if left <= 0.0 or not Settings.show_hints:
			c.queue_free()
	if not _tip_queue.is_empty() and live < TIP_MAX and _tip_cd <= 0.0:
		var t: Array = _tip_queue.pop_front()
		_show_tip(t[0], t[1])
		_tip_cd = 1.2

func _process(dt: float) -> void:
	_tick_tips(dt)
	if _line_left > 0.0:
		_line_left -= dt
		_line.modulate.a = clampf(_line_left / 0.5, 0.0, 1.0)
	_line.visible = _line_left > 0.0 and not line_hidden
	if _banner_left > 0.0:
		_banner_left -= dt
		if _banner_left <= 0.0:
			_banner.visible = false

## Строка внизу по центру на sec секунд (реплики клиента).
func show_line(text: String, sec := 4.0) -> void:
	_line.text = text
	_line_left = sec
	_line.modulate.a = 1.0
	_line.visible = true

## Последняя реплика, пока не погасла (видна строкой внизу или пузырём над говорящим).
func line_text() -> String:
	return _line.text if _line_left > 0.0 else ""

## Большая табличка по центру сверху: итог смены и т.п.
## stars ≥ 0 — ряд из пяти звёзд под заголовком; hide_after > 0 — спрятать через столько секунд.
func show_banner(title: String, sub := "", good := true, stars := -1, hide_after := 0.0) -> void:
	for c in _banner.get_children():
		c.queue_free()
	for line in [[title, 54, Style.ACCENT if good else Style.DANGER], ["*", 0, null], [sub, 24, Style.TEXT]]:
		if line[0] == "*":
			if stars >= 0:
				_banner.add_child(_stars_row(stars))
			continue
		if line[0] == "":
			continue
		var l: Label = Style.title(line[0], line[1], line[2]) if line[1] > 30 else Style.label(line[0], line[1], line[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Style.outlined(l, 12 if line[1] > 30 else 8)
		_banner.add_child(l)
	_banner.visible = true
	_banner_left = hide_after
	_banner_stars = stars

var _banner_stars := -1

func banner_stars() -> int:
	return _banner_stars if _banner.visible else -1

func _stars_row(n: int) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 5:
		var st := Control.new()
		st.custom_minimum_size = Vector2(54, 54)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var on := i < n
		st.draw.connect(func():
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI / 2 + k * PI / 5
				var r := 25.0 if k % 2 == 0 else 10.5
				pts.append(Vector2(27, 29) + Vector2(cos(a), sin(a)) * r)
			st.draw_colored_polygon(pts, Style.ACCENT if on else Style.PANEL.lightened(0.15))
			pts.append(pts[0])
			st.draw_polyline(pts, Style.BG, 3.0, true))
		row.add_child(st)
	return row

func banner_text() -> String:
	var parts: Array[String] = []
	for c in _banner.get_children():
		if c is Label and not c.is_queued_for_deletion():
			parts.append(c.text)
	return " / ".join(parts) if _banner.visible else ""

var settings_menu: Control

## Настройки поверх паузы (мир при этом идёт дальше, как и в паузе).
func open_settings() -> void:
	if is_instance_valid(settings_menu):
		return
	settings_menu = SettingsMenu.new()
	_root.add_child(settings_menu)

func is_paused() -> bool:
	return _pause.visible

func set_paused(v: bool) -> void:
	if not v and is_instance_valid(settings_menu):
		settings_menu.close()
	_pause.visible = v
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if v else Input.MOUSE_MODE_CAPTURED

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		set_paused(not is_paused())
		get_viewport().set_input_as_handled()

func _to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.to_menu()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
