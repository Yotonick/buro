extends Node
## Сетевая сессия: соединение и список игроков.
## Ничего не знает про уровни, персонажей и UI — общается сигналами.

signal session_started                 ## мы в сессии (как хост или клиент)
signal session_ended(reason: String)   ## сессия закончилась; reason пуст при обычном выходе
signal players_changed
signal player_joined(id: int)
signal player_left(id: int)

const EnetTransport := preload("res://net/enet_transport.gd")
const NetTransport := preload("res://net/net_transport.gd")

const MAX_PLAYERS := 4
const PROTOCOL_VERSION := 10
const CONNECT_TIMEOUT := 8.0
const MAX_NAME_LENGTH := 16
const PLAYER_COLORS: Array[Color] = [
	Color("378add"), Color("d85a30"), Color("1d9e75"), Color("ef9f27"),
]

## id -> { "name": String, "slot": int }. Слот определяет цвет.
var players: Dictionary = {}
var _transport: NetTransport
var _connect_timer: SceneTreeTimer
var _in_session := false

func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func in_session() -> bool:
	return _in_session

func is_host() -> bool:
	return _in_session and multiplayer.is_server()

func local_id() -> int:
	return multiplayer.get_unique_id() if _in_session else 0

func color_of(id: int) -> Color:
	if not players.has(id):
		return Color.WHITE
	return PLAYER_COLORS[int(players[id]["slot"]) % PLAYER_COLORS.size()]

## Создать игру. Возвращает пустую строку или текст ошибки.
func host_game(player_name: String, port: int) -> String:
	leave()
	_transport = EnetTransport.new()
	var peer := _transport.create_host(port, MAX_PLAYERS)
	if peer == null:
		return _transport.last_error
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": _clean_name(player_name), "slot": 0}}
	_in_session = true
	session_started.emit()
	players_changed.emit()
	return ""

## Подключиться к хосту. Результат придёт сигналом session_started / session_ended.
func join_game(player_name: String, address: String, port: int) -> String:
	leave()
	_transport = EnetTransport.new()
	var peer := _transport.create_client(address.strip_edges(), port)
	if peer == null:
		return _transport.last_error
	multiplayer.multiplayer_peer = peer
	_pending_name = player_name
	_connect_timer = get_tree().create_timer(CONNECT_TIMEOUT)
	_connect_timer.timeout.connect(_on_connect_timeout.bind(_connect_timer))
	return ""

func leave() -> void:
	_end_session("", false)

var _pending_name := ""

func _end_session(reason: String, notify := true) -> void:
	var was_active := _in_session or _connect_timer != null
	_connect_timer = null
	_in_session = false
	players = {}
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if was_active and notify:
		session_ended.emit(reason)

func _clean_name(raw: String) -> String:
	var n := raw.strip_edges().replace("\n", " ").left(MAX_NAME_LENGTH)
	return n if n != "" else "Ремонтник"

func _unique_name(wanted: String) -> String:
	var taken := {}
	for p in players.values():
		taken[p["name"]] = true
	if not taken.has(wanted):
		return wanted
	var i := 2
	while taken.has("%s %d" % [wanted, i]):
		i += 1
	return "%s %d" % [wanted, i]

func _free_slot() -> int:
	var used := {}
	for p in players.values():
		used[int(p["slot"])] = true
	for i in MAX_PLAYERS:
		if not used.has(i):
			return i
	return -1

# --- клиент ---

func _on_connected_to_server() -> void:
	_request_join.rpc_id(1, PROTOCOL_VERSION, _pending_name)

func _on_connection_failed() -> void:
	_end_session("Не удалось подключиться. Проверьте IP и что хост создал игру.")

func _on_connect_timeout(timer: SceneTreeTimer) -> void:
	if timer == _connect_timer and not _in_session:
		_end_session("Хост не отвечает. Проверьте Radmin VPN, IP и что хост создал игру.")

func _on_server_disconnected() -> void:
	_end_session(_reject_reason if _reject_reason != "" else "Хост закрыл игру или связь потеряна.")
	_reject_reason = ""

var _reject_reason := ""

@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	_reject_reason = reason

@rpc("authority", "call_remote", "reliable")
func _sync_players(data: Dictionary) -> void:
	var old := players
	players = data
	if not _in_session:
		_in_session = true
		_connect_timer = null
		session_started.emit()
	for id in players:
		if not old.has(id):
			player_joined.emit(id)
	for id in old:
		if not players.has(id):
			player_left.emit(id)
	players_changed.emit()

# --- хост ---

@rpc("any_peer", "call_remote", "reliable")
func _request_join(version: int, player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		return
	var reason := ""
	if version != PROTOCOL_VERSION:
		reason = "Разные версии игры: у хоста %d, у вас %d. Обновите игру." % [PROTOCOL_VERSION, version]
	elif _free_slot() < 0:
		reason = "В бригаде уже нет мест (максимум %d)." % MAX_PLAYERS
	if reason != "":
		_rejected.rpc_id(id, reason)
		get_tree().create_timer(0.5).timeout.connect(_kick.bind(id))
		return
	players[id] = {"name": _unique_name(_clean_name(player_name)), "slot": _free_slot()}
	_sync_players.rpc(players)
	player_joined.emit(id)
	players_changed.emit()

func _kick(id: int) -> void:
	if _in_session and multiplayer.is_server() and id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(id)

func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not players.has(id):
		return
	players.erase(id)
	_sync_players.rpc(players)
	player_left.emit(id)
	players_changed.emit()
