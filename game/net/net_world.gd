extends Node
## NetWorld — общий мир для всех игроков. Живёт внутри уровня (узел "NetWorld").
##
## Хост считает всю физику и 20 раз в секунду рассылает снимки мира (только то,
## что изменилось). Клиенты шлют хосту свой ввод и показывают мир по снимкам —
## плавно, с небольшим отставанием. Своего персонажа клиент считает сам, сразу
## (предсказание), а хост его мягко поправляет.
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

const SimLink := preload("res://net/sim_link.gd")

const TICK := 1.0 / 60.0
# --- снимки ---
const SNAP_FAST := 3           ## обычно снимок каждые 3 тика (20 раз/с)…
const SNAP_SLOW := 6           ## …а если канал хоста не справляется — реже, до 10 раз/с
const REPEAT := 3              ## замерший объект досылается ещё столько раз (вдруг пакет потерялся)
const REFRESH_SNAPS := 40      ## и всё равно обновляется раз в столько снимков
const POS_SCALE := 256.0       ## точность позиции 4 мм; уровень обязан помещаться в ±125 м от центра
const KOMBEZ_BIT := 0x8000
const DYN_BASE := 1000
const OVERLOAD_TICKS := 6.0    ## пинг вырос на столько тиков (0.1 с) сверх обычного — канал забит
# --- показ на клиенте ---
const INPUT_EVERY := 2         ## ввод уходит хосту через тик (30 раз/с) и сразу при любом изменении
const DELAY_PAD := 1.5         ## отставание показа = шаг снимков + столько тиков + запас на неровную связь
const DELAY_MAX := 24.0
const TELEPORT_DIST := 4.0     ## скачок дальше — это телепорт, а не движение
# --- предсказание своего персонажа ---
const HIST := 128              ## сколько тиков своей истории помним
const CORR_RATE := 0.12        ## какую долю расхождения с хостом убираем за тик
const CORR_DEAD := 0.015       ## меньше — не трогаем
const SNAP_DIST := 1.5         ## расхождение больше — переставляем сразу
const SNAP_DIST_HARD := 3.0
const BLEND_KEEP := 0.86       ## как быстро сглаживается переход «считаю сам» -> «веду по хосту»

## Имитация плохой связи для автотестов: [задержка с, разброс с, доля потерь, канал КБ/с]. В игре пусто.
static var sim_link: Array = []
## Считать ли своего персонажа на клиенте самому (выключается только в автотестах).
static var predict_local := true
## Снижать ли частоту снимков при забитом канале (выключается только в автотестах).
static var adapt_rate := true

## Свой персонаж на клиенте: его ввод уходит хосту.
var local_kombez: Kombez:
	set(k):
		local_kombez = k
		if k != null and not is_authority():
			k.action_requested.connect(_send_action)

## Сводка для экрана отладки (F3) и журнала, обновляется раз в секунду.
var stats := {}

var _spawners := {}            ## kind -> Callable(params) -> Node
var _nodes := {}               ## id -> Node3D
var _dyn := {}                 ## id -> [kind, params]   (только динамические)
var _kombez_by_peer := {}      ## peer -> Kombez
var _next_static := 1
var _next_dyn := DYN_BASE
var _tick := 0
var _link: SimLink

# хост
var _ready_peers := {}         ## peer -> true: уровень загружен, можно слать
var _full_next := false
var _interval := SNAP_FAST
var _next_snap := 0
var _snap_no := 0
var _sent := {}                ## id -> [байты последней записи, сколько раз ещё дослать]
var _in := {}                  ## peer -> [номер ввода, с какого тика он действует, пинг, обычный пинг] (в тиках)
var _calm := 0
var _cool := 0
var _trial := 0
var _hold := 0.0
var _hold_next := 30.0

