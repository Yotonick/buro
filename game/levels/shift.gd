extends Node3D
## Ход смены на вызове: идёт работа → справились / провалили. Общий для всех уровней-вызовов.
## Хост решает исход (finish), у всех показывается табличка, и через несколько секунд
## бригада возвращается в лобби. Уровень должен взять узел на учёт в NetWorld (track).

enum P { WORK, WON, FAILED }

const END_DELAY := 8.0

var phase := P.WORK
var time := 0.0                ## секунд с начала смены (считает хост)
var title := ""
var subtitle := ""

var _world: Node
var _end_t := 0.0

func _ready() -> void:
	add_to_group("shift")
	_world = get_tree().get_first_node_in_group("net_world")

func working() -> bool:
	return phase == P.WORK

## Закончить смену (только хост).
func finish(won: bool, t: String, sub := "") -> void:
	if phase != P.WORK or _world == null or not _world.is_authority():
		return
	phase = P.WON if won else P.FAILED
	title = t
	subtitle = sub
	_world.sync_state(self, {"p": phase, "t": title, "s": subtitle})
	_show()

func net_state(d: Dictionary) -> void:
	phase = int(d.get("p", P.WORK)) as P
	title = str(d.get("t", ""))
	subtitle = str(d.get("s", ""))
	_show()

func _show() -> void:
	if phase == P.WORK:
		return
	var level := get_parent()
	if level != null and "hud" in level and level.hud != null:
		level.hud.show_banner(title, subtitle, phase == P.WON)

func _physics_process(dt: float) -> void:
	if _world == null or not _world.is_authority():
		return
	if phase == P.WORK:
		time += dt
		return
	_end_t += dt
	if _end_t >= END_DELAY:
		_end_t = -INF
		Game.back_to_lobby()
