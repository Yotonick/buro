extends CanvasLayer
## Игровой интерфейс поверх мира: подсказка по управлению и пауза (Esc).
## Мир на паузе не останавливается — просто отпускается мышь.

const Style := preload("res://ui/ui_style.gd")

var _hint: Label
var _pause: Control
var _root: Control

func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = Style.make_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_hint = Style.label("", 16, Style.TEXT)
	_hint.add_theme_color_override("font_outline_color", Style.BG)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_hint)

	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0.05, 0.1, 0.15, 0.7)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_root.add_child(_pause)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Style.label("Перекур", 36, Style.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var cont := Button.new()
	cont.text = "Продолжить"
	cont.pressed.connect(set_paused.bind(false))
	box.add_child(cont)
	var quit := Button.new()
	quit.text = "В меню"
	quit.pressed.connect(_to_menu)
	box.add_child(quit)
	set_paused(false)

func set_hint(text: String) -> void:
	_hint.text = text

func is_paused() -> bool:
	return _pause.visible

func set_paused(v: bool) -> void:
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
