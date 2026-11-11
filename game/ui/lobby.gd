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
	var panel := Style.plate(true)
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	head.add_child(Style.logo(56))
	head.add_child(Style.title("БРИГАДА", 40))
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(pad)
	_count = Style.title("", 28, Style.MUTED)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.custom_minimum_size = Vector2(0, 0)
	box.add_child(_list)

	if Net.is_host():
		var note := Style.sticker(_host_hint(), 1.5, 340.0, 24)
		note.size_flags_horizontal = Control.SIZE_SHRINK_END
		box.add_child(note)
		box.add_child(Style.spacer(6))
		var start := Style.button("Вызов: подводный ресторан «Глубокая тарелка»", func(): Game.start_match("deep_plate"), "primary")
		box.add_child(start)
		start.grab_focus()
		box.add_child(Style.button("Полигон (потренироваться)", func(): Game.start_match("polygon")))
	else:
		var wait := Style.label("Ждём, когда хост выберет вызов…", 20, Style.MUTED)
		wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(wait)

	var leave := Style.button("Закрыть игру" if Net.is_host() else "Выйти из бригады", _on_leave, "danger")
	leave.set_meta("back", true)
	box.add_child(leave)

	Net.players_changed.connect(_refresh)
	_refresh()

func _host_hint() -> String:
	var radmin: Array[String] = []
	for a in IP.get_local_addresses():
		if a.begins_with("26."):
			radmin.append(a)
	if radmin.is_empty():
		return "Radmin VPN не найден! Запусти его — друзья подключаются по твоему Radmin-IP (26.x.x.x)."
	return "IP для друзей: %s" % ", ".join(radmin)

func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	_count.text = "%d из %d" % [ids.size(), Net.MAX_PLAYERS]
	for id in ids:
		_list.add_child(_player_row(id))
	for i in range(ids.size(), Net.MAX_PLAYERS):
		var empty := Style.label("— свободное место —", 18, Style.MUTED.darkened(0.3))
		empty.custom_minimum_size = Vector2(0, 42)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list.add_child(empty)

## Строка бригады: каска цвета игрока, имя, пометки.
func _player_row(id: int) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 42)
	row.add_theme_constant_override("separation", 14)
	var col := Net.color_of(id)
	var helmet := Control.new()
	helmet.custom_minimum_size = Vector2(44, 44)
	helmet.draw.connect(func():
		helmet.draw_circle(Vector2(22, 26), 18, Style.NAVY_DEEP)
		helmet.draw_arc(Vector2(22, 26), 16, PI, TAU, 24, col, 16.0, true)
		helmet.draw_rect(Rect2(2, 26, 40, 6), col.darkened(0.2))
		helmet.draw_rect(Rect2(20, 9, 4, 10), col.lightened(0.25)))
	row.add_child(helmet)
	var name_l := Style.title(str(Net.players[id]["name"]), 24, Style.TEXT)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_l)
	var tags: Array[String] = []
	if id == 1:
		tags.append("бригадир")
	if id == Net.local_id():
		tags.append("это ты")
	if not tags.is_empty():
		var t := Style.label("· " + " · ".join(tags), 18, Style.MUTED)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
	return row

func _on_leave() -> void:
	Net.leave()
	get_tree().change_scene_to_file(Game.MENU)