# клиент: показ мира
var _tracks := {}              ## id -> Track
var _clock := 0.0              ## какой тик хоста сейчас показываем
var _seq := 0                  ## наш счётчик тиков = номер ввода
var _offset := 0.0             ## среднее (тик хоста − наш тик) по приходящим снимкам
var _jitter := 0.0             ## насколько снимки, бывает, опаздывают (в тиках)
var _delay := SNAP_FAST + DELAY_PAD
var _last_tick := -1
var _prev_tick := -1
var _snap_seq := 0             ## наш тик, когда пришёл последний снимок
var _snap_interval := SNAP_FAST
var _welcomed := false

# клиент: свой персонаж
var _own_id := -1
var _own: Array = []           ## последнее от хоста: [позиция, скорость, левая рука, правая рука, флаги, хваты]
var _hist_pos := PackedVector3Array()
var _hist_seq := PackedInt32Array()
var _hist_from := 0
var _shift := Vector3.ZERO     ## сумма всех поправок (история хранится без них)
var _corr := Vector3.ZERO      ## сколько ещё осталось поправить
var _blend := Vector3.ZERO
var _await := [0, 0]
var _last_key := -1
var _ping := -1.0              ## в тиках
var _err := 0.0

# статистика
var _stat_t := 0.0
var _log_t := 0.0
var _st_snaps := 0
var _st_bytes := 0
var _tot_out := 0
var _tot_t := 0.0
var _max_ping := 0.0

class Track:
	## Последние снимки одного объекта: [tick, pos, quat, extra]
	var s: Array = []

	func push(prev_snapshot_tick: int, sample: Array) -> void:
		# объект пропускали (не менялся) — значит всё это время он стоял на месте
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
	_hist_pos.resize(HIST)
	_hist_seq.resize(HIST)
	_hist_seq.fill(-1)
	if not sim_link.is_empty():
		_link = SimLink.new(sim_link)

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
	_nodes.erase(id)
	_tracks.erase(id)
	_sent.erase(id)
	if _dyn.has(id):
		_dyn.erase(id)
		if Net.is_host():
			for peer in _ready_peers:
				_despawn.rpc_id(peer, id)

func _on_player_left(id: int) -> void:
	_ready_peers.erase(id)
	_kombez_by_peer.erase(id)
	_in.erase(id)

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
	_welcome.rpc_id(peer, list)
	_ready_peers[peer] = true
	_full_next = true

@rpc("authority", "call_remote", "reliable")
func _welcome(list: Array) -> void:
	if _welcomed:
		return
	_welcomed = true
	for e in list:
		_create(e[0], e[1], e[2])

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
		_: player_action.emit(peer, action)

## Ненадёжная отправка (снимок или ввод); в автотестах — через имитацию плохого канала.
func _send(peer: int, method: Callable, bytes: PackedByteArray) -> void:
	if _link == null:
		method.rpc_id(peer, bytes)
	else:
		_link.send(bytes.size(), func() -> void:
			if Net.in_session() and peer in multiplayer.get_peers():
				method.rpc_id(peer, bytes))

func _physics_process(dt: float) -> void:
	if not Net.in_session():
		return
	if _link != null:
		_link.tick(dt)
	if Net.is_host():
		_host_tick()
	else:
		_client_tick()
	_stat_t += dt
	if _stat_t >= 1.0:
		_update_stats()

# ---------- хост: ввод игроков ----------

## Ввод клиента: номер, движение, кнопки, взгляд + «эхо» последнего снимка (по нему хост меряет пинг).
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _player_input(bytes: PackedByteArray) -> void:
	if not Net.is_host() or bytes.size() != 12:
		return
	var peer := multiplayer.get_remote_sender_id()
	var k := kombez_of(peer)
	if k == null:
		return
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var seq := b.get_u16()
	var st: Array = _in.get(peer, [])
	if not st.is_empty() and ((seq - int(st[0])) & 0xFFFF) >= 0x8000:
		return   # опоздавший старый пакет
	var mx := b.get_8()
	var my := b.get_8()
	var buttons := b.get_u8()
	var yaw := b.get_16()
	var pitch := b.get_16()
	var echo := b.get_u16()
	var held := b.get_u8()
	k.in_move = (Vector2(mx, my) / 127.0).limit_length(1.0)
	k.in_jump = buttons & 1 != 0
	k.in_grab_l = buttons & 2 != 0
	k.in_grab_r = buttons & 4 != 0
	k.in_aim_yaw = wrapf(yaw / 10000.0, -PI, PI)
	k.in_aim_pitch = clampf(pitch / 10000.0, -1.6, 1.6)
	if st.is_empty():
		st = [seq, 0, -1.0, 1e9]
		_in[peer] = st
	st[0] = seq
	st[1] = _tick + 1
	if held < 255:
		var rtt := float((_tick - echo) & 0xFFFF) - held
		if rtt >= 0.0 and rtt < 3000.0:
			st[2] = rtt if st[2] < 0.0 else lerpf(st[2], rtt, 0.1)

