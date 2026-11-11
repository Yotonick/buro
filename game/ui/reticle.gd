extends Control
## Прицел: точка в центре экрана — туда тянутся руки, клеится лента и смотрит E.
##   • дотянешься до предмета — оранжевое кольцо, а сам предмет подсвечивается по краю;
##   • дотянешься до стены/пола (ухватиться) — белое тонкое кольцо;
##   • не дотянешься — просто бледная точка.
## С вещью в руках подсветки нет. В нокауте, на паузе и с планшетом — прицел гаснет.

const Style := preload("res://ui/ui_style.gd")
const RIM := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.15, 1.0);
uniform float strength = 0.8;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = tint.rgb * (rim * 1.4 + 0.12) * strength;
}
"""

enum Mode { FAR, SURFACE, ITEM, HIDDEN }

var world: Node
var hud: Node
var mode := Mode.FAR
var highlighted: Node3D        ## что сейчас подсвечено (для тестов)

var _rim: ShaderMaterial
var _lit: Array[GeometryInstance3D] = []
var _ring := 0.0               ## плавный радиус кольца
var _alpha := 1.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rim = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = RIM
	_rim.shader = sh

func _process(dt: float) -> void:
	var k := _kombez()
	var want_lit: Node3D = null
	if k == null:
		mode = Mode.HIDDEN
	else:
		mode = Mode.FAR
		var hit := k.aim_hit()
		if not hit.is_empty() and k.can_reach(hit["position"]):
			var c: Object = hit["collider"]
			if c is PhysicsBody3D and not (c as Node).is_in_group("no_grab"):
				mode = Mode.ITEM if (c is RigidBody3D) else Mode.SURFACE
				if mode == Mode.ITEM and not k.is_holding():
					want_lit = c as Node3D
	_set_lit(want_lit)
	var r := {Mode.FAR: 0.0, Mode.SURFACE: 7.0, Mode.ITEM: 11.0, Mode.HIDDEN: 0.0}[mode] as float
	_ring = lerpf(_ring, r, 1.0 - exp(-dt * 18.0))
	_alpha = move_toward(_alpha, 0.0 if mode == Mode.HIDDEN else 1.0, dt * 6.0)
	queue_redraw()

func _kombez() -> Kombez:
	if world == null:
		return null
	if hud != null and ((hud.has_method("is_paused") and hud.is_paused()) or (hud.has_method("tablet_open") and hud.tablet_open())):
		return null
	var k: Kombez = world.local_kombez
	if k == null or not is_instance_valid(k) or k.is_ko() or not k.is_inside_tree():
		return null
	return k

func _draw() -> void:
	if _alpha <= 0.01:
		return
	var c := size * 0.5
	var dot := Color(1, 1, 1, (0.55 if mode == Mode.FAR else 0.9) * _alpha)
	draw_circle(c, 3.2, Color(0, 0, 0, 0.35 * _alpha))
	draw_circle(c, 2.2, dot)
	if _ring > 1.5:
		var col := Style.SIGNAL if mode == Mode.ITEM else Color(1, 1, 1, 0.8)
		col.a *= _alpha * clampf((_ring - 1.5) / 4.0, 0.0, 1.0)
		draw_arc(c, _ring + 1.0, 0, TAU, 40, Color(0, 0, 0, col.a * 0.35), 3.5, true)
		draw_arc(c, _ring, 0, TAU, 40, col, 2.0 if mode == Mode.ITEM else 1.4, true)

## Подсветка края у предмета, который схватится.
func _set_lit(n: Node3D) -> void:
	if n == highlighted and (n == null or is_instance_valid(n)):
		return
	for g in _lit:
		if is_instance_valid(g) and g.material_overlay == _rim:
			g.material_overlay = null
	_lit.clear()
	highlighted = n if n != null and is_instance_valid(n) else null
	if highlighted != null and Settings.show_hints:
		_collect(highlighted, 0)
		for g in _lit:
			g.material_overlay = _rim

func _collect(n: Node, depth: int) -> void:
	if depth > 4 or _lit.size() >= 24:
		return
	for c in n.get_children():
		if c is PhysicsBody3D:   # вложенное отдельное тело — не наше
			continue
		if c is MeshInstance3D and (c as MeshInstance3D).material_overlay == null:
			_lit.append(c)
		_collect(c, depth + 1)

func _exit_tree() -> void:
	_set_lit(null)
