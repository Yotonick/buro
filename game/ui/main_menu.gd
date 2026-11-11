extends Control
## Главное меню: эмблема бюро слева, «проходная» справа — имя, создать игру, подключиться по IP,
## одиночные выезды. (Позже фоном станет 3D-гараж бюро — см. план «визуал и интерфейс».)

const Style := preload("res://ui/ui_style.gd")

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _buttons: Array[Button] = []

func _ready() -> void:
	theme = Style.make_theme()
	add_child(Style.background())
	_edge_stripes()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 64)
	center.add_child(row)

	# Слева — вывеска бюро.
	var brand := VBoxContainer.new()
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", 6)
	brand.custom_minimum_size = Vector2(430, 0)
	row.add_child(brand)
	var logo := Style.logo(170)
	brand.add_child(logo)
	for line in ["БЮРО", "НЕВОЗМОЖНОГО", "РЕМОНТА"]:
		var t := Style.title(line, 50 if line != "НЕВОЗМОЖНОГО" else 44)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		brand.add_child(t)
	brand.add_child(Style.spacer(10))
	var slogan := Style.sticker("Чиним то, что чинить не стоило", -3.0, 0.0, 30)
	slogan.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	brand.add_child(slogan)

	# Справа — проходная.
	var panel := Style.plate(true)
	panel.custom_minimum_size = Vector2(500, 0)
	row.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	box.add_child(_caption("Имя ремонтника"))
	_name_edit = LineEdit.new()
	_name_edit.text = Settings.player_name
	_name_edit.max_length = Net.MAX_NAME_LENGTH
	box.add_child(_name_edit)
	box.add_child(Style.spacer(4))
	box.add_child(_button("Создать игру", _on_host, "primary"))
	box.add_child(Style.spacer(6))

	box.add_child(_caption("Подключиться к другу — его IP из Radmin VPN (26.x.x.x)"))
	var ip_row := HBoxContainer.new()
	box.add_child(ip_row)
	_ip_edit = LineEdit.new()
	_ip_edit.text = Settings.last_address
	_ip_edit.placeholder_text = "26.123.45.67"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.text_submitted.connect(func(_t): _on_join())
	ip_row.add_child(_ip_edit)
	ip_row.add_child(_button("Подключиться", _on_join))

	_status = Style.label("", 18, Style.DANGER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 26)
	box.add_child(_status)

	box.add_child(_caption("Один, без сети"))
	var solo := HBoxContainer.new()
	box.add_child(solo)
	for b in [_button("«Глубокая тарелка»", func(): Game.open_level("deep_plate")),
			_button("Полигон", func(): Game.open_playground())]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		solo.add_child(b)
	box.add_child(Style.spacer(4))
	var quit := _button("Выход", func(): get_tree().quit(), "danger")
	quit.set_meta("back", true)
	box.add_child(quit)

	var ver := Style.label("v" + str(ProjectSettings.get_setting("application/config/version")), 15, Style.MUTED)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 26)
	add_child(ver)

	if Game.pending_message != "":
		_status.text = Game.pending_message
		Game.pending_message = ""
	_name_edit.grab_focus()

func _edge_stripes() -> void:
	for top in [true, false]:
		var s := Style.stripe(12)
		s.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			s.offset_bottom = 12
		else:
			s.offset_top = -12
		add_child(s)

func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "MutedLabel"
	return l

func _button(text: String, action: Callable, kind := "") -> Button:
	var b := Style.button(text, action, kind)
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
		UiSound.play("error")

func _on_join() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip == "":
		_status.text = "Введите IP хоста."
		UiSound.play("error")
		return
	Settings.last_address = ip
	var err := Net.join_game(_save_name(), ip, Settings.port)
	if err != "":
		_status.text = err
		UiSound.play("error")
		return
	_status.add_theme_color_override("font_color", Style.MUTED)
	_status.text = "Подключаемся к %s…" % ip
	for b in _buttons:
		b.disabled = true
