extends Node3D
## Камера игрока. По умолчанию — от первого лица (Settings.start_view).
## Колёсико — плавный зум: вплотную — первое лицо, дальше — «за спиной», ещё дальше — общий план.
## Клавиша view_toggle (V) — сразу 1-е ⇄ 3-е лицо.
##
## Камера всегда стоит в глазах Комбеза (Kombez.eye_point) или на штанге позади них, поэтому
## центр экрана совпадает с прицелом рук, ленты, E и подсказок в любом виде.
## В первом лице своя голова и каска не рисуются (слой HEAD_LAYER), но тень от них остаётся;
## тело, руки и ноги видны. В нокауте вид заваливается вместе с телом и темнеет по краям.
## Скрипты кадров могут по-старому ставить _arm.spring_length — камера примет это как зум.

const SENS := 0.0026           ## базовая; умножается на Settings.mouse_sens
const DISTANCE := 4.4          ## обычный вид от третьего лица (V)
const ZOOM_MIN := 1.3          ## ближе — уже первое лицо
const ZOOM_MAX := 8.0
const ZOOM_STEP := 1.25        ## шаг колёсика (во сколько раз)
const FP_EDGE := 0.6           ## штанга короче — считаем, что это первое лицо
const HEAD_LAYER := 1 << 19    ## слой 20: своя голова и каска
const SHOULDER := 0.5          ## от третьего лица камера сдвинута вправо — голова не закрывает прицел
const AIM_FAR := 40.0
const PITCH_FP := Vector2(-1.45, 1.4)
const PITCH_TP := Vector2(-1.25, 1.1)

