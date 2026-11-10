extends Node
## NetWorld — общий мир для всех игроков. Живёт внутри уровня (узел "NetWorld").
##
## Хост считает всю физику. Клиенты физику не считают: шлют хосту свой ввод
## и показывают мир по снимкам состояния (с небольшой задержкой, плавно).
## В одиночной игре (без сети) этот узел просто ничего не отправляет.
##
## Что синхронизируется:
##  - «статичные» объекты уровня — те, что уровень создал при постройке
##    (одинаковый порядок на всех машинах -> одинаковые номера);
##  - «динамические» — появляются во время игры через spawn() (игроки, каски,
##    позже изолента и инструменты); хост сообщает о них надёжным каналом.

signal spawned(node: Node, kind: String, params: Dictionary)
## Действие игрока, которое решает уровень (например "respawn"). Только на хосте.
signal player_action(peer: int, action: StringName)

const SNAP_EVERY := 1          ## снимок каждые N тиков физики (60 Гц / N)
const DELAY := 2.5             ## клиент показывает мир с отставанием минимум на столько тиков…
const DELAY_MAX := 15.0        ## …и сам добавляет запас, если связь неровная (до стольких)
const REFRESH_TICKS := 120     ## спящий предмет всё равно обновляется раз в столько тиков
const TELEPORT_DIST := 4.0     ## скачок дальше — это телепорт, а не движение
const DYN_BASE := 1000
const T_BODY := 0
const T_KOMBEZ := 1

## Имитация плохой связи для автотестов: [задержка с, разброс с, доля потерь]. В игре пусто.
static var sim_bad_link: Array = []

## Свой персонаж на клиенте: его ввод уходит хосту.
var local_kombez: Kombez:
	set(k):
		local_kombez = k
		if k != null and not is_authority():
			k.action_requested.connect(_send_action)

var _spawners := {}            ## kind -> Callable(params) -> Node
var _nodes := {}               ## id -> Node3D
var _ids := {}                 ## Node3D -> id
var _states := {}              ## id -> Dictionary: состояние объекта (sync_state)
var _dyn := {}                 ## id -> [kind, params]   (только динамические)
var _kombez_by_peer := {}      ## peer -> Kombez
var _next_static := 1
var _next_dyn := DYN_BASE
var _tick := 0

# хост
var _ready_peers := {}         ## peer -> true: уровень загружен, можно слать
var _full_next := false

# клиент
var _tracks := {}              ## id -> Track
var _clock := 0.0              ## какой тик хоста сейчас показываем
var _local_tick := 0
var _offset := 0.0             ## среднее (тик хоста − наш тик) по приходящим снимкам
var _jitter := 0.0             ## насколько снимки, бывает, опаздывают (в тиках)
var _delay := DELAY
var _last_tick := -1
var _prev_tick := -1
var _welcomed := false

class Track:
	## Последние снимки одного объекта: [tick, pos, quat, extra]
	var s: Array = []

	func push(prev_snapshot_tick: int, sample: Array) -> void:
		# объект пропускали (спал) — значит всё это время он стоял на месте
		if not s.is_empty() and s[-1][0] < prev_snapshot_tick:
			var hold: Array = s[-1].duplicate()
			hold[0] = prev_snapshot_tick
			s.append(hold)
		s.append(sample)
		while s.size() > 16:
			s.pop_front()

	## Возвращает [a, b, t]: два соседних снимка и долю между ними.
	func at(tick: float) -> Array:
		var n := s.size()
		if tick >= s[n - 1][0]:
			return [s[n - 1], s[n - 1], 0.0]
		for i in range(n - 2, -1, -1):
			if s[i][0] <= tick:
				var span: float = s[i + 1][0] - s[i][0]
				return [s[i], s[i + 1], (tick - s[i][0]) / span]
		return [s[0], s[0], 0.0]

func _ready() -> void:
	add_to_group("net_world")
	process_physics_priority = 100   # после персонажей и уровня
	Net.player_left.connect(_on_player_left)

## true — эта машина считает физику и принимает решения (хост или одиночная игра).
func is_authority() -> bool:
	return not Net.in_session() or Net.is_host()

func local_peer() -> int:
	return Net.local_id() if Net.in_session() else 1