# ---------- хост: снимки ----------

func _host_tick() -> void:
	_tick += 1
	if _ready_peers.is_empty() or _tick < _next_snap:
		return
	_next_snap = _tick + _interval
	_snap_no += 1
	var body := _write_records(_full_next)
	_full_next = false
	for peer in _ready_peers:
		# шапка у каждого своя: какой его ввод уже учтён и сколько тиков он действует
		var h := StreamPeerBuffer.new()
		h.put_u32(_tick)
		h.put_u8(_interval)
		var st: Array = _in.get(peer, [])
		if st.is_empty():
			h.put_u16(0)
			h.put_u8(255)
		else:
			h.put_u16(st[0])
			h.put_u8(clampi(_tick - int(st[1]), 0, 254))
		var bytes := h.data_array + body
		_st_snaps += 1
		_st_bytes += bytes.size()
		_send(peer, _snapshot, bytes)

## Записи обо всех объектах, которые изменились с прошлого снимка.
## Объект: номер (2 байта), позиция (3×2), поворот (4). Комбез ещё: скорость (3×2),
## руки относительно тела (2×3×2), флаги, высота над землёй, что держат руки.
func _write_records(full: bool) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u16(0)
	var count := 0
	for id in _nodes:
		var node: Node3D = _nodes[id]
		var k := node as Kombez
		var r := StreamPeerBuffer.new()
		var xf := node.global_transform
		_put_v3s(r, xf.origin, POS_SCALE)
		r.put_u32(_pack_quat(xf.basis.get_rotation_quaternion()))
		if k != null:
			_put_v3s(r, k.linear_velocity, 100.0)
			_put_v3s(r, k.hand_l.global_position - xf.origin, 1000.0)
			_put_v3s(r, k.hand_r.global_position - xf.origin, 1000.0)
			r.put_u8(k.net_flags())
			r.put_u8(clampi(roundi(k.ground_dist * 100.0), 0, 255))
			r.put_u8(k.net_hold())
		var rec := r.data_array
		var st: Array = _sent.get(id, [])
		if not full and not st.is_empty() and st[0] == rec:
			if st[1] <= 0 and (_snap_no + id) % REFRESH_SNAPS != 0:
				continue
			st[1] -= 1
		else:
			_sent[id] = [rec, REPEAT]
		b.put_u16(id | (KOMBEZ_BIT if k != null else 0))
		b.put_data(rec)
		count += 1
	b.seek(0)
	b.put_u16(count)
	return b.data_array

static func _put_v3s(b: StreamPeerBuffer, v: Vector3, scale: float) -> void:
	b.put_16(clampi(roundi(v.x * scale), -32767, 32767))
	b.put_16(clampi(roundi(v.y * scale), -32767, 32767))
	b.put_16(clampi(roundi(v.z * scale), -32767, 32767))

static func _get_v3s(b: StreamPeerBuffer, scale: float) -> Vector3:
	var x := b.get_16()
	var y := b.get_16()
	var z := b.get_16()
	return Vector3(x, y, z) / scale

