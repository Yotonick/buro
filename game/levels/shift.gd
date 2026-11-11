extends Node3D
## Ход смены на вызове: идёт работа → (приёмка клиентом) → справились / провалили.
## Общий для всех уровней-вызовов. Хост решает исход (finish), у всех показывается
## табличка (со звёздами, если была приёмка), и через несколько секунд бригада
## возвращается в лобби. Уровень должен взять узел на учёт в NetWorld (track).

enum P { WORK, WON, FAILED, REVIEW }

const END_DELAY := 8.0
const PROGRESS_EVERY := 0.5
const TIME_EVERY := 3.0         ## время смены уточняется у клиентов раз в столько секунд

var phase := P.WORK
var time := 0.0                ## секунд с начала смены (считает хост)
var title := ""
var subtitle := ""
var stars := -1                ## оценка приёмки 0..5 (-1 — без приёмки)
## Ход смены для планшета (что проверено при приёмке и т.п.) — уровень/приёмка пишут сюда
## через set_progress, хост рассылает не чаще раза в PROGRESS_EVERY с.
var progress := {}

var _world: Node
var _end_t := 0.0
var _dirty := false
var _send_t := 0.0

func _ready() -> void:
	add_to_group("shift")
	_world = get_tree().get_first_node_in_group("net_world")

## Идёт смена (работа или приёмка) — мир живёт, вода течёт.
func working() -> bool:
	return phase == P.WORK or phase == P.REVIEW

func reviewing() -> bool:
	return phase == P.REVIEW

## Смена отработана — клиент начинает приёмку (только хост). t/sub — табличка на пару секунд.
func start_review(t: String, sub := "") -> void:
	if phase != P.WORK or _world == null or not _world.is_authority():
		return
	phase = P.REVIEW
	title = t
	subtitle = sub
	_send()
	_show()

## Закончить смену (только хост). stars — оценка приёмки 0..5, если она была.
func finish(won: bool, t: String, sub := "", st := -1) -> void:
	if not working() or _world == null or not _world.is_authority():
		return
	phase = P.WON if won else P.FAILED
	title = t
	subtitle = sub
	stars = st
	_send()
	_show()

## Дописать ход смены (только хост; у клиентов придёт по сети).
func set_progress(d: Dictionary) -> void:
	if _world == null or not _world.is_authority():
		return
	for k in d:
		if progress.get(k) != d[k]:
			progress[k] = d[k]
			_dirty = true

func _send() -> void:
	_dirty = false
	_send_t = 0.0
	_world.sync_state(self, {"p": phase, "t": title, "s": subtitle, "st": stars, "tm": time, "pg": progress})

func net_state(d: Dictionary) -> void:
	var was := phase
	phase = int(d.get("p", P.WORK)) as P
	title = str(d.get("t", ""))
	subtitle = str(d.get("s", ""))
	stars = int(d.get("st", -1))
	time = float(d.get("tm", time))
	progress = d.get("pg", {})
	if phase != was:
		_show()

func _show() -> void:
	if phase == P.WORK:
		return
	var level := get_parent()
	if level == null or not "hud" in level or level.hud == null:
		return
	if phase == P.REVIEW:
		level.hud.show_banner(title, subtitle, true, -1, 6.0)
	else:
		level.hud.show_banner(title, subtitle, phase == P.WON, stars)

func _physics_process(dt: float) -> void:
	if _world == null:
		return
	if not _world.is_authority():   # у клиента часы идут сами, хост иногда уточняет
		if working():
			time += dt
		return
	if working():
		time += dt
		_send_t += dt
		if (_dirty and _send_t >= PROGRESS_EVERY) or _send_t >= TIME_EVERY:
			_send()
		return
	_end_t += dt
	if _end_t >= END_DELAY:
		_end_t = -INF
		Game.back_to_lobby()
