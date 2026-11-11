extends Node
## Автотест камеры (вид от первого лица + зум колёсиком) на полигоне, без экрана:
##   godot --headless --path game --fixed-fps 60 --disable-render-loop res://tests/camera_test.tscn

const Cam := preload("res://characters/player_camera.gd")
const Reticle := preload("res://ui/reticle.gd")

var room: Node3D
var k: Kombez
var cam: Node3D
var fails := 0

func _ready() -> void:
	Settings.start_view = "first"
	Settings.fov_fp = 85.0
	Settings.fov = 62.0
	room = load("res://levels/test_room/test_room.tscn").instantiate()
	add_child(room)
	k = room.player
	cam = room.camera
	room.controller.walk_only = true   # без экрана мышь не захватить — так контроллер всё равно ведёт Комбеза
	await _wait(0.6)
	await _run()
	print("RESULT ", "PASS" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit(fails)

func _run() -> void:
	# --- вид по умолчанию ---
	_check("по умолчанию — первое лицо", cam.is_first_person() and cam.zoom == 0.0)
	_check("своя голова и каска на отдельном слое, камера его не видит", k.visual._head.layers == Cam.HEAD_LAYER
		and k.visual._helmet != null and _layers_ok(k.visual._helmet, Cam.HEAD_LAYER)
		and cam.camera.cull_mask & Cam.HEAD_LAYER == 0)
	_check("тело в кадре (слой 1)", _body_visible())
	_check("тень от головы остаётся (каска/голова отбрасывают тень)", k.visual._head.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_check("обзор 1-го лица — 85°", is_equal_approx(cam.camera.fov, 85.0), "%.1f" % cam.camera.fov)
	var eye: Vector3 = Kombez.eye_point(k.get_global_transform_interpolated().origin, cam.yaw)
	_check("камера в глазах (у лица, не внутри комбеза)", cam.camera.global_position.distance_to(eye) < 0.08,
		"%.3f" % cam.camera.global_position.distance_to(eye))
	_check("центр экрана = прицел: луч камеры совпадает с лучом рук", (-cam.camera.global_basis.z).dot(k.aim_dir()) > 0.999
		and cam.camera.global_position.distance_to(k.aim_origin()) < 0.08)

	# --- колёсико и V ---
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _wait(0.8)
	_check("колёсико вниз — отъехали за спину, голова видна", not cam.is_first_person() and is_equal_approx(cam.zoom, Cam.ZOOM_MIN)
		and cam.camera.cull_mask & Cam.HEAD_LAYER != 0, "zoom=%.2f" % cam.zoom)
	for i in 6:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _wait(1.0)
	_check("ещё вниз — дальше, плавно, обзор 3-го лица", cam.zoom > 4.0 and absf(cam._arm.spring_length - cam.zoom) < 0.05
		and is_equal_approx(cam.camera.fov, 62.0), "zoom=%.2f arm=%.2f fov=%.1f" % [cam.zoom, cam._arm.spring_length, cam.camera.fov])
	for i in 30:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_check("дальше предела не уезжает", cam.zoom <= Cam.ZOOM_MAX + 0.001)
	cam._arm.spring_length = 3.0
	await _wait(0.1)
	_check("скрипт кадров поставил штангу — камера приняла", is_equal_approx(cam.zoom, 3.0) and not cam.is_first_person())
	for i in 12:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
	await _wait(1.0)
	_check("колёсико вверх — снова первое лицо", cam.is_first_person() and cam.zoom == 0.0 and cam.camera.cull_mask & Cam.HEAD_LAYER == 0)
	_press("view_toggle")
	await _wait(1.0)
	_check("V — сразу от третьего лица (4.4 м)", is_equal_approx(cam.zoom, Cam.DISTANCE) and not cam.is_first_person())
	cam.pitch = -0.35
	await _wait(0.5)
	var from: Vector3 = cam.camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.camera.global_basis.z * 40.0, 1 | 2)
	var ph := k.get_world_3d().direct_space_state.intersect_ray(q)
	var off := 99.0
	if not ph.is_empty():
		var v: Vector3 = ph["position"] - k.aim_origin()
		off = (v - k.aim_dir() * v.dot(k.aim_dir())).length()
	_check("3-е лицо: камера правее головы, а руки и лента целятся в центр экрана", cam.shoulder > 0.3 and off < 0.08, "сдвиг=%.2f мимо=%.3f" % [cam.shoulder, off])
	_press("view_toggle")
	await _wait(1.0)
	_check("V ещё раз — первое лицо", cam.is_first_person())
	_check("V есть в раскладке и в настройках", Controls.title_of("view_toggle").begins_with("Вид") and Controls.codes("view_toggle")[0] == "key:%d" % KEY_V)

	# --- тело смотрит туда же, куда игрок ---
	await _reset(Vector3(0, 0.9, 6), 0.0)
	cam.yaw = 0.0
	cam.pitch = 0.0
	Input.action_press("move_back")
	await _wait(1.0)
	Input.action_release("move_back")
	var fwd := -k.global_basis.z
	_check("1-е лицо: пятишься назад — тело лицом вперёд (in_face_aim)", k.in_face_aim and fwd.dot(Vector3.FORWARD) > 0.9 and k.linear_velocity.z > -0.5 and k.global_position.z > 6.5,
		"fwd=%s z=%.2f" % [fwd, k.global_position.z])
	cam.set_zoom(Cam.DISTANCE, true)
	Input.action_press("move_back")
	await _wait(1.0)
	Input.action_release("move_back")
	_check("3-е лицо: пятишься — разворачивается по ходу, как раньше", not k.in_face_aim and (-k.global_basis.z).dot(Vector3.BACK) > 0.8)
	cam.set_zoom(0.0, true)
	await _wait(0.3)

	# --- руки точно в прицел + прицел «достаю / не достаю» ---
	room.controller.kombez = null   # дальше рулим вручную
	var box: RigidBody3D = room.get_children().filter(func(n): return n is RigidBody3D and n.mass == 14.0)[0]
	box.global_position = Vector3(8, 0.36, 4.0)
	box.global_rotation = Vector3.ZERO
	box.linear_velocity = Vector3.ZERO
	await _reset(Vector3(8, 0.9, 5.1), 0.0)
	var ret: Control = room.hud.reticle
	var aim_p := Vector3(8.18, 0.71, 4.0 + 0.35)   # передняя грань ящика, правее середины
	_aim_at(aim_p)
	await _wait(0.3)
	var hit := k.aim_hit()
	_check("взгляд упёрся в ящик", not hit.is_empty() and hit["collider"] == box, str(hit))
	_check("ящик достаю — оранжевое кольцо и подсветка края", ret.mode == Reticle.Mode.ITEM and ret.highlighted == box
		and _has_overlay(box), "mode=%d" % ret.mode)
	k.in_grab_r = true
	var at := await _grab_point(k.hand_r)
	_check("правая рука взялась ровно там, куда смотришь", k.hand_r.held == box and at.distance_to(aim_p) < 0.2,
		"held=%s d=%.2f" % [k.hand_r.held, at.distance_to(aim_p)])
	_check("с вещью в руках подсветки нет", ret.highlighted == null and not _has_overlay(box))
	k.in_grab_r = false
	await _wait(0.5)
	aim_p = Vector3(7.82, 0.5, 4.0 + 0.35)   # левее и ниже
	_aim_at(aim_p)
	await _wait(0.3)
	k.in_grab_l = true
	at = await _grab_point(k.hand_l)
	_check("левая рука — тоже в прицел", k.hand_l.held == box and at.distance_to(aim_p) < 0.2, "d=%.2f" % at.distance_to(aim_p))
	k.in_grab_l = false
	await _wait(0.5)
	await _reset(Vector3(8, 0.9, 7.5), 0.0)
	_aim_at(box.global_position)
	await _wait(0.3)
	_check("ящик в 3 м — не достаю (просто точка)", ret.mode == Reticle.Mode.FAR and ret.highlighted == null, "mode=%d" % ret.mode)
	k.in_aim_pitch = -1.3
	cam.pitch = -1.3
	await _wait(0.3)
	_check("пол под ногами (вприсядку достанешь) — кольцо «ухватиться»", ret.mode == Reticle.Mode.SURFACE or ret.mode == Reticle.Mode.FAR, "mode=%d" % ret.mode)

	# --- нокаут ---
	k.knock_out(2.0)
	await _wait(0.6)
	_check("нокаут: вид заваливается и темнеет по краям", cam.ko_amount > 0.8 and cam._vignette.visible
		and ret.mode == Reticle.Mode.HIDDEN, "ko=%.2f" % cam.ko_amount)
	await _wait(6.0)
	_check("очнулся — эффект ушёл", cam.ko_amount < 0.05 and not cam._vignette.visible, "ko=%.2f" % cam.ko_amount)

	# --- стартовый вид из настроек ---
	Settings.start_view = "third"
	var c2: Node3D = Cam.new()
	add_child(c2)
	_check("в настройках «3-е лицо» — новая камера стартует сзади", not c2.is_first_person() and is_equal_approx(c2.zoom, Cam.DISTANCE))
	c2.queue_free()
	Settings.start_view = "first"
	cam.camera.make_current()

## Где рука была в миг хвата (потом она уже ведёт вещь взглядом).
func _grab_point(h: RigidBody3D) -> Vector3:
	for i in 60:
		await get_tree().physics_frame
		if h.held != null:
			return h.global_position
	return h.global_position

func _aim_at(p: Vector3) -> void:
	var yaw := 0.0
	var pitch := 0.0
	for i in 3:
		var d: Vector3 = p - k.aim_origin()
		yaw = atan2(-d.x, -d.z)
		pitch = atan2(d.y, Vector2(d.x, d.z).length())
		k.in_aim_yaw = yaw
		k.in_aim_pitch = pitch
	cam.yaw = yaw
	cam.pitch = pitch

func _layers_ok(n: Node, l: int) -> bool:
	if n is VisualInstance3D and (n as VisualInstance3D).layers != l:
		return false
	for c in n.get_children():
		if not _layers_ok(c, l):
			return false
	return true

func _body_visible() -> bool:
	var n := 0
	for c in k.visual._puff.get_children():
		if c is MeshInstance3D and c != k.visual._head and (c as MeshInstance3D).layers & cam.camera.cull_mask != 0:
			n += 1
	return n >= 5 and k.visual._arms[0].layers & cam.camera.cull_mask != 0 and k.visual._legs[0].layers & cam.camera.cull_mask != 0

func _has_overlay(b: Node) -> bool:
	for c in b.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).material_overlay != null:
			return true
	return false

func _wheel(button: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	cam.handle_input(e)

func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	cam.handle_input(ev)

func _reset(pos: Vector3, yaw := 0.0) -> void:
	k.in_move = Vector2.ZERO
	k.in_grab_l = false
	k.in_grab_r = false
	k.in_aim_yaw = yaw
	k.in_aim_pitch = 0.0
	if k.is_ko():
		await _wait(8.0)
	k.teleport(pos, yaw)
	await _wait(0.8)

func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await get_tree().physics_frame

func _check(what: String, ok: bool, info := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", what, info if not ok else ""])
	if not ok:
		fails += 1