## Поворот в 4 байтах: самую большую из четырёх компонент не передаём (её можно вычислить).
static func _pack_quat(q: Quaternion) -> int:
	var a := [q.x, q.y, q.z, q.w]
	var m := 0
	for i in 4:
		if absf(a[i]) > absf(a[m]):
			m = i
	var sgn := -1.0 if a[m] < 0.0 else 1.0
	var out := m
	var sh := 2
	for i in 4:
		if i == m:
			continue
		out |= clampi(roundi(a[i] * sgn * 723.0) + 512, 0, 1023) << sh
		sh += 10
	return out

static func _unpack_quat(p: int) -> Quaternion:
	var m := p & 3
	var a := [0.0, 0.0, 0.0, 0.0]
	var sum := 0.0
	var sh := 2
	for i in 4:
		if i == m:
			continue
		var v := (((p >> sh) & 1023) - 512) / 723.0
		a[i] = v
		sum += v * v
		sh += 10
	a[m] = sqrt(maxf(1.0 - sum, 0.0))
	return Quaternion(a[0], a[1], a[2], a[3]).normalized()

## Раз в секунду: если пинг до кого-то вырос сильно выше обычного — канал забит,
## шлём снимки реже. Когда всё спокойно — осторожно пробуем вернуть частоту.
func _adapt() -> void:
	var worst := 0.0
	for peer in _in:
		var st: Array = _in[peer]
		if st[2] < 0.0:
			continue
		st[3] = minf(st[3] + 0.05, st[2])
		worst = maxf(worst, st[2] - st[3])
	_hold = maxf(_hold - 1.0, 0.0)
	_cool = maxi(_cool - 1, 0)
	_trial = maxi(_trial - 1, 0)
	if not adapt_rate:
		return
	if worst > OVERLOAD_TICKS:
		_calm = 0
		if _interval < SNAP_SLOW and _cool == 0:
			_interval += 1
			_cool = 2
			if _trial > 0:   # только что пробовали быстрее — не вышло, в следующий раз ждём дольше
				_hold_next = minf(_hold_next * 2.0, 600.0)
			_hold = _hold_next
			print("NET канал перегружен (пинг +%d мс): снимки теперь %d раз/с" % [roundi(worst * TICK * 1000.0), roundi(60.0 / _interval)])
	else:
		_calm += 1
		if _interval > SNAP_FAST and _hold <= 0.0 and _calm >= 5:
			_interval -= 1
			_calm = 0
			_trial = 15
			print("NET связь спокойная: пробуем снимки %d раз/с" % roundi(60.0 / _interval))

# ---------- клиент: приём снимков ----------

@rpc("authority", "call_remote", "unreliable", 2)
func _snapshot(bytes: PackedByteArray) -> void:
	_st_snaps += 1
	_st_bytes += bytes.size()
	_read_snapshot(bytes)

func _read_snapshot(bytes: PackedByteArray) -> void:
	if bytes.size() < 10:
		return
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var tick := int(b.get_u32())
	if tick <= _last_tick:
		return
	_snap_interval = clampi(b.get_u8(), 1, 30)
	var ack := b.get_u16()
	var age := b.get_u8()
	var count := b.get_u16()
	for i in count:
		if b.get_available_bytes() < 12:
			return
		var id := b.get_u16()
		var is_kombez := id & KOMBEZ_BIT != 0
		id &= ~KOMBEZ_BIT
		var pos := _get_v3s(b, POS_SCALE)
		var q := _unpack_quat(b.get_u32())
		var extra = null
		if is_kombez:
			if b.get_available_bytes() < 21:
				return
			var vel := _get_v3s(b, 100.0)
			var hl := _get_v3s(b, 1000.0)
			var hr := _get_v3s(b, 1000.0)
			var flags := b.get_u8()
			var gd := b.get_u8() / 100.0
			var hold := b.get_u8()
			extra = [vel, pos + hl, pos + hr, flags, gd, hold]
		var node: Node3D = _nodes.get(id)
		if node == null:
			continue   # о появлении объекта ещё не сообщили
		if extra != null and node == local_kombez:
			_own_id = id
			_own = [pos, extra[0], extra[1], extra[2], extra[3], extra[5]]
		var tr: Track = _tracks.get(id)
		if tr == null:
			tr = Track.new()
			_tracks[id] = tr
		tr.push(_prev_tick if _prev_tick >= 0 else tick, [tick, pos, q, extra])
	_prev_tick = tick
	# Часы: считаем, насколько хост «впереди» нас, и как сильно снимки опаздывают.
	var off := float(tick - _seq)
	if _last_tick < 0 or absf(off - _offset) > 30.0:
		_offset = off
		_jitter = 0.0
		_delay = _snap_interval + DELAY_PAD
		_clock = tick - _delay
	else:
		_offset += (off - _offset) * 0.05
		_jitter = maxf(_jitter * 0.995, _offset - off)
	_last_tick = tick
	_snap_seq = _seq
	_reconcile(ack, age)

