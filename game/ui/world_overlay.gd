extends Control
## То, что привязано к людям в мире, но рисуется поверх экрана (чётко, в стиле бюро):
##   — плашки с именами над напарниками: видны рядом (NAME_NEAR м) или когда на напарника смотришь;
##   — комикс-пузырь с репликой над говорящим (узлы группы "speaker":
##     speech_text() -> String, speech_anchor() -> Vector3, speech_alpha() -> float).
##     Говорящий вне экрана — пузырь не рисуется, вместо него HUD показывает строку внизу.

const Style := preload("res://ui/ui_style.gd")

const NAME_NEAR := 7.0
const NAME_FAR := 30.0
const NAME_LOOK := 0.14          ## рад: «смотрю на него»
const BUBBLE_W := 360.0

var world: Node
var hud: Node

var _tags := {}                  ## Kombez -> PanelContainer
var _bubble: Control
var _bubble_label: Label
var _bubble_tail := Vector2.ZERO
var _bubble_text := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble = Control.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.visible = false
	_bubble.draw.connect(_draw_bubble)
	add_child(_bubble)
	_bubble_label = Style.hand("", 27, Style.INK)
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(_bubble_label)

func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	_names(cam, dt)
	_speech(cam)

# ---------- имена ----------

func _names(cam: Camera3D, dt: float) -> void:
	var me: Node = world.local_kombez if world != null else null
	var alive := {}
	for k in get_tree().get_nodes_in_group("kombez"):
		if k == me or k.peer_id <= 0 or k.player_name == "":
			continue
		alive[k] = true
		var tag: Control = _tags.get(k)
		if tag == null:
			tag = _make_tag(k)
			_tags[k] = tag
		var want := 0.0
		var head: Vector3 = k.get_global_transform_interpolated().origin + Vector3.UP * 1.2
		if cam != null and not cam.is_position_behind(head):
			var to := head - cam.global_position
			var d := to.length()
			var near: float = me.global_position.distance_to(k.global_position) if is_instance_valid(me) else d
			var look := (-cam.global_basis.z).angle_to(to)
			if near < NAME_NEAR or (look < NAME_LOOK and d < NAME_FAR):
				want = 1.0
			var p := cam.unproject_position(head)
			tag.position = (p - Vector2(tag.size.x * 0.5, tag.size.y)).round()
		tag.modulate.a = move_toward(tag.modulate.a, want, dt * 5.0)
		tag.visible = tag.modulate.a > 0.01
	for k in _tags.keys():
		if not alive.has(k):
			_tags[k].queue_free()
			_tags.erase(k)

func _make_tag(k: Node) -> Control:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Style.NAVY, 0.85)
	sb.set_corner_radius_all(5)
	sb.border_color = k.suit_color
	sb.border_width_bottom = 3
	sb.content_margin_left = 8
	sb.content_margin_right = 9
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(h)
	var dot := ColorRect.new()
	dot.color = k.suit_color
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)
	var l := Style.label(k.player_name, 16, Style.TEXT)
	l.add_theme_font_override("font", Style.BOLD)
	h.add_child(l)
	pc.modulate.a = 0.0
	add_child(pc)
	return pc

## Видна ли сейчас плашка с именем этого Комбеза (для тестов).
func tag_visible(k: Node) -> bool:
	var t: Control = _tags.get(k)
	return t != null and t.visible and t.modulate.a > 0.5

# ---------- пузырь ----------

func _speech(cam: Camera3D) -> void:
	var on_screen := false
	var who: Node = null
	for s in get_tree().get_nodes_in_group("speaker"):
		if s.speech_text() != "":
			who = s
			break
	if who != null and cam != null:
		var at: Vector3 = who.speech_anchor()
		if not cam.is_position_behind(at):
			var p := cam.unproject_position(at)
			var vr := get_viewport_rect().size
			if p.x > 0 and p.y > 0 and p.x < vr.x and p.y < vr.y:
				on_screen = true
				_place_bubble(who.speech_text(), p, vr)
				_bubble.modulate.a = who.speech_alpha()
	_bubble.visible = on_screen
	if hud != null:
		hud.line_hidden = on_screen

func _place_bubble(text: String, tip: Vector2, vr: Vector2) -> void:
	if text != _bubble_text:
		_bubble_text = text
		_bubble_label.text = text
		_bubble_label.custom_minimum_size = Vector2(BUBBLE_W - 36, 0)
		_bubble_label.size = Vector2(BUBBLE_W - 36, 0)
	var lsz := Style.HAND.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, BUBBLE_W - 36, 27,
		-1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var sz := Vector2(BUBBLE_W, lsz.y + 24)
	var pos := tip - Vector2(sz.x * 0.5, sz.y + 26)
	pos.x = clampf(pos.x, 12, vr.x - sz.x - 12)
	pos.y = clampf(pos.y, 12, vr.y - sz.y - 40)
	_bubble.position = pos.round()
	_bubble.size = sz
	_bubble_label.position = Vector2(18, 12)
	_bubble_label.size = Vector2(sz.x - 36, lsz.y)
	_bubble_tail = tip - _bubble.position
	_bubble.queue_redraw()

func _draw_bubble() -> void:
	var sz := _bubble.size
	var r := Rect2(Vector2.ZERO, sz)
	var base_x := clampf(_bubble_tail.x, 30, sz.x - 30)
	var tip := Vector2(clampf(_bubble_tail.x, 10, sz.x - 10), minf(_bubble_tail.y, sz.y + 24))
	if tip.y < sz.y + 6:
		tip.y = sz.y + 18
	var tail := PackedVector2Array([Vector2(base_x - 16, sz.y - 2), Vector2(base_x + 12, sz.y - 2), tip])
	# тень, обводка, бумага
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.25)
	shadow.set_corner_radius_all(16)
	_bubble.draw_style_box(shadow, r.grow(0).grow_individual(-2, -2, 2, 4))
	_bubble.draw_colored_polygon(_offset(tail, Vector2(2, 4)), Color(0, 0, 0, 0.25))
	var edge := StyleBoxFlat.new()
	edge.bg_color = Style.INK
	edge.set_corner_radius_all(16)
	_bubble.draw_style_box(edge, r.grow(3))
	var grown := PackedVector2Array([tail[0] + Vector2(-3, 0), tail[1] + Vector2(3, 0), tail[2] + Vector2(0, 4)])
	_bubble.draw_colored_polygon(grown, Style.INK)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Style.PAPER.lightened(0.35)
	paper.set_corner_radius_all(14)
	_bubble.draw_style_box(paper, r)
	_bubble.draw_colored_polygon(tail, Style.PAPER.lightened(0.35))

static func _offset(p: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var o := PackedVector2Array()
	for v in p:
		o.append(v + d)
	return o

func bubble_visible() -> bool:
	return _bubble.visible