func add_spawner(kind: String, factory: Callable) -> void:
	_spawners[kind] = factory

## Взять на учёт объект, созданный при постройке уровня.
func track(node: Node3D) -> void:
	_register(_next_static, node)
	_next_static += 1

## Взять на учёт все физические тела — прямых детей уровня (в порядке создания).
func track_tree(root: Node) -> void:
	for c in root.get_children():
		if c is RigidBody3D or c is AnimatableBody3D:
			track(c)

## Создать объект во время игры (только хост / одиночная игра). Появится у всех.
func spawn(kind: String, params: Dictionary) -> Node:
	assert(is_authority())
	var id := _next_dyn
	_next_dyn += 1
	_dyn[id] = [kind, params]
	for peer in _ready_peers:
		_spawn.rpc_id(peer, id, kind, params)
	return _create(id, kind, params)

## Клиент закончил загрузку уровня — просит у хоста текущее состояние.
func start() -> void:
	while not is_authority() and not _welcomed and is_inside_tree():
		_hello.rpc_id(1)
		await get_tree().create_timer(1.0).timeout   # хост мог не успеть загрузиться — повторяем

## Попросить действие, которое решает уровень (работает и на хосте, и на клиенте).
func request_action(action: StringName) -> void:
	if is_authority():
		player_action.emit(local_peer(), action)
	else:
		_action.rpc_id(1, action)

## Номер объекта в общем мире (0 — объект не на учёте, например стена).
func id_of(node: Object) -> int:
	return _ids.get(node, 0)

func node_of(id: int) -> Node3D:
	return _nodes.get(id)

## Разослать всем состояние объекта, которое не видно по его положению (сколько ленты
## в рулоне, открыт ли вентиль…). У клиентов вызовется node.net_state(data);
## опоздавший игрок получит последнее состояние при входе. Только хост / одиночная игра.
func sync_state(node: Node3D, data: Dictionary) -> void:
	var id := id_of(node)
	if id == 0 or not is_authority():
		return
	_states[id] = data
	for peer in _ready_peers:
		_state.rpc_id(peer, id, data)

func kombez_of(peer: int) -> Kombez:
	var k: Kombez = _kombez_by_peer.get(peer)
	return k if is_instance_valid(k) else null

# ---------- учёт ----------

func _create(id: int, kind: String, params: Dictionary) -> Node:
	var node: Node = _spawners[kind].call(params)
	get_parent().add_child(node)
	if params.has("xform") and node is Node3D:
		node.global_transform = params["xform"]
		node.reset_physics_interpolation()
	_register(id, node)
	spawned.emit(node, kind, params)
	return node

func _register(id: int, node: Node3D) -> void:
	_nodes[id] = node
	_ids[node] = id
	if node is Kombez and node.peer_id > 0:
		_kombez_by_peer[node.peer_id] = node
	if not is_authority():
		if node.has_method("set_puppet"):
			node.set_puppet(true)
		elif node is RigidBody3D:
			node.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			node.freeze = true
	node.tree_exiting.connect(_on_node_gone.bind(id))

func _on_node_gone(id: int) -> void:
	_ids.erase(_nodes.get(id))
	_nodes.erase(id)
	_states.erase(id)
	_tracks.erase(id)
	if _dyn.has(id):
		_dyn.erase(id)
		if Net.is_host():
			for peer in _ready_peers:
				_despawn.rpc_id(peer, id)

func _on_player_left(id: int) -> void:
	_ready_peers.erase(id)
	_kombez_by_peer.erase(id)

# ---------- обмен ----------

@rpc("any_peer", "call_remote", "reliable")
func _hello() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not Net.is_host() or not Net.players.has(peer) or _ready_peers.has(peer):
		return
	var list := []
	var ids := _dyn.keys()
	ids.sort()
	for id in ids:
		list.append([id, _dyn[id][0], _dyn[id][1]])
	_welcome.rpc_id(peer, list, _states)
	_ready_peers[peer] = true
	_full_next = true

@rpc("authority", "call_remote", "reliable")
func _welcome(list: Array, states: Dictionary) -> void:
	if _welcomed:
		return
	_welcomed = true
	for e in list:
		_create(e[0], e[1], e[2])
	for id in states:
		_state(id, states[id])