# ---------- клиент: каждый тик ----------

func _client_tick() -> void:
	_seq += 1
	var k: Kombez = local_kombez if is_instance_valid(local_kombez) else null
	if k != null:
		_update_own(k)
	_apply_snapshots()
	if k != null:
		if k.predicted:
			_predict(k)
		_send_input(k)

## Показать мир таким, каким он был у хоста _delay тиков назад (плавно между снимками).
func _apply_snapshots() -> void:
	if _last_tick < 0:
		return
	var base := _snap_interval + DELAY_PAD
	_delay = move_toward(_delay, clampf(base + _jitter, base, DELAY_MAX), 0.05)
	# идём ровно тик за тик, мягко подтягиваясь к нужному отставанию
	var want := _seq + _offset - _delay
	if absf(want - _clock - 1.0) > 40.0:
		_clock = want
	else:
		_clock += 1.0 + clampf(want - (_clock + 1.0), -0.1, 0.1)
	_blend *= BLEND_KEEP
	for id in _tracks:
		var node: Node3D = _nodes.get(id)
		if node == null:
			continue
		var k := node as Kombez
		if k != null and k.predicted:
			continue   # своего считаем сами
		var r: Array = _tracks[id].at(_clock)
		var a: Array = r[0]
		var c: Array = r[1]
		var t: float = r[2]
		var pos: Vector3 = (a[1] as Vector3).lerp(c[1], t)
		var q: Quaternion = (a[2] as Quaternion).slerp(c[2], t)
		var add := _blend if id == _own_id else Vector3.ZERO
		pos += add
		var jumped := pos.distance_to(node.global_position) > TELEPORT_DIST
		node.global_transform = Transform3D(Basis(q), pos)
		if k != null and a[3] != null and c[3] != null:
			var ea: Array = a[3]
			var ec: Array = c[3]
			k.hand_l.global_position = (ea[1] as Vector3).lerp(ec[1], t) + add
			k.hand_r.global_position = (ea[2] as Vector3).lerp(ec[2], t) + add
			k.apply_net((ea[0] as Vector3).lerp(ec[0], t), ea[3], ea[4])
			if jumped:
				k.hand_l.reset_physics_interpolation()
				k.hand_r.reset_physics_interpolation()
		elif k == null:
			# скорость куклы: по ней свой персонаж понимает, что стоит на движущемся
			var span: float = (c[0] - a[0]) * TICK
			node.set_meta(&"net_vel", ((c[1] as Vector3) - a[1]) / span if span > 0.0 else Vector3.ZERO)
		if jumped:
			node.reset_physics_interpolation()

