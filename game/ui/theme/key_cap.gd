extends Control
## Клавиша на экране: нарисованный колпачок с подписью или значок мыши.
## Если задано action — подпись берётся из текущей раскладки (core/controls.gd)
## и обновляется сама при переназначении.

const HEAD: FontFile = preload("res://ui/theme/fonts/RussoOne-Regular.ttf")
const MOUSE := {
	MOUSE_BUTTON_LEFT: preload("res://ui/theme/icons/mouse_left.svg"),
	MOUSE_BUTTON_RIGHT: preload("res://ui/theme/icons/mouse_right.svg"),
	MOUSE_BUTTON_MIDDLE: preload("res://ui/theme/icons/mouse_wheel.svg"),
}
const NAMES := {
	KEY_SPACE: "Пробел", KEY_CTRL: "Ctrl", KEY_SHIFT: "Shift", KEY_ALT: "Alt",
	KEY_ESCAPE: "Esc", KEY_ENTER: "Enter", KEY_TAB: "Tab", KEY_BACKSPACE: "⌫",
	KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→", KEY_CAPSLOCK: "Caps",
}
const FACE := Color("f4efe4")
const EDGE := Color("9aa7b8")
const INK := Color("14233a")

var action := "":
	set(v):
		action = v
		_update()
var text := "":
	set(v):
		text = v
		_update()
var cap_height := 34.0:
	set(v):
		cap_height = v
		_update()

var _shown := ""
var _icon: Texture2D

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	var c := get_node_or_null("/root/Controls")
	if c and c.has_signal("bindings_changed"):
		c.bindings_changed.connect(_update)
	_update()

## Подпись для события ввода: «E», «Пробел», «ЛКМ»…
static func event_label(e: InputEvent) -> String:
	if e is InputEventKey:
		var k: Key = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		if NAMES.has(k):
			return NAMES[k]
		return OS.get_keycode_string(k)
	if e is InputEventMouseButton:
		return {MOUSE_BUTTON_LEFT: "ЛКМ", MOUSE_BUTTON_RIGHT: "ПКМ", MOUSE_BUTTON_MIDDLE: "СКМ",
			MOUSE_BUTTON_WHEEL_UP: "Колесо ↑", MOUSE_BUTTON_WHEEL_DOWN: "Колесо ↓"}.get(e.button_index, "Мышь %d" % e.button_index)
	return "?"

## Подпись первой клавиши действия (для текста подсказок).
static func action_label(act: String) -> String:
	if not InputMap.has_action(act):
		return act
	var ev := InputMap.action_get_events(act)
	return event_label(ev[0]) if ev.size() > 0 else "—"

func _update() -> void:
	_icon = null
	_shown = text
	if action != "" and InputMap.has_action(action):
		var ev := InputMap.action_get_events(action)
		if ev.size() > 0:
			var e: InputEvent = ev[0]
			if e is InputEventMouseButton and MOUSE.has(e.button_index):
				_icon = MOUSE[e.button_index]
			_shown = event_label(e)
		else:
			_shown = "—"
	var w := cap_height
	if _icon == null:
		var fs := _font_size()
		w = maxf(cap_height, HEAD.get_string_size(_shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + cap_height * 0.55)
	else:
		w = cap_height
	custom_minimum_size = Vector2(w, cap_height)
	tooltip_text = ""
	queue_redraw()

func _font_size() -> int:
	return maxi(14, int(cap_height * (0.52 if _shown.length() <= 2 else 0.44)))

func shown_text() -> String:
	return _shown

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size if size.x > 0 else custom_minimum_size)
	if _icon:
		var s := r.size.y * 1.15
		draw_texture_rect(_icon, Rect2(Vector2((r.size.x - s) / 2.0, (r.size.y - s) / 2.0), Vector2(s, s)), false)
		return
	var edge := StyleBoxFlat.new()
	edge.bg_color = EDGE
	edge.set_corner_radius_all(int(cap_height * 0.22))
	edge.set_border_width_all(2)
	edge.border_color = INK
	edge.anti_aliasing = true
	draw_style_box(edge, r)
	var face := StyleBoxFlat.new()
	face.bg_color = FACE
	face.set_corner_radius_all(int(cap_height * 0.18))
	face.anti_aliasing = true
	var depth := maxf(3.0, cap_height * 0.12)
	draw_style_box(face, Rect2(r.position + Vector2(3, 2), r.size - Vector2(6, depth + 4)))
	var fs := _font_size()
	var ts := HEAD.get_string_size(_shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var base := Vector2((r.size.x - ts.x) / 2.0, (r.size.y - depth) / 2.0 + fs * 0.36)
	draw_string(HEAD, base, _shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
