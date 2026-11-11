extends Node
## Раскладка управления. Действия создаются кодом, чтобы раскладка жила в одном месте.
## У каждого действия два места под клавишу (основная и запасная). Переназначенное
## хранится в Settings.bindings ("key:<physical_keycode>" / "mouse:<кнопка>" / "" — пусто)
## и сохраняется в user://settings.cfg. После любой перемены — сигнал bindings_changed.

signal bindings_changed   # клавиши переназначены — подсказки перерисовываются

const SLOTS := 2

## Действия по порядку, как они идут в настройках: [действие, подпись].
const ACTIONS := [
	["move_forward", "Вперёд"],
	["move_back", "Назад"],
	["move_left", "Влево"],
	["move_right", "Вправо"],
	["jump", "Прыжок"],
	["crouch", "Присесть"],
	["grab_left", "Левая рука"],
	["grab_right", "Правая рука"],
	["use", "Использовать / на пояс"],
	["drop_tool", "Бросить инструмент"],
	["flop", "Упасть"],
	["laugh", "Ржать"],
	["respawn", "Встать на место"],
	["tablet", "Планшет"],
	["view_toggle", "Вид: 1-е / 3-е лицо"],
]
## Действия, которые не переназначаются (Esc всегда выход в паузу и отмена).
const FIXED := ["pause"]

const DEFAULTS := {
	"move_forward": ["key:%d" % KEY_W, "key:%d" % KEY_UP],
	"move_back": ["key:%d" % KEY_S, "key:%d" % KEY_DOWN],
	"move_left": ["key:%d" % KEY_A, "key:%d" % KEY_LEFT],
	"move_right": ["key:%d" % KEY_D, "key:%d" % KEY_RIGHT],
	"jump": ["key:%d" % KEY_SPACE, ""],
	"use": ["key:%d" % KEY_E, ""],
	"drop_tool": ["key:%d" % KEY_Q, ""],
	"crouch": ["key:%d" % KEY_CTRL, "key:%d" % KEY_C],
	"flop": ["key:%d" % KEY_F, ""],
	"laugh": ["key:%d" % KEY_T, ""],
	"respawn": ["key:%d" % KEY_R, ""],
	"tablet": ["key:%d" % KEY_TAB, ""],
	"view_toggle": ["key:%d" % KEY_V, ""],
	"pause": ["key:%d" % KEY_ESCAPE, ""],
	"grab_left": ["mouse:%d" % MOUSE_BUTTON_LEFT, ""],
	"grab_right": ["mouse:%d" % MOUSE_BUTTON_RIGHT, ""],
}

func _ready() -> void:
	for a in DEFAULTS:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	_apply_all()

## Текущие клавиши действия: массив из SLOTS строк-кодов.
func codes(action: String) -> Array:
	var c: Array = Settings.bindings.get(action, DEFAULTS.get(action, [])).duplicate()
	while c.size() < SLOTS:
		c.append("")
	return c.slice(0, SLOTS)

## Поставить клавишу в место slot (event = null — очистить место).
func set_binding(action: String, slot: int, event: InputEvent) -> void:
	if not DEFAULTS.has(action) or action in FIXED or slot < 0 or slot >= SLOTS:
		return
	var c := codes(action)
	c[slot] = encode(event) if event != null else ""
	if c == _padded(DEFAULTS[action]):
		Settings.bindings.erase(action)
	else:
		Settings.bindings[action] = c
	_apply(action)
	bindings_changed.emit()

## Вернуть одно действие к заводским клавишам.
func reset_action(action: String) -> void:
	Settings.bindings.erase(action)
	_apply(action)
	bindings_changed.emit()

## Вернуть всё (после Settings.reset_controls() или загрузки).
func reload() -> void:
	_apply_all()
	bindings_changed.emit()

## Конфликты: код клавиши -> список действий, где он стоит (только где больше одного).
func conflicts() -> Dictionary:
	var used := {}
	for a in DEFAULTS:
		for code in codes(a):
			if code == "":
				continue
			if not used.has(code):
				used[code] = []
			if not (a in used[code]):
				used[code].append(a)
	var out := {}
	for code in used:
		if used[code].size() > 1:
			out[code] = used[code]
	return out

static func title_of(action: String) -> String:
	for p in ACTIONS:
		if p[0] == action:
			return p[1]
	return "Пауза" if action == "pause" else action

static func encode(e: InputEvent) -> String:
	if e is InputEventKey:
		var k: Key = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		return "key:%d" % k
	if e is InputEventMouseButton:
		return "mouse:%d" % e.button_index
	return ""

static func decode(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var n := int(parts[1])
	if parts[0] == "key":
		var e := InputEventKey.new()
		e.physical_keycode = n as Key
		return e
	if parts[0] == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = n as MouseButton
		return m
	return null

func _padded(a: Array) -> Array:
	var c := a.duplicate()
	while c.size() < SLOTS:
		c.append("")
	return c

func _apply_all() -> void:
	for a in DEFAULTS:
		_apply(a)

func _apply(action: String) -> void:
	InputMap.action_erase_events(action)
	for code in codes(action):
		var e := decode(code)
		if e != null:
			InputMap.action_add_event(action, e)