## Свой персонаж: когда считаем его сами, а когда ведём по хосту.
## Сами — пока он на ногах и не держит ничего подвижного. Нокаут и хват решает хост.
func _update_own(k: Kombez) -> void:
	if _own.is_empty():
		return
	var flags: int = _own[4]
	var hold: int = _own[5]
	var want := predict_local and flags & 1 == 0 and (hold & 0x0F) != 2 and (hold >> 4) != 2
	if want and not k.predicted:
		k.set_predicted(true)
		_corr = Vector3.ZERO
		_hist_from = _seq
		_await = [0, 0]
	elif not want and k.predicted:
		_blend = Vector3.ZERO
		var tr: Track = _tracks.get(_own_id)
		if tr != null:
			var r: Array = tr.at(_clock)
			_blend = k.global_position - (r[0][1] as Vector3).lerp(r[1][1], r[2])
			if _blend.length() > TELEPORT_DIST:
				_blend = Vector3.ZERO
		k.set_predicted(false)
	if not k.predicted:
		return
	k.apply_net_predicted(flags)
	# Хват за стену/пол решает хост; мы повторяем его у себя — рука крепится в той же точке.
	var hands: Array = [k.hand_l, k.hand_r]
	for i in 2:
		var kind := (hold >> (i * 4)) & 0x0F
		_await[i] = maxi(_await[i] - 1, 0)
		if kind == 0:
			_await[i] = 0
			if hands[i].pinned:
				hands[i].release()
		elif not hands[i].active:
			_await[i] = 30   # мы уже отпустили, а хост ещё не знает — его «держит» устарело
		elif not hands[i].pinned and _await[i] == 0:
			hands[i].pin_world(_own[2 + i])

## Шаг предсказания: понемногу убираем расхождение с хостом и запоминаем, где мы были.
func _predict(k: Kombez) -> void:
	if _corr != Vector3.ZERO:
		var step := _corr * CORR_RATE
		if _corr.length() < 0.004:
			step = _corr
		k.global_position += step
		_corr -= step
		_shift += step
	var i := _seq % HIST
	_hist_pos[i] = k.global_position - _shift
	_hist_seq[i] = _seq

## Пришёл снимок: хост говорит, где наш персонаж был после ввода номер ack (+ age тиков).
## Сравниваем с тем, где мы сами были в тот момент; разницу потом плавно убираем.
func _reconcile(ack16: int, age: int) -> void:
	if age == 255:
		return
	var ack := _seq - ((_seq - ack16) & 0xFFFF)
	var rtt := float(_seq - ack - age)
	_ping = rtt if _ping < 0.0 else lerpf(_ping, rtt, 0.1)
	var k := local_kombez
	if not is_instance_valid(k) or not k.predicted or _own.is_empty():
		return
	var at := mini(ack + age, _seq)
	if at < _hist_from or _hist_seq[at % HIST] != at:
		return
	var raw: Vector3 = _own[0] - (_hist_pos[at % HIST] + _shift)
	# Не лезем поправкой внутрь предмета, который нас подпирает: он у нас на экране
	# отстаёт от хоста и сам сдвинется чуть позже.
	var err := raw
	for n in k.block_normals:
		var d := err.dot(n)
		if d < 0.0:
			err -= n * d
	_err = raw.length()
	if raw.length() > SNAP_DIST_HARD or err.length() > SNAP_DIST:
		k.global_position += raw
		k.linear_velocity = _own[1]
		_shift += raw
		_corr = Vector3.ZERO
		for h in [k.hand_l, k.hand_r]:
			if not h.pinned:
				h.snap_to_rest()
		k.reset_physics_interpolation()
	else:
		_corr = err if err.length() > CORR_DEAD else Vector3.ZERO

func _send_input(k: Kombez) -> void:
	var mx := clampi(roundi(k.in_move.x * 127.0), -127, 127)
	var my := clampi(roundi(k.in_move.y * 127.0), -127, 127)
	var buttons := int(k.in_jump) | int(k.in_grab_l) << 1 | int(k.in_grab_r) << 2
	var key := (mx & 0xFF) | (my & 0xFF) << 8 | buttons << 16
	if _seq % INPUT_EVERY != 0 and key == _last_key:
		return
	_last_key = key
	var b := StreamPeerBuffer.new()
	b.put_u16(_seq & 0xFFFF)
	b.put_8(mx)
	b.put_8(my)
	b.put_u8(buttons)
	b.put_16(roundi(wrapf(k.in_aim_yaw, -PI, PI) * 10000.0))
	b.put_16(roundi(clampf(k.in_aim_pitch, -1.6, 1.6) * 10000.0))
	b.put_u16(maxi(_last_tick, 0) & 0xFFFF)
	b.put_u8(255 if _last_tick < 0 else clampi(_seq - _snap_seq, 0, 254))
	_send(1, _player_input, b.data_array)

