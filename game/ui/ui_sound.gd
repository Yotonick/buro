extends Node
## Звуки интерфейса (Kenney Interface Sounds) на шине «UI».
## Сам цепляется ко всем кнопкам, галочкам, ползункам и вкладкам, которые появляются в дереве,
## поэтому экранам ничего делать не нужно. Свой звук: UiSound.play("stamp").

const SOUNDS := {
	"hover": preload("res://ui/theme/sounds/hover.ogg"),
	"click": preload("res://ui/theme/sounds/click.ogg"),
	"back": preload("res://ui/theme/sounds/back.ogg"),
	"open": preload("res://ui/theme/sounds/open.ogg"),
	"close": preload("res://ui/theme/sounds/close.ogg"),
	"confirm": preload("res://ui/theme/sounds/confirm.ogg"),
	"error": preload("res://ui/theme/sounds/error.ogg"),
	"toggle": preload("res://ui/theme/sounds/toggle.ogg"),
	"tab": preload("res://ui/theme/sounds/tab.ogg"),
	"pop": preload("res://ui/theme/sounds/pop.ogg"),
	"stamp": preload("res://ui/theme/sounds/stamp.ogg"),
	"paper": preload("res://ui/theme/sounds/paper.ogg"),
}
const VOLUME := {"hover": -14.0, "click": -4.0, "tab": -6.0, "toggle": -6.0}
const POOL := 6

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_hover := 0
var last_played := ""   # для автотестов

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bus := "UI" if AudioServer.get_bus_index("UI") >= 0 else "Master"
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)
	get_tree().node_added.connect(_on_node_added)

func play(name: String) -> void:
	if not SOUNDS.has(name):
		return
	last_played = name
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = SOUNDS[name]
	p.volume_db = VOLUME.get(name, -6.0)
	p.pitch_scale = randf_range(0.96, 1.04)
	p.play()

func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		if n.has_meta("no_sound"):
			return
		n.mouse_entered.connect(_hover.bind(n))
		if n is CheckBox or n is CheckButton:
			n.toggled.connect(func(_on): play("toggle"))
		elif n is OptionButton:
			n.pressed.connect(play.bind("click"))
			n.item_selected.connect(func(_i): play("toggle"))
		else:
			n.pressed.connect(func(): play("back" if n.has_meta("back") else "click"))
	elif n is TabBar:
		n.tab_changed.connect(func(_i): play("tab"))
	elif n is TabContainer:
		n.tab_changed.connect(func(_i): play("tab"))

func _hover(b: BaseButton) -> void:
	if b.disabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hover < 40:   # быстрый проход мышью по списку — не трещать
		return
	_last_hover = now
	play("hover")
