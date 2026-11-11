extends Node
## Приёмка «Глубокой тарелки» (вариант А, выбран владельцем): смена отработана —
## метрдотель выходит из шлюза и обходит зал по кругу против часовой.
##  - У каждого стола: стоит ли стол, вся ли еда на месте, не валяется ли посуда,
##    стоят ли стулья, горит ли свет этого сектора (щиток).
##  - У каждой заделанной течи: стучит по стеклу. Хлипкое (1–3 полоски ленты,
##    затычка без ленты) может развалиться прямо при нём — и окатить его струёй.
##  - Всё время: облили струёй, кинули предметом, схватили руками, примотали лентой — штраф.
##  - В конце у шлюза: сухо ли в зале. Итог — 0..5 звёзд и ворчливый комментарий.
## Проверяет только то, что видит, когда подошёл: успели прибрать стол до него — молодцы.
## Работает только у хоста; всё видимое (метрдотель, реплики, итог) уходит через NetWorld.

const START_PENALTY_CAP := 2.0   ## за попадания предметами — не больше этого
const RING := 7.6                ## радиус дорожки обхода (между столами и стеклом)
const AT_LEAK := 0.85            ## на таком расстоянии от стекла стучит по течи
const MAX_TIME := 160.0          ## обход затянулся — идёт к выходу
const SPRAY_R := 0.5

var level: Node3D                ## deep_plate.gd
var npc: AnimatableBody3D        ## client_npc.gd
var pace := 1.0                  ## множитель пауз (для тестов)
var peel_weak := 0.6             ## шанс, что от стука отклеится полоска, если их 1–2…
var peel_three := 0.3            ## …если ровно 3 (4 и больше — не отклеиваются)
var running := false
var score := 5.0
var said: Array[String] = []     ## что он сказал (для тестов и отладки)

var _stops: Array = []           ## {kind, obj, pos, look, off}
var _i := -1
var _step := ""
var _t := 0.0
var _elapsed := 0.0
var _off := 0.0                  ## где на круге он сейчас (угол от шлюза)
var _rng := RandomNumberGenerator.new()
var _cat := {}                   ## категория -> сумма штрафа
var _hit_pen := 0.0
var _taped_said := false
var _grab_said := 0
var _grab_next := 0.0
var _spray_next := {}            ## течь -> когда снова можно считать «облили»
var _sprayed := {}
var _knock_cover: Node3D
var _knock_strips := 0
var _wet_said := false
var _final := ""

func setup(lvl: Node3D, client: AnimatableBody3D) -> void:
	level = lvl
	npc = client
	npc.hit.connect(_on_hit)
	_rng.seed = Time.get_ticks_usec()

## Начать обход (только хост).
func start() -> void:
	running = true
	score = 5.0
	_elapsed = 0.0
	npc.teleport(level.REVIEW_START, 0.0)
	npc.set_active(true)
	npc.go([_free(_entry())])
	_say("Так-так. Посмотрим, что вы тут натворили.", "snob")
	_build_stops()
	_i = -1
	_off = 0.0
	_step = "enter"
	_t = 0.0

func _entry() -> Vector3:
	return Vector3(cos(level.DOOR_ANGLE), 0, sin(level.DOOR_ANGLE)) * (level.R - 1.2)

func _build_stops() -> void:
	_stops.clear()
	for t in level.tables:
		var c: Vector3 = t["center"]
		var dir := Vector3(c.x, 0, c.z).normalized()
		_stops.append({"kind": "table", "obj": t, "pos": _free(dir * RING), "off": _offset_of(c)})
	for l in level.leaks:
		if not l.is_burst():
			continue
		var p: Vector3 = l.global_position
		var dir := Vector3(p.x, 0, p.z).normalized()
		_stops.append({"kind": "leak", "obj": l, "pos": _free(dir * (level.R - AT_LEAK)), "off": _offset_of(p)})
	_stops.sort_custom(func(a, b): return a["off"] < b["off"])

## Угол точки от шлюза против часовой, 0..TAU.
func _offset_of(p: Vector3) -> float:
	return fposmod(atan2(p.z, p.x) - level.DOOR_ANGLE, TAU)

func _ring(off: float) -> Vector3:
	var a: float = level.DOOR_ANGLE + off
	return Vector3(cos(a), 0, sin(a)) * RING