# ---------- статистика (F3 и журнал) ----------

func _update_stats() -> void:
	var t := _stat_t
	_stat_t = 0.0
	var tr := Net.pop_traffic()
	_tot_out += tr[0]
	_tot_t += t
	var host := Net.is_host()
	var per := maxi(_ready_peers.size(), 1) if host else 1
	stats = {
		"host": host,
		"fps": roundi(Engine.get_frames_per_second()),
		"snap_hz": snappedf(_st_snaps / t / per, 0.1),
		"snap_bytes": roundi(float(_st_bytes) / maxi(_st_snaps, 1)),
		"out_kbs": snappedf(tr[0] / t / 1024.0, 0.1),
		"in_kbs": snappedf(tr[1] / t / 1024.0, 0.1),
		"out_avg_kbs": snappedf(_tot_out / _tot_t / 1024.0, 0.1),
	}
	_st_snaps = 0
	_st_bytes = 0
	if host:
		var pings := {}
		for peer in _in:
			if Net.players.has(peer) and _in[peer][2] >= 0.0:
				var ms := roundi(_in[peer][2] * TICK * 1000.0)
				pings[str(Net.players[peer]["name"])] = [ms, Net.ping_ms(peer)]
				_max_ping = maxf(_max_ping, ms)
		stats["pings"] = pings
		stats["max_ping"] = roundi(_max_ping)
		stats["rate"] = roundi(60.0 / _interval)
		if _link != null:
			stats["queue_kb"] = snappedf(_link.queued_bytes / 1024.0, 0.1)
		_adapt()
	else:
		var ms := roundi(_ping * TICK * 1000.0) if _ping >= 0.0 else -1
		_max_ping = maxf(_max_ping, ms)
		stats["ping"] = ms
		stats["max_ping"] = roundi(_max_ping)
		stats["enet_ping"] = Net.ping_ms(1)
		stats["delay"] = roundi(_delay * TICK * 1000.0)
		stats["jitter"] = roundi(_jitter * TICK * 1000.0)
		stats["rate"] = roundi(60.0 / _snap_interval)
		stats["predicted"] = is_instance_valid(local_kombez) and local_kombez.predicted
		stats["err_cm"] = roundi(_err * 100.0)
	_log_t += t
	if _log_t >= 5.0:
		_log_t = 0.0
		print("NETSTAT ", JSON.stringify(stats))

## Текст для экрана отладки (F3).
func debug_text() -> String:
	if not Net.in_session():
		return "Одиночная игра"
	if stats.is_empty():
		return "Сеть: считаю…"
	var s := ""
	if stats["host"]:
		s += "ХОСТ   снимки %d раз/с по %d байт" % [stats["rate"], stats["snap_bytes"]]
		s += "\nотправка %.1f КБ/с   приём %.1f КБ/с" % [stats["out_kbs"], stats["in_kbs"]]
		var pings: Dictionary = stats["pings"]
		for n in pings:
			s += "\n%s: пинг %d мс (ENet %d)" % [n, pings[n][0], pings[n][1]]
	else:
		s += "КЛИЕНТ   пинг %d мс (ENet %d)" % [stats["ping"], stats["enet_ping"]]
		s += "\nснимки %.0f раз/с по %d байт (хост шлёт %d)" % [stats["snap_hz"], stats["snap_bytes"], stats["rate"]]
		s += "\nмир отстаёт на %d мс   разброс связи %d мс" % [stats["delay"], stats["jitter"]]
		s += "\nприём %.1f КБ/с   отправка %.1f КБ/с" % [stats["in_kbs"], stats["out_kbs"]]
		s += "\nсвой персонаж: %s, расхождение с хостом %d см" % ["считаю сам" if stats["predicted"] else "веду по хосту", stats["err_cm"]]
	return s
