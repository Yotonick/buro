extends Node3D
## Основа любого уровня: общий мир (NetWorld), появление игроков, своя камера,
## управление и интерфейс. Конкретный уровень наследуется и переопределяет
## _build() (постройка), spawn_point() и при необходимости _tick().
##
## Уровень не думает о сети: он строится одинаково у всех, а «живую» логику
## (_tick) выполняет только та машина, что считает физику.

const Kit := preload("res://levels/level_kit.gd")
const NetWorld := preload("res://net/net_world.gd")
const HelmetProp := preload("res://characters/kombez/helmet_prop.gd")
const CameraScript := preload("res://characters/player_camera.gd")
const ControllerScript := preload("res://characters/player_controller.gd")
const Tape := preload("res://physics/tape.gd")
const TapeRoll := preload("res://tools/tape_roll.gd")
const HudScript := preload("res://ui/game_hud.gd")

const FALL_Y := -15.0

var world: Node                ## NetWorld
var player: Kombez             ## свой персонаж (у клиента появляется чуть позже загрузки)
var camera: Node3D
var controller: Node
var hud: CanvasLayer
## Советы-стикеры в начале смены: [[id, текст], …] — уровень заполняет в _build().
## Остальные советы уровень показывает сам по событиям: hud.tip(id, текст).
var intro_tips: Array = []

var _players := {}             ## peer -> Kombez
var _slots := {}               ## peer -> номер места (цвет, точка появления)
var _tip_t := 0.0

# --- переопределяется уровнем ---

func _build() -> void:
	pass

func _tick(_dt: float) -> void:
	pass

func spawn_point(slot: int) -> Vector3:
	return Vector3(slot * 1.6, 1.0, 0.0)

# --- общее ---

func _ready() -> void:
	world = NetWorld.new()
	world.name = "NetWorld"
	add_child(world)
	world.add_spawner("kombez", _make_kombez)
	world.add_spawner("helmet", HelmetProp.create)
	world.add_spawner("tape", Tape.create)
	world.add_spawner("tape_roll", TapeRoll.create)
	world.spawned.connect(_on_spawned)
	world.player_action.connect(_on_player_action)

	_build()
	world.track_tree(self)

	camera = CameraScript.new()
	add_child(camera)
	camera.global_position = spawn_point(0) + Vector3.UP * 0.7
	controller = ControllerScript.new()
	controller.camera = camera
	add_child(controller)
	hud = HudScript.new()
	add_child(hud)
	hud.attach_world(world)
	for t in intro_tips:
		hud.tip(t[0], t[1], 10.0)

	if world.is_authority():
		if Net.in_session():
			var ids := Net.players.keys()
			ids.sort()
			for id in ids:
				_spawn_player(id)
			Net.player_joined.connect(_spawn_player)
		else:
			_spawn_player(1)
	Net.player_left.connect(_remove_player)
	world.start()

func _spawn_player(id: int) -> void:
	var slot := 0
	var pname := ""
	if Net.players.has(id):
		slot = int(Net.players[id]["slot"])
		pname = str(Net.players[id]["name"])
	world.spawn("kombez", {"peer": id, "slot": slot, "name": pname,
		"color": Net.PLAYER_COLORS[slot % Net.PLAYER_COLORS.size()], "pos": spawn_point(slot)})

func _make_kombez(params: Dictionary) -> Node:
	var k := Kombez.new()
	k.peer_id = int(params.get("peer", 0))
	k.player_name = str(params.get("name", ""))
	k.suit_color = params.get("color", k.suit_color)
	k.position = params.get("pos", Vector3.ZERO)
	return k

func _on_spawned(node: Node, kind: String, params: Dictionary) -> void:
	if kind != "kombez":
		return
	var k: Kombez = node
	if k.peer_id <= 0:
		return
	_players[k.peer_id] = k
	_slots[k.peer_id] = int(params.get("slot", 0))
	if k.peer_id == world.local_peer():
		player = k
		camera.target = k
		camera.snap()
		controller.kombez = k
		world.local_kombez = k

func _remove_player(id: int) -> void:
	var k: Kombez = _players.get(id)
	_players.erase(id)
	_slots.erase(id)
	if world.is_authority() and is_instance_valid(k):
		k.queue_free()

func _on_player_action(peer: int, action: StringName) -> void:
	if action == &"respawn":
		var k: Kombez = _players.get(peer)
		if is_instance_valid(k):
			k.teleport(spawn_point(_slots.get(peer, 0)))

func _physics_process(dt: float) -> void:
	if is_instance_valid(player) and Input.is_action_just_pressed("respawn"):
		world.request_action(&"respawn")
	if not world.is_authority():
		return
	for peer in _players:
		var k: Kombez = _players[peer]
		if is_instance_valid(k) and k.global_position.y < FALL_Y:
			k.teleport(spawn_point(_slots.get(peer, 0)))
	_tick(dt)

func _process(dt: float) -> void:
	_tip_t -= dt
	if _tip_t <= 0.0:
		_tip_t = 0.5
		_check_tips()

## Советы по событиям — смотрит каждые полсекунды (у всех: состояние приходит по сети).
## Уровень может дополнить, вызвав super().
func _check_tips() -> void:
	if not is_instance_valid(player):
		return
	for t in get_tree().get_nodes_in_group("tool"):
		if t.get("holder_id") and world.node_of(t.holder_id) == player:
			hud.tip("belt", "Рулон на поясе, руки свободны. %s — клеить туда, куда смотришь: раз — конец, второй раз — примотал. %s — бросить рулон."
				% [hud.key_name("use"), hud.key_name("drop_tool")])