@rpc("authority", "call_remote", "reliable")
func _state(id: int, data: Dictionary) -> void:
	var node: Node = _nodes.get(id)
	if node != null and node.has_method("net_state"):
		node.net_state(data)

@rpc("authority", "call_remote", "reliable")
func _spawn(id: int, kind: String, params: Dictionary) -> void:
	if not _nodes.has(id) and _spawners.has(kind):
		_create(id, kind, params)

@rpc("authority", "call_remote", "reliable")
func _despawn(id: int) -> void:
	var node: Node = _nodes.get(id)
	if node != null:
		node.queue_free()

func _send_action(action: StringName) -> void:
	_action.rpc_id(1, action)

@rpc("any_peer", "call_remote", "reliable")
func _action(action: StringName) -> void:
	if not Net.is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	var k := kombez_of(peer)
	if k == null:
		return
	match action:
		&"flop": k.flop()
		&"laugh": k.laugh()
		&"use": k.use()
		&"drop": k.drop_tool()
		_: player_action.emit(peer, action)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _player_input(move: Vector2, buttons: int, yaw: float, pitch: float) -> void:
	if not Net.is_host():
		return
	var k := kombez_of(multiplayer.get_remote_sender_id())
	if k == null or not (move.is_finite() and is_finite(yaw) and is_finite(pitch)):
		return
	k.in_move = move.limit_length(1.0)
	k.in_jump = buttons & 1 != 0
	k.in_grab_l = buttons & 2 != 0
	k.in_grab_r = buttons & 4 != 0
	k.in_crouch = buttons & 8 != 0
	k.in_aim_yaw = wrapf(yaw, -PI, PI)
	k.in_aim_pitch = clampf(pitch, -1.6, 1.6)

func _physics_process(_dt: float) -> void:
	if not Net.in_session():
		return
	if Net.is_host():
		_tick += 1
		if not _ready_peers.is_empty() and _tick % SNAP_EVERY == 0:
			var bytes := _write_snapshot(_full_next)
			_full_next = false
			for peer in _ready_peers:
				_snapshot.rpc_id(peer, bytes)
	else:
		_apply_snapshots()
		var k := local_kombez
		if k != null and is_instance_valid(k):
			var buttons := int(k.in_jump) | int(k.in_grab_l) << 1 | int(k.in_grab_r) << 2 | int(k.in_crouch) << 3
			_player_input.rpc_id(1, k.in_move, buttons, k.in_aim_yaw, k.in_aim_pitch)

# ---------- снимки: хост пишет ----------

func _write_snapshot(full: bool) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(_tick)
	b.put_u16(0)
	var count := 0
	for id in _nodes:
		var node: Node3D = _nodes[id]
		if not node is PhysicsBody3D:
			continue   # не тело (например, лента): его положение вычисляется, а не передаётся
		var k := node as Kombez
		if k == null:
			var rb := node as RigidBody3D
			if rb != null and rb.sleeping and not rb.freeze and not full and (_tick + id) % REFRESH_TICKS != 0:
				continue
		b.put_u16(id)
		b.put_u8(T_BODY if k == null else T_KOMBEZ)
		var xf := node.global_transform
		_put_v3(b, xf.origin)
		var q := xf.basis.get_rotation_quaternion()
		b.put_16(roundi(q.x * 32767.0))
		b.put_16(roundi(q.y * 32767.0))
		b.put_16(roundi(q.z * 32767.0))
		b.put_16(roundi(q.w * 32767.0))
		if k != null:
			_put_v3s(b, k.linear_velocity, 100.0)
			_put_v3s(b, k.hand_l.global_position - xf.origin, 1000.0)
			_put_v3s(b, k.hand_r.global_position - xf.origin, 1000.0)
			b.put_u8(k.net_flags())
			b.put_u8(clampi(roundi(k.ground_dist * 100.0), 0, 255))
		count += 1
	b.seek(4)
	b.put_u16(count)
	return b.data_array

static func _put_v3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)

static func _put_v3s(b: StreamPeerBuffer, v: Vector3, scale: float) -> void:
	b.put_16(clampi(roundi(v.x * scale), -32767, 32767))
	b.put_16(clampi(roundi(v.y * scale), -32767, 32767))
	b.put_16(clampi(roundi(v.z * scale), -32767, 32767))

