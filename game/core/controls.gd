extends Node
## Раскладка управления. Действия создаются кодом, чтобы раскладка жила в одном месте
## (позже сюда добавятся геймпад и переназначение клавиш).

func _ready() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE])
	_key("use", [KEY_E])
	_key("flop", [KEY_F])
	_key("laugh", [KEY_T])
	_key("respawn", [KEY_R])
	_key("pause", [KEY_ESCAPE])
	_mouse("grab_left", MOUSE_BUTTON_LEFT)
	_mouse("grab_right", MOUSE_BUTTON_RIGHT)

func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)

func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)