## Точка, где он может стоять: если там что-то неподвижное (насос, стойка щитка) — ближе к центру.
func _free(p: Vector3) -> Vector3:
	var space := level.get_world_3d().direct_space_state
	var sq := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.32
	sq.shape = sph
	sq.collision_mask = 1
	for i in 12:
		sq.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
		if space.intersect_shape(sq, 1).is_empty():
			break
		p -= Vector3(p.x, 0, p.z).normalized() * 0.25
	return p

## Дорога по кругу от текущего места до угла off и к точке to.
func _route(off: float, to: Vector3) -> Array:
	var pts: Array = []
	var a0 := _off
	if npc.at().distance_to(_ring(a0)) > 0.4:
		pts.append(_free(_ring(a0)))
	var d := off - a0
	var n := int(ceil(d / 0.25))
	for i in range(1, n + 1):
		pts.append(_free(_ring(a0 + d * i / n)))
	pts.append(to)
	_off = off
	return pts

# ---------- ход обхода ----------

func _physics_process(dt: float) -> void:
	if not running:
		return
	if not level.shift.reviewing():
		running = false   # затопило прямо при нём — итог уже подвёл уровень
		npc.go([])
		return
	_elapsed += dt
	_t += dt
	_watch()
	if _elapsed > MAX_TIME and _step != "exit" and _step != "verdict" and _step != "done":
		_exit()
	match _step:
		"enter":
			if not npc.walking():
				_next()
		"walk":
			if not npc.walking():
				_arrive()
		"look":
			if _t > 1.1 * pace:
				_judge_table(_stops[_i]["obj"])
				_wait("talk")
		"knock":
			if _t > 0.5 * pace and _knock_cover == null and _knock_strips < 0:
				_do_knock(_stops[_i]["obj"])
			if _t > 1.8 * pace:
				_judge_leak(_stops[_i]["obj"])
				_wait("talk")
		"talk":
			if _t > 2.3 * pace:
				_next()
		"exit":
			if not npc.walking():
				npc.look(Vector3.ZERO)
				_verdict()
				_wait("verdict")
		"verdict":
			if _t > 3.0 * pace:
				_step = "done"
				running = false
				level.shift.finish(true, "КУПОЛ ДЕРЖИТСЯ", _final, stars())

func _wait(step: String) -> void:
	_step = step
	_t = 0.0

func _next() -> void:
	_i += 1
	if _i >= _stops.size():
		_exit()
		return
	var s: Dictionary = _stops[_i]
	npc.go(_route(s["off"], s["pos"]))
	_wait("walk")

func _arrive() -> void:
	var s: Dictionary = _stops[_i]
	if s["kind"] == "table":
		npc.look((s["obj"]["body"] as Node3D).global_position)
		_wait("look")
	else:
		npc.look((s["obj"] as Node3D).global_position)
		npc.act("knock")
		_knock_cover = null
		_knock_strips = -1
		_wait("knock")

func _exit() -> void:
	npc.go(_route(TAU, _free(_entry())))
	_wait("exit")

# ---------- проверки ----------

func _judge_table(t: Dictionary) -> void:
	var body: RigidBody3D = t["body"]
	var c := body.global_position
	var lines: Array[String] = []
	var pen := 0.0
	var upright := body.global_basis.y.dot(Vector3.UP) > 0.85
	var moved := Vector2(c.x - t["center"].x, c.z - t["center"].z).length() > 0.8
	if not upright:
		pen += 0.7
		lines.append(_pick(["Стол. Лежит. Гости, по-вашему, едят с пола?", "Кто перевернул стол? Это ресторан, а не бар в порту."]))
	elif moved:
		pen += 0.2
		lines.append("Стол уехал. Я сорок лет его ровнял по колонне.")
	var food := _count_on("food", body, float(t["top"]))
	var dish := _count_on("dish", body, float(t["top"]))
	var miss_food := maxi(int(t["food"]) - food, 0)
	var miss_dish := maxi(int(t["dish"]) - dish, 0)
	if miss_food > 0:
		pen += 0.3 * miss_food
		_add("еда", 0.3 * miss_food)
		lines.append(_pick(["Здесь стояла еда. Где еда?!", "Гость заказывал горячее. Горячее, где ты?",
			"Кто-то из вас съел банкет. Я вижу крошки на усах."]) if miss_food == 1 else
			"Со стола пропало %d блюда. Это не ремонт, это ограбление." % miss_food)
	if miss_dish > 0:
		var p := minf(0.12 * miss_dish, 0.5)
		pen += p
		_add("посуда", p)
		lines.append(_pick(["Посуда на полу. Прелестно.", "Тарелки где? Гостям из ладошек есть?"]))
	var chairs := _chairs_at(body)
	if chairs < 3:
		pen += 0.1 * (3 - chairs)
		_add("мебель", 0.1 * (3 - chairs))
		lines.append("Стул где? Гостю стоять?")
	if not level.board.sector_lit(int(t["sector"])):
		pen += 0.4
		_add("свет", 0.4)
		lines.append(_pick(["Почему здесь темно? Это романтический ужин или подвал?", "Темно, как у вас в голове. Свет!"]))
	if not upright:
		_add("мебель", 0.7)
	elif moved:
		_add("мебель", 0.2)
	pen = minf(pen, 1.3)
	score -= pen
	if lines.is_empty():
		if level.flood.level > 0.1 and not _wet_said:
			_wet_said = true
			_say("Сухо… почти. Ковёр хлюпает.", "snob")
		else:
			_say(_pick(["Приемлемо.", "Хм. Сносно.", "Ни пятнышка. Даже обидно.", "Так и быть."]),
				"pleased" if _rng.randf() < 0.5 else "snob")
	else:
		_say(" ".join(lines.slice(0, 2)), "disgust" if pen >= 0.3 else "snob")