static func _get_v3s(b: StreamPeerBuffer, scale: float) -> Vector3:
	var x := b.get_16()
	var y := b.get_16()
	var z := b.get_16()
	return Vector3(x, y, z) / scale

# ---------- снимки: клиент читает и показывает ----------

@rpc("authority", "call_remote", "unreliable", 2)
func _snapshot(bytes: PackedByteArray) -> void:
	if sim_bad_link.is_empty():
		_read_snapshot(bytes)
	elif randf() >= sim_bad_link[2]:
		get_tree().create_timer(sim_bad_link[0] + randf() * sim_bad_link[1], true, true) \
			.timeout.connect(_read_snapshot.bind(bytes))

func _read_snapshot(bytes: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	if bytes.size() < 6:
		return
	var tick := int(b.get_u32())
	if tick <= _last_tick:
		return
	var count := b.get_u16()
	for i in count:
		if b.get_available_bytes() < 23:
			return
		var id := b.get_u16()
		var type := b.get_u8()
		var px := b.get_float()
		var py := b.get_float()
		var pz := b.get_float()
		var qx := b.get_16()
		var qy := b.get_16()
		var qz := b.get_16()
		var qw := b.get_16()
		var q := Quaternion(qx, qy, qz, qw)
		q = q.normalized() if q.length_squared() > 0.0 else Quaternion.IDENTITY
		var pos := Vector3(px, py, pz)
		var extra = null
		if type == T_KOMBEZ:
			if b.get_available_bytes() < 20:
				return
			var vel := _get_v3s(b, 100.0)
			var hl := _get_v3s(b, 1000.0)
			var hr := _get_v3s(b, 1000.0)
			var flags := b.get_u8()
			var gd := b.get_u8() / 100.0
			extra = [vel, pos + hl, pos + hr, flags, gd]
		if not _nodes.has(id):
			continue   # о появлении объекта ещё не сообщили
		var tr: Track = _tracks.get(id)
		if tr == null:
			tr = Track.new()
			_tracks[id] = tr
		tr.push(_prev_tick if _prev_tick >= 0 else tick, [tick, pos, q, extra])
	_prev_tick = tick
	# Часы: считаем, насколько хост «впереди» нас, и как сильно снимки опаздывают.
	var off := float(tick - _local_tick)
	if _last_tick < 0 or absf(off - _offset) > 30.0:
		_offset = off
		_jitter = 0.0
		_delay = DELAY
		_clock = tick - _delay
	else:
		_offset += (off - _offset) * 0.02
		_jitter = maxf(_jitter * 0.998, _offset - off)
	_last_tick = tick

func _apply_snapshots() -> void:
	if _last_tick < 0:
		return
	_local_tick += 1
	_delay = move_toward(_delay, clampf(DELAY + _jitter, DELAY, DELAY_MAX), 0.02)
	# идём ровно тик за тик, мягко подтягиваясь к нужному отставанию
	_clock += 1.0 + clampf((_local_tick + _offset - _delay) - (_clock + 1.0), -0.1, 0.1)
	for id in _tracks:
		var node: Node3D = _nodes.get(id)
		if node == null:
			continue
		var r: Array = _tracks[id].at(_clock)
		var a: Array = r[0]
		var c: Array = r[1]
		var t: float = r[2]
		var pos: Vector3 = (a[1] as Vector3).lerp(c[1], t)
		var q: Quaternion = (a[2] as Quaternion).slerp(c[2], t)
		var jumped := pos.distance_to(node.global_position) > TELEPORT_DIST
		node.global_transform = Transform3D(Basis(q), pos)
		var k := node as Kombez
		if k != null and a[3] != null and c[3] != null:
			var ea: Array = a[3]
			var ec: Array = c[3]
			k.hand_l.global_position = (ea[1] as Vector3).lerp(ec[1], t)
			k.hand_r.global_position = (ea[2] as Vector3).lerp(ec[2], t)
			k.apply_net((ea[0] as Vector3).lerp(ec[0], t), ea[3], ea[4])
			if jumped:
				k.hand_l.reset_physics_interpolation()
				k.hand_r.reset_physics_interpolation()
		if jumped:
			node.reset_physics_interpolation()
