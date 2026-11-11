extends Node
## Автотест настроек (без экрана):
##   godot --headless --path game --fixed-fps 60 --disable-render-loop res://tests/settings_test.tscn
## Переназначение клавиш, конфликты, сохранение и загрузка, графика, звук, поле зрения, подсказки.

const SettingsMenu := preload("res://ui/settings_menu.gd")
const Style := preload("res://ui/ui_style.gd")
const CameraScript := preload("res://characters/player_camera.gd")

var fails := 0
var _signals := 0

func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	Settings.reset_controls()
	Settings.reset_graphics()
	Settings.reset_audio()
	Controls.reload()
	Controls.bindings_changed.connect(func(): _signals += 1)
	await _run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	print("RESULT ", "PASS" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit(fails)

func _check(name: String, ok: bool, info := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, info])
	if not ok:
		fails += 1

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = true
	return e

func _has_key(action: String, k: Key) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and e.physical_keycode == k:
			return true
	return false

func _run() -> void:
	# --- Раскладка ---
	_check("по умолчанию: использовать — E", _has_key("use", KEY_E))
	var cap: Control = Style.key("use", 30)
	add_child(cap)
	await _frames(1)
	_check("колпачок показывает E", cap.shown_text() == "E", cap.shown_text())

	var before := _signals
	Controls.set_binding("use", 0, _key(KEY_G))
	_check("переназначили на G — InputMap", _has_key("use", KEY_G) and not _has_key("use", KEY_E))
	_check("сигнал bindings_changed", _signals > before)
	_check("колпачок перерисовался на G", cap.shown_text() == "G", cap.shown_text())

	Controls.set_binding("jump", 1, _key(KEY_G))
	var conf := Controls.conflicts()
	_check("конфликт G: использовать + прыжок", conf.has("key:%d" % KEY_G) and conf["key:%d" % KEY_G].size() == 2, str(conf))

	Settings.save()
	Settings.bindings = {}
	Controls.reload()
	_check("без сохранённого — снова E", _has_key("use", KEY_E))
	Settings.load_file()
	Controls.reload()
	_check("из файла: использовать — G, прыжок — Пробел + G",
		_has_key("use", KEY_G) and _has_key("jump", KEY_SPACE) and _has_key("jump", KEY_G))

	Controls.reset_action("use")
	Controls.reset_action("jump")
	_check("«как было» — E и без конфликтов", _has_key("use", KEY_E) and Controls.conflicts().is_empty())
	_check("заводские клавиши не хранятся в файле", Settings.bindings.is_empty(), str(Settings.bindings))

	# --- Окно настроек: переназначение кликом ---
	var m: Control = SettingsMenu.new()
	add_child(m)
	await _frames(2)
	_check("три вкладки", m.tabs.get_tab_count() == 3 and m.tabs.get_tab_title(0) == "Управление")
	_check("гнездо «Использовать» — E", m.slot_text("use", 0) == "E", m.slot_text("use", 0))
	_check("гнездо «Левая рука» — ЛКМ", m.slot_text("grab_left", 0) == "ЛКМ", m.slot_text("grab_left", 0))
	m._start_wait("use", 0)
	_check("ждёт клавишу", m.slot_text("use", 0) == "Нажми клавишу…", m.slot_text("use", 0))
	m.feed_binding(_key(KEY_H))
	await _frames(1)
	_check("нажали H — встала", _has_key("use", KEY_H) and m.slot_text("use", 0) == "H", m.slot_text("use", 0))
	m._start_wait("jump", 0)
	m.feed_binding(_key(KEY_H))
	await _frames(1)
	_check("H на прыжке — оба гнезда красные", m.slot_conflict("use", 0) and m.slot_conflict("jump", 0))
	_check("внизу написано, где занята", "Прыжок" in m.conflict_text() and "Использовать" in m.conflict_text(), m.conflict_text())
	m._start_wait("jump", 0)
	m.feed_binding(_key(KEY_ESCAPE))
	await _frames(1)
	_check("Esc — отмена, H осталась", _has_key("jump", KEY_H) and not m.is_waiting())
	m._start_wait("jump", 0)
	m.feed_binding(_key(KEY_BACKSPACE))
	await _frames(1)
	_check("Backspace — гнездо пустое, конфликта нет", not _has_key("jump", KEY_H) and m.slot_text("jump", 0) == "—"
		and not m.slot_conflict("use", 0), m.slot_text("jump", 0))
	m._start_wait("grab_right", 1)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_MIDDLE
	mb.pressed = true
	m.feed_binding(mb)
	await _frames(1)
	_check("кнопка мыши: правая рука + колесо", m.slot_text("grab_right", 1) == "СКМ", m.slot_text("grab_right", 1))

	m.tabs.current_tab = 0
	m._reset_tab()
	await _frames(1)
	_check("сброс вкладки — всё по-заводски", _has_key("use", KEY_E) and _has_key("jump", KEY_SPACE)
		and InputMap.action_get_events("grab_right").size() == 1 and Settings.bindings.is_empty())

	# --- Мышь и подсказки ---
	var cam := CameraScript.new()
	add_child(cam)
	await _frames(1)
	m._sens.value = 2.0
	m._invert.button_pressed = true
	_check("чувствительность и инверсия", is_equal_approx(Settings.mouse_sens, 2.0) and Settings.invert_y)
	var hud: CanvasLayer = load("res://ui/game_hud.gd").new()
	add_child(hud)
	await _frames(1)
	hud.set_hint("подсказка")
	m._hints.button_pressed = false
	_check("выключили подсказки — строка спряталась", not hud._hint.visible)
	m._hints.button_pressed = true
	_check("включили — видна", hud._hint.visible)

	# --- Графика ---
	m.tabs.current_tab = 1
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	add_child(sun)
	await _frames(2)
	_check("на «Средне» тени у света есть", sun.shadow_enabled)
	m._g.preset.select(0)
	m._g.preset.item_selected.emit(0)
	await _frames(1)
	_check("«Низко»: тени выкл, масштаб 75%", Settings.shadows == 0 and not sun.shadow_enabled
		and is_equal_approx(get_tree().root.scaling_3d_scale, 0.75), "scale %.2f" % get_tree().root.scaling_3d_scale)
	_check("«Низко»: ползунок масштаба 75%", is_equal_approx(m._g.scale[0].value, 0.75) and m._g.scale[1].text == "75%")
	var lamp := OmniLight3D.new()
	lamp.shadow_enabled = true
	add_child(lamp)
	await _frames(2)
	_check("новая лампа на «Низко» — тоже без теней", not lamp.shadow_enabled)
	m._g.preset.select(2)
	m._g.preset.item_selected.emit(2)
	await _frames(1)
	_check("«Высоко»: MSAA 4×, тени вернулись", get_tree().root.msaa_3d == Viewport.MSAA_4X and sun.shadow_enabled and lamp.shadow_enabled)
	m._g.shadows.select(1)
	m._g.shadows.item_selected.emit(1)
	_check("поменяли тени — пресет «Своё»", Settings.preset == "custom" and m._g.preset.selected == 3)
	m._g.aa.select(3)
	m._g.aa.item_selected.emit(3)
	m._g.shadows.select(2)
	m._g.shadows.item_selected.emit(2)
	_check("вернули как в «Высоко» — снова «Высоко»", Settings.preset == "high" and m._g.preset.selected == 2)
	m._g.fps.select(1)
	m._g.fps.item_selected.emit(1)
	_check("ограничение 60 кадров", Engine.max_fps == 60)
	m._g.fov[0].value = 80.0
	await _frames(1)
	_check("поле зрения 80° — у камеры сразу", is_equal_approx(cam.camera.fov, 80.0), "%.1f" % cam.camera.fov)

	# --- Звук ---
	m.tabs.current_tab = 2
	m._vol["Master"][0].value = 0.5
	var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	_check("общая 50% ≈ −6 дБ", absf(db - linear_to_db(0.5)) < 0.1, "%.2f дБ" % db)
	m._vol["SFX"][0].value = 0.0
	_check("эффекты 0 — шина выключена", AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) and m._vol["SFX"][1].text == "выкл")
	m._reset_tab()
	_check("сброс звука", is_equal_approx(Settings.volume["SFX"], 1.0) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))

	# --- Закрытие и файл ---
	m._sens.value = 1.5
	var esc := _key(KEY_ESCAPE)
	Input.parse_input_event(esc)
	await _frames(3)
	_check("Esc закрыл окно", not is_instance_valid(m) or m.is_queued_for_deletion())
	var cfg := ConfigFile.new()
	var ok := cfg.load(Settings.PATH) == OK
	_check("сохранилось в settings.cfg", ok and is_equal_approx(float(cfg.get_value("controls", "mouse_sens", 0)), 1.5)
		and str(cfg.get_value("graphics", "preset", "")) == "high" and is_equal_approx(float(cfg.get_value("graphics", "fov", 0)), 80.0))

	# --- Пауза → настройки ---
	hud.set_paused(true)
	hud.open_settings()
	await _frames(2)
	_check("из паузы открываются настройки", is_instance_valid(hud.settings_menu) and hud.settings_menu.is_inside_tree())
	hud.set_paused(false)
	await _frames(2)
	_check("закрыли паузу — настройки тоже", not is_instance_valid(hud.settings_menu) or hud.settings_menu.is_queued_for_deletion())

	Settings.reset_graphics()
	Settings.apply_graphics()