## Сколько предметов из группы стоит на столе.
func _count_on(group: String, table: Node3D, top: float) -> int:
	var c := table.global_position
	var n := 0
	for b in level.get_tree().get_nodes_in_group(group):
		var p: Vector3 = (b as Node3D).global_position
		if Vector2(p.x - c.x, p.z - c.z).length() < 1.0 and p.y > top - 0.1 and p.y < top + 0.7:
			n += 1
	return n

func _chairs_at(table: Node3D) -> int:
	var c := table.global_position
	var n := 0
	for b in level.get_tree().get_nodes_in_group("chair"):
		var ch := b as Node3D
		var p := ch.global_position
		if Vector2(p.x - c.x, p.z - c.z).length() < 1.9 and p.y < 0.9 and ch.global_basis.y.dot(Vector3.UP) > 0.8:
			n += 1
	return mini(n, 3)

## Постучать: хлипкое может отвалиться.
func _do_knock(l: Node3D) -> void:
	var tapes: Array = l.crossing_tapes()
	_knock_strips = tapes.size()
	_knock_cover = l.cover if l.cover != null else level   # level — «стучал, затычки нет»
	var rb := l.cover as RigidBody3D
	if rb != null and not rb.freeze and not rb is Kombez and not rb.get_parent() is Kombez:
		rb.apply_impulse(l.inward() * rb.mass * 1.6)
	elif l.cover == null and tapes.size() > 0:
		var chance := peel_weak if tapes.size() <= 2 else (peel_three if tapes.size() == 3 else 0.0)
		if _rng.randf() < chance:
			(tapes[_rng.randi() % tapes.size()] as Node).queue_free()   # полоска отклеилась

func _judge_leak(l: Node3D) -> void:
	match int(l.state):
		1:   # OPEN
			_add("течи", 0.8)
			score -= 0.8
			_say(_pick(["Развалилось от одного прикосновения!", "Я только постучал! ТОЛЬКО ПОСТУЧАЛ!"]), "shock")
		2:   # DRIP
			_add("течи", 0.3)
			score -= 0.3
			_say("Сочится. Это вы называете «заделано»?", "disgust")
		_:
			var cover: Node3D = l.cover
			if cover != null:
				if cover.is_in_group("dish") or cover.is_in_group("food"):
					_add("посуда", 0.15)
					score -= 0.15
					_say("Дыра заткнута… тарелкой из сервиза. Держится. Я запомню.", "disgust")
				elif cover is Kombez or cover.get_parent() is Kombez:
					_say("Это… ваш коллега держит дыру? Ну, держит же.", "snob")
				else:
					_say(_pick(["Затычка. Колхоз, но держит.", "Держится. На честном слове и на соплях."]), "snob")
			elif _knock_strips >= 4:
				_say("Крепко. Некрасиво, но крепко.", "pleased")
			else:
				_say("Держится. Пока.", "snob")

