extends RefCounted
## Имитация плохого канала для автотестов (в обычной игре не создаётся).
## Всё, что эта машина отправляет, проходит через узкое «горлышко»: пакеты встают
## в очередь и уходят не быстрее rate байт/с (как на слабой отдаче интернета),
## потом ещё задерживаются и иногда теряются.

const OVERHEAD := 48           ## служебные байты на пакет (ENet + UDP + IP)
const QUEUE_SECONDS := 4.0     ## длиннее очередь не растёт — пакеты выбрасываются

var delay := 0.0               ## задержка в пути, с
var jitter := 0.0              ## случайная добавка к задержке, с
var loss := 0.0                ## доля потерянных пакетов
var rate := 0.0                ## пропускная способность, байт/с (0 — без ограничения)

var queued_bytes := 0
var _queue: Array = []         ## [размер, отправка]
var _flying: Array = []        ## [когда доставить, отправка]
var _budget := 0.0
var _now := 0.0

func _init(cfg: Array) -> void:
	delay = float(cfg[0])
	jitter = float(cfg[1]) if cfg.size() > 1 else 0.0
	loss = float(cfg[2]) if cfg.size() > 2 else 0.0
	rate = float(cfg[3]) * 1024.0 if cfg.size() > 3 else 0.0

func send(size: int, deliver: Callable) -> void:
	size += OVERHEAD
	if rate > 0.0 and queued_bytes + size > rate * QUEUE_SECONDS:
		return
	queued_bytes += size
	_queue.append([size, deliver])

func tick(dt: float) -> void:
	_now += dt
	if rate > 0.0:
		_budget = minf(_budget + rate * dt, maxf(rate * 0.05, 1500.0))
	while not _queue.is_empty() and (rate <= 0.0 or _budget >= _queue[0][0]):
		var p: Array = _queue.pop_front()
		queued_bytes -= p[0]
		_budget -= p[0]
		if randf() >= loss:
			_flying.append([_now + delay + randf() * jitter, p[1]])
	var i := 0
	while i < _flying.size():
		if _flying[i][0] <= _now:
			(_flying[i][1] as Callable).call()
			_flying.remove_at(i)
		else:
			i += 1
