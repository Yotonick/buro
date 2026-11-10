extends Control
## Лобби: список бригады и IP для друзей. Хост нажимает «Начать смену» —
## и вся бригада попадает на уровень.

const Style := preload("res://ui/ui_style.gd")

var _list: VBoxContainer
var _count: Label

func _ready() -> void:
	theme = Style.make_theme()
	add_child(Style.background())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	box.add_child(Style.label("Бригада", 36, Style.ACCENT))
	_count = Style.label("", 18, Style.MUTED)
	box.add_child(_count)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.custom_minimum_size = Vector2(0, 220)
	box.add_child(_list)

	if Net.is_host():
		var hint := Style.label(_host_hint(), 18, Style.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hint)

	if Net.is_host():
		var start := Button.new()
		start.text = "Начать смену (полигон)"
		start.pressed.connect(func(): Game.start_match())
		box.add_child(start)
		start.grab_focus()
	else:
		box.add_child(Style.label("Ждём, когда хост начнёт смену…", 18, Style.MUTED))

	var leave := Button.new()
	leave.text = "Закрыть игру" if Net.is_host() else "Выйти из бригады"
	leave.pressed.connect(_on_leave)
	box.add_child(leave)

	Net.players_changed.connect(_refresh)
	_refresh()

func _host_hint() -> String:
	var radmin: Array[String] = []
	for a in IP.get_local_addresses():
		if a.begins_with("26."):
			radmin.append(a)
	if radmin.is_empty():
		return "Radmin VPN не найден. Запустите его — друзья подключаются по вашему Radmin-IP (вида 26.x.x.x)."
	return "Ваш Radmin-IP для друзей: %s" % ", ".join(radmin)

func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	_count.text = "%d из %d" % [ids.size(), Net.MAX_PLAYERS]
	for id in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var chip := ColorRect.new()
		chip.color = Net.color_of(id)
		chip.custom_minimum_size = Vector2(28, 28)
		row.add_child(chip)
		var text: String = Net.players[id]["name"]
		if id == 1:
			text += "  (хост)"
		if id == Net.local_id():
			text += "  — это вы"
		row.add_child(Style.label(text))
		_list.add_child(row)

func _on_leave() -> void:
	Net.leave()
	get_tree().change_scene_to_file(Game.MENU)
