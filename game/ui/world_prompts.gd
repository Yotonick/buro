extends Control
## Всплывающие подсказки по месту: смотришь на предмет или стоишь рядом с делом —
## под прицелом появляется короткая плашка «[клавиша] что сделать» и плавно гаснет.
## Клавиши — из текущей раскладки. Всё слушается Settings.show_hints.
##
## Откуда берутся подсказки (строка — [клавиши, текст, тихая?]; клавиши — действие,
## массив действий или "" — без клавиши, значок «!»; тихая — без звука «pop»):
##   1) инструмент на поясе своего игрока: метод belt_hint(k) -> Array;
##   2) то, на что смотрит игрок (луч на REACH м), или его родители до 3 уровней:
##      метод prompt_hint(k, dist) -> Array, либо мета "prompt" (Array или Callable(k, dist));
##      ничего не сказало, а это тело — общая подсказка «схватить» (ближе GRAB_REACH);
##   3) дела рядом: узлы группы "prompt_near" с методом near_hint(k) -> Array.
## Больше двух строк не показывается.

const Style := preload("res://ui/ui_style.gd")

const REACH := 3.0
const GRAB_REACH := 2.2
const GRAB := ["grab_left", "grab_right"]
const PROBE_EVERY := 0.1
const MAX_ROWS := 2

var world: Node                 ## NetWorld — из него берём своего Комбеза
var hud: Node                   ## на паузе подсказки прячутся
var rows: Array = []            ## что сейчас показано (для тестов)

var _box: VBoxContainer
var _shown_key := ""
var _probe_t := 0.0
var _pop_cd := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_box.add_theme_constant_override("separation", 6)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.offset_top = 34
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_box)
	_box.modulate.a = 0.0

func _process(dt: float) -> void:
	_pop_cd -= dt
	_probe_t -= dt
	if _probe_t <= 0.0:
		_probe_t = PROBE_EVERY
		_set_rows(_gather())
	var want := 1.0 if not rows.is_empty() else 0.0
	_box.modulate.a = move_toward(_box.modulate.a, want, dt * (8.0 if want > 0.5 else 4.0))
	_box.offset_top = lerpf(_box.offset_top, 34.0 if want > 0.5 else 44.0, 1.0 - exp(-dt * 14.0))
	if _box.modulate.a <= 0.0 and rows.is_empty() and _box.get_child_count() > 0:
		_clear()

func _gather() -> Array:
	if not Settings.show_hints or world == null:
		return []
	if hud != null and hud.has_method("is_paused") and hud.is_paused():
		return []
	if hud != null and hud.has_method("tablet_open") and hud.tablet_open():
		return []
	var k: Kombez = world.local_kombez
	if k == null or not is_instance_valid(k) or k.is_ko():
		return []
	return gather(k)

## Подсказки для Комбеза k прямо сейчас (не больше двух строк).
static func gather(k: Kombez) -> Array:
	var out: Array = []
	for t in k.get_tree().get_nodes_in_group("tool"):
		if t.has_method("belt_hint"):
			var r: Array = t.belt_hint(k)
			if not r.is_empty():
				out.append_array(r)
				break
	var q := PhysicsRayQueryParameters3D.create(k.aim_origin(), k.aim_origin() + k.aim_dir() * REACH, 1 | 2 | 4 | 16)
	q.exclude = [k.get_rid(), k.hand_l.get_rid(), k.hand_r.get_rid()]
	var hit := k.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] is Node:
		var target: Node = hit["collider"]
		if target is StaticBody3D:   # мелочь на полу (пробка, заглушка): луч чуть промахнулся — берём то, что рядом
			var near := _small_near(k, hit["position"])
			if near != null:
				target = near
		var dist := k.aim_origin().distance_to(hit["position"])
		out.append_array(hint_of(target, k, dist))
	if out.size() < MAX_ROWS:
		for n in k.get_tree().get_nodes_in_group("prompt_near"):
			var r: Array = n.near_hint(k)
			if not r.is_empty():
				out.append_array(r)
				break
	var seen := {}
	var res: Array = []
	for row in out:
		var key := str(row[1])
		if seen.has(key):
			continue
		seen[key] = true
		res.append(row)
	return res.slice(0, MAX_ROWS)

static func _small_near(k: Kombez, at: Vector3) -> Node:
	var sq := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.15
	sq.shape = sph
	sq.transform = Transform3D(Basis.IDENTITY, at)
	sq.collision_mask = 2
	sq.exclude = [k.hand_l.get_rid(), k.hand_r.get_rid()]
	var hits := k.get_world_3d().direct_space_state.intersect_shape(sq, 1)
	return hits[0]["collider"] if not hits.is_empty() else null

## Что говорит про себя предмет, на который смотрят.
static func hint_of(node: Node, k: Kombez, dist: float) -> Array:
	var n := node
	for i in 4:
		if n == null:
			break
		if n.has_method("prompt_hint"):
			return n.prompt_hint(k, dist)
		if n.has_meta("prompt"):
			var p: Variant = n.get_meta("prompt")
			if p is Callable:
				return (p as Callable).call(k, dist)
			if dist <= GRAB_REACH:
				return p
			return []
		n = n.get_parent()
	if node is RigidBody3D and dist <= GRAB_REACH:
		return [[GRAB, "схватить", true]]
	return []

func _set_rows(r: Array) -> void:
	var key := str(r)
	if key == _shown_key:
		return
	var loud := false
	for row in r:
		if row.size() < 3 or not row[2]:
			loud = true
	rows = r
	if r.is_empty():
		_shown_key = ""
		return   # гаснет плавно, содержимое уберётся, когда погаснет
	_shown_key = key
	_clear()
	for row in r:
		_box.add_child(_row(row[0], str(row[1])))
	if loud and _pop_cd <= 0.0:
		_pop_cd = 0.8
		UiSound.play("pop")

func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()

func _row(keys: Variant, text: String) -> Control:
	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Style.NAVY, 0.82)
	sb.border_color = Color(Style.SIGNAL, 0.9)
	sb.border_width_left = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", sb)
	wrap.add_child(pc)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(h)
	var list: Array = keys if keys is Array else ([keys] if str(keys) != "" else [])
	if list.is_empty():
		var bang := Style.key_text("!", 26)
		bang.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bang)
	for i in list.size():
		if i > 0:
			var sl := Style.label("/", 16, Style.MUTED)
			sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(sl)
		var cap := Style.key(str(list[i]), 26)
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(cap)
	var l := Style.label(text, 18, Style.TEXT)
	l.add_theme_font_override("font", Style.BOLD)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return wrap