## Всё время обхода: облили, примотали, хватают.
func _watch() -> void:
	var chest: Vector3 = npc.at() + Vector3.UP * 1.3
	for l in level.leaks:
		if int(l.state) != 1 and int(l.state) != 2:
			continue
		var n: Vector3 = l.inward()
		var d: Vector3 = chest - l.global_position
		var along := d.dot(n)
		var reach := 2.9 if int(l.state) == 1 else 1.3
		if along < 0.0 or along > reach or (d - n * along).length() > SPRAY_R + 0.6 * (along / reach):
			continue
		if level.shift.time < float(_spray_next.get(l, 0.0)):
			continue
		_spray_next[l] = level.shift.time + 3.0
		var first := not _sprayed.has(l)
		_sprayed[l] = true
		if int(l.state) == 1:
			var p := 0.7 if first else 0.3
			score -= p
			_add("течи", p)
			_say(_pick(["Вы что, издеваетесь?! Я в смокинге!", "Меня окатило! МЕНЯ!", "Это был мой лучший фрак."]), "wet")
		elif first:
			score -= 0.15
			_add("течи", 0.15)
			_say("Мне капает за шиворот. Чудесно.", "disgust")
	# примотали лентой
	if not _taped_said:
		var me: int = level.world.id_of(npc)
		for t in level.get_tree().get_nodes_in_group("tape"):
			if not t.is_queued_for_deletion() and (int(t.a_id) == me or int(t.b_id) == me):
				_taped_said = true
				score -= 1.0
				_add("хамство", 1.0)
				_say("Почему ко мне примотан ремонтник?! Отмотайте немедленно!", "shock")
				break
	# держат руками
	if _grab_said < 3 and level.shift.time >= _grab_next:
		for k in level.get_tree().get_nodes_in_group("kombez"):
			var kz := k as Kombez
			if kz != null and (kz.hand_l.held == npc or kz.hand_r.held == npc):
				_grab_said += 1
				_grab_next = level.shift.time + 6.0
				score -= 0.25
				_add("хамство", 0.25)
				_say(_pick(["Руки! Уберите руки!", "Не трогайте фрак грязными перчатками!", "Я вам не поручень!"]), "disgust")
				break

func _on_hit(_body: PhysicsBody3D, _speed: float) -> void:
	if not running:
		return
	npc.act("wobble")
	if _hit_pen >= START_PENALTY_CAP:
		npc.set_mood("shock")
		return
	_hit_pen += 0.4
	score -= 0.4
	_add("хамство", 0.4)
	_say(_pick(["Кто кинул?!", "Это что сейчас было?!", "В меня?! Бросаться?!", "Я запомнил ваши лица."]), "shock")

func _verdict() -> void:
	var w: float = level.flood.level
	var wet := 0.0
	var wl := "Сухо. Удивительно."
	if w > 0.35:
		wet = 1.5
		wl = "В зале по колено воды. Гостям выдать ласты?"
	elif w > 0.15:
		wet = 0.9
		wl = "Гости сидят по щиколотку в воде."
	elif w > 0.05:
		wet = 0.4
		wl = "Под ногами хлюпает."
	score -= wet
	_add("вода", wet)
	var st := stars()
	var line: String = [
		"Это не ремонт, это преступление. Вон.",
		"Отвратительно. Я напишу о вас отзыв. Два отзыва.",
		"Я видел ремонт и получше. В тюремной столовой.",
		"Посредственно. Как и всё в вашей жизни, полагаю.",
		"Сносно. Чаевых не будет, но и жалобы тоже.",
		"Безупречно. Подозрительно безупречно. Что вы спрятали?",
	][st]
	_say(wl + " " + line, "pleased" if st >= 4 else ("disgust" if st <= 2 else "snob"))
	_final = "Метрдотель: «%s»" % line
	var worst := ""
	var most := 0.25
	for k in _cat:
		if float(_cat[k]) > most:
			most = float(_cat[k])
			worst = k
	if worst != "":
		_final += "\nБольше всего не понравилось: " + {
			"еда": "пропавшая еда", "посуда": "посуда где попало", "мебель": "мебель вверх ногами",
			"свет": "темнота", "вода": "вода в зале", "течи": "течи при клиенте", "хамство": "хамство бригады",
		}[worst]

## Строгий: любая заметная претензия (от 0.2) уже стоит звезды.
func stars() -> int:
	return clampi(floori(score + 0.2), 0, 5)

func _add(cat: String, v: float) -> void:
	_cat[cat] = float(_cat.get(cat, 0.0)) + v

func _say(text: String, face: String) -> void:
	said.append(text)
	npc.say(text, face)

func _pick(arr: Array) -> String:
	return arr[_rng.randi() % arr.size()]
