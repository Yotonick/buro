extends Control
## Главное меню: имя, «Создать игру», «Подключиться по IP».

const Style := preload("res://ui/ui_style.gd")

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _buttons: Array[Button] = []

func _ready() -> void:
	theme = Style.make_theme()
	add_child(Style.background())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Style.label("Бюро Невозможного Ремонта", 40, Style.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Style.label("Чиним то, что чинить не стоило", 18, Style.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(_spacer(18))

	box.add_child(Style.label("Имя ремонтника", 18, Style.MUTED))
	_name_edit = LineEdit.new()
	_name_edit.text = Settings.player_name
	_name_edit.max_length = Net.MAX_NAME_LENGTH
	box.add_child(_name_edit)
	box.add_child(_spacer(8))

	box.add_child(_button("Создать игру", _on_host))
	box.add_child(_spacer(8))

	box.add_child(Style.label("IP хоста (из Radmin VPN, вида 26.x.x.x)", 18, Style.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.text = Settings.last_address
	_ip_edit.placeholder_text = "26.123.45.67"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.text_submitted.connect(func(_t): _on_join())
	row.add_child(_ip_edit)
	row.add_child(_button("Подключиться", _on_join))

	_status = Style.label("", 18, Style.DANGER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 56)
	box.add_child(_status)
	box.add_child(_button("Выход", func(): get_tree().quit()))

	var ver := Style.label("v" + str(ProjectSettings.get_setting("application/config/version")), 14, Style.MUTED)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	add_child(ver)

	if Game.pending_message != "":
		_status.text = Game.pending_message
		Game.pending_message = ""
	_name_edit.grab_focus()

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	_buttons.append(b)
	return b

func _save_name() -> String:
	var n := _name_edit.text.strip_edges()
	if n == "":
		n = "Ремонтник"
	Settings.player_name = n
	Settings.save()
	return n

func _on_host() -> void:
	var err := Net.host_game(_save_name(), Settings.port)
	if err != "":
		_status.text = err

func _on_join() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip == "":
		_status.text = "Введите IP хоста."
		return
	Settings.last_address = ip
	var err := Net.join_game(_save_name(), ip, Settings.port)
	if err != "":
		_status.text = err
		return
	_status.add_theme_color_override("font_color", Style.MUTED)
	_status.text = "Подключаемся к %s…" % ip
	for b in _buttons:
		b.disabled = true