const VIGNETTE := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform float time = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.7;
	float d = length(uv);
	float edge = smoothstep(0.95 - amount * 0.6, 1.25 - amount * 0.45, d * 1.6);
	float pulse = 0.85 + 0.15 * sin(time * 5.0);
	float a = clamp(edge * pulse + amount * 0.22, 0.0, 0.93) * amount;
	COLOR = vec4(0.03, 0.02, 0.07, a);
}
"""

var target: Node3D
var yaw := 0.0
var pitch := -0.3
var camera: Camera3D
var zoom := 0.0                ## куда едет штанга (0 — первое лицо)
var ko_amount := 0.0           ## 0..1 — насколько «завалило» (для эффекта и тестов)
## Куда смотреть Комбезу (рукам, ленте): из его глаз ровно в ту точку, что в центре экрана.
## В первом лице это просто yaw/pitch; со сдвигом «из-за плеча» — чуть поправленные.
var aim_yaw := 0.0
var aim_pitch := -0.3
var shoulder := 0.0            ## текущий сдвиг вправо (м)
var _eye_s := Vector3.ZERO     ## сглаженные глаза
var _dist := 0.0               ## где штанга сейчас
var _arm: SpringArm3D
var _set_len := -1.0           ## что сами поставили в _arm.spring_length в прошлый раз
var _fp_shown := false         ## голова сейчас спрятана
var _head_owner: Node3D        ## чью голову прятали
var _vignette: ColorRect
var _vmat: ShaderMaterial
var _t := 0.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	zoom = 0.0 if Settings.start_view != "third" else DISTANCE
	_dist = zoom
	_arm = SpringArm3D.new()
	_arm.spring_length = _dist
	_set_len = _dist
	_arm.collision_mask = 1
	_arm.margin = 0.2
	var sh := SphereShape3D.new()
	sh.radius = 0.2
	_arm.shape = sh
	add_child(_arm)
	camera = Camera3D.new()
	camera.far = 200.0
	camera.near = 0.04
	_arm.add_child(camera)
	camera.make_current()
	_update_fov()
	Settings.changed.connect(_update_fov)

	var cl := CanvasLayer.new()
	cl.layer = -1   # под интерфейсом
	add_child(cl)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vmat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = VIGNETTE
	_vmat.shader = shader
	_vignette.material = _vmat
	_vignette.visible = false
	cl.add_child(_vignette)

func is_first_person() -> bool:
	return _dist < FP_EDGE

## Сразу поставить вид (без плавного переезда): 0 — первое лицо, иначе длина штанги.
func set_zoom(z: float, instant := false) -> void:
	zoom = 0.0 if z < FP_EDGE else clampf(z, ZOOM_MIN, ZOOM_MAX)
	if instant:
		_dist = zoom
		_apply_arm()

func zoom_in() -> void:
	set_zoom(0.0 if zoom <= ZOOM_MIN + 0.01 else maxf(zoom / ZOOM_STEP, ZOOM_MIN))

func zoom_out() -> void:
	set_zoom(ZOOM_MIN if zoom < FP_EDGE else zoom * ZOOM_STEP)

func toggle_view() -> void:
	set_zoom(DISTANCE if zoom < FP_EDGE else 0.0)

func _update_fov() -> void:
	var t := clampf((_dist - FP_EDGE) / (ZOOM_MIN + 0.8 - FP_EDGE), 0.0, 1.0)
	camera.fov = lerpf(Settings.fov_fp, Settings.fov, t)

func _unhandled_input(e: InputEvent) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		handle_input(e)

## Мышь и V (зовётся, когда мышь захвачена игрой; тесты зовут напрямую).
func handle_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var k := SENS * Settings.mouse_sens
		yaw = wrapf(yaw - e.relative.x * k, -PI, PI)
		var lim := PITCH_FP if is_first_person() else PITCH_TP
		pitch = clampf(pitch - e.relative.y * k * (-1.0 if Settings.invert_y else 1.0), lim.x, lim.y)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()
	if e.is_action_pressed("view_toggle", false, true):
		toggle_view()

func snap() -> void:
	if target != null:
		_eye_s = _eye(target.global_position)
		global_position = _eye_s
		aim_yaw = yaw
		aim_pitch = pitch

func _eye(body_pos: Vector3) -> Vector3:
	return Kombez.eye_point(body_pos, yaw)

func _apply_arm() -> void:
	_arm.spring_length = _dist
	_set_len = _dist

func _process(dt: float) -> void:
	_t += dt
	if not is_equal_approx(_arm.spring_length, _set_len):   # штангу поставили снаружи (скрипт кадров)
		zoom = _arm.spring_length
		_dist = zoom
	if absf(_dist - zoom) > 0.002:
		_dist = lerpf(_dist, zoom, 1.0 - exp(-dt * 11.0))
		if absf(_dist - zoom) < 0.01:
			_dist = zoom
	_update_fov()
	_apply_arm()
	if target == null or not is_instance_valid(target):
		return
	var fp := is_first_person()
	_show_head(not fp)
	if fp:
		pitch = clampf(pitch, PITCH_FP.x, PITCH_FP.y)
	else:
		pitch = clampf(pitch, PITCH_TP.x, PITCH_TP.y)

	var xf := target.get_global_transform_interpolated()
	var p := _eye(xf.origin)
	var ko: bool = target.has_method("is_ko") and target.is_ko()
	ko_amount = move_toward(ko_amount, 1.0 if ko else 0.0, dt * (3.0 if ko else 1.6))
	var view := Basis.from_euler(Vector3(pitch, yaw, 0))
	if _eye_s.distance_to(p) > 2.0:   # телепорт, возрождение
		_eye_s = p
	if fp:
		# глаза качаются вместе с пружинным телом — по вертикали сглаживаем сильнее, чтобы не укачало
		var nx := _eye_s.lerp(p, 1.0 - exp(-dt * 30.0))
		nx.y = lerpf(_eye_s.y, p.y, 1.0 - exp(-dt * 14.0))
		_eye_s = nx
	else:
		_eye_s = _eye_s.lerp(p, 1.0 - exp(-dt * 16.0))
	var pivot := _eye_s
	shoulder = SHOULDER * clampf((_dist - FP_EDGE) / (ZOOM_MIN - FP_EDGE), 0.0, 1.0)
	if shoulder > 0.001:
		var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		var want := pivot + right * shoulder
		var q := PhysicsRayQueryParameters3D.create(pivot, want + right * 0.2, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():   # справа стена — прижимаемся ближе к голове
			want = pivot + right * maxf(pivot.distance_to(hit["position"]) - 0.2, 0.0)
		pivot = want
	global_position = pivot
	if fp and ko_amount > 0.001:
		# в нокауте смотрим из головы, которая валится вместе с телом
		var head := xf * Vector3(0, Kombez.EYE_UP - 0.06, -Kombez.EYE_FWD)
		global_position = global_position.lerp(head, ko_amount)
		var up := xf.basis.orthonormalized().y
		var tilt := Quaternion(Vector3.UP, up) if up.dot(Vector3.UP) > -0.99 else Quaternion.IDENTITY
		var wob := Basis(Vector3.FORWARD, sin(_t * 2.3) * 0.12 * ko_amount)
		view = Basis(Quaternion.IDENTITY.slerp(tilt, ko_amount)) * view * wob
	global_basis = view
	_update_aim(fp)
	_vignette.visible = ko_amount > 0.001
	if _vignette.visible:
		_vmat.set_shader_parameter("amount", ko_amount * (1.0 if fp else 0.6))
		_vmat.set_shader_parameter("time", _t)

## Куда смотреть Комбезу: от третьего лица находим, что в центре экрана, и целимся туда из глаз.
func _update_aim(fp: bool) -> void:
	aim_yaw = yaw
	aim_pitch = pitch
	if fp or shoulder < 0.001 or not camera.is_inside_tree():
		return
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * AIM_FAR, 1 | 2 | 4 | 16)
	var ex: Array[RID] = []
	if target is CollisionObject3D:
		ex.append((target as CollisionObject3D).get_rid())
	for hn in ["hand_l", "hand_r"]:
		var h: Variant = target.get(hn)
		if h is CollisionObject3D:
			ex.append((h as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var pt: Vector3 = hit["position"] if not hit.is_empty() else from + fwd * AIM_FAR
	var eye := _eye(target.global_position)
	var d := pt - eye
	if d.dot(fwd) < 0.3:   # точка позади глаз (вплотную к стене за спиной) — целимся просто по камере
		return
	d = d.normalized()
	aim_yaw = atan2(-d.x, -d.z)
	aim_pitch = asin(clampf(d.y, -1.0, 1.0))

## Своя голова и каска: в первом лице — только тень.
func _show_head(show: bool) -> void:
	if _head_owner != target:
		if _head_owner != null and is_instance_valid(_head_owner) and "visual" in _head_owner:
			_head_owner.visual.set_head_layers(1)
		_head_owner = target
		_fp_shown = false
		camera.cull_mask = 0xFFFFF
	var hide := not show
	if hide == _fp_shown:
		return
	_fp_shown = hide
	if "visual" in target and target.visual != null and target.visual.has_method("set_head_layers"):
		target.visual.set_head_layers(HEAD_LAYER)
	camera.cull_mask = 0xFFFFF & ~HEAD_LAYER if hide else 0xFFFFF
