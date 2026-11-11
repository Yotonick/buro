extends Node
## Автотест щитка «Глубокой тарелки» (без экрана):
##   godot --headless --path game --fixed-fps 60 --disable-render-loop res://tests/switchboard_test.tscn

const Board := preload("res://levels/deep_plate/switchboard.gd")

var lvl: Node3D
var k: Kombez
var b: Node3D
var fails := 0

func _ready() -> void:
	lvl = load("res://levels/deep_plate/deep_plate.tscn").instantiate()
	add_child(lvl)
	lvl.controller.kombez = null
	k = lvl.player
	lvl._next_leak = 99999.0
	b = lvl.board
	b._next_surge = 99999.0
	await _wait(0.5)
	await _run()
	print("RESULT ", "PASS" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit(fails)

func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await get_tree().physics_frame

func _check(name: String, ok: bool, info := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", name, info])
	if not ok:
		fails += 1

func _tape(a: Node3D, pa: Vector3, c: Node3D, pc: Vector3) -> Node:
	var w: Node = lvl.world
	var ia: int = 0 if a == null else w.id_of(a)
	var ic: int = 0 if c == null else w.id_of(c)
	var la := pa if a == null else a.global_transform.affine_inverse() * pa
	var lc := pc if c == null else c.global_transform.affine_inverse() * pc
	return w.spawn("tape", {"a": ia, "la": la, "na": Vector3.UP, "b": ic, "lb": lc, "nb": Vector3.UP, "rest": pa.distance_to(pc)})

## Повернуть рубильник «рукой бога»: w рад/с вокруг оси (плюс — вниз, в «выкл»).
func _push_lever(w: float, sec: float) -> void:
	for i in int(sec * 60.0):
		b.lever.angular_velocity = b.panel.angular_velocity + b.panel.global_basis.x * w
		await get_tree().physics_frame

func _slot_at(i: int) -> Vector3:
	return b.panel.global_transform * (Board.SLOTS[i] as Vector3)

func _run() -> void:
	var lamp: OmniLight3D = lvl.table_lamps[0]
	_check("щиток на месте: 3 пробки в гнёздах, рубильник вкл, свет 3/3",
		b.fuse_in == [true, true, true] and b.lever_on and b.lit_sectors() == 3, "%s %s" % [str(b.fuse_in), b.lever_on])
	await _wait(2.0)
	_check("целый рубильник сам не падает", b.lever_on and b.lever_angle() < 0.2, "угол %.2f" % b.lever_angle())
	_check("щиток стоит на тумбе низко", b.contacts_y() < 0.5 and b.contacts_y() > 0.3, "розетки на %.2f м" % b.contacts_y())
	await get_tree().process_frame
	_check("лампы горят", lamp.light_energy > 0.1)

	# скачок: пробка вылетает, рубильник падает
	b.warn_sector = 0
	b.surge()
	await _wait(1.5)
	var f0: RigidBody3D = b.fuses[0]
	_check("скачок: пробка сектора вылетела из щитка", not b.fuse_in[0] and f0.global_position.distance_to(_slot_at(0)) > 0.3,
		"в %.2f м от гнезда" % f0.global_position.distance_to(_slot_at(0)))
	_check("скачок: рубильник упал, света нет", not b.lever_on and b.lit_sectors() == 0, "угол %.2f" % b.lever_angle())
	await get_tree().process_frame
	_check("лампы погасли", lamp.light_energy < 0.01 and (lvl.center_light as OmniLight3D).light_energy < 0.01)

	# подняли — сломанный сам падает обратно
	await _push_lever(-15.0, 0.4)
	_check("подняли рубильник — вкл", b.lever_on, "угол %.2f" % b.lever_angle())
	await _wait(2.0)
	_check("сломанная защёлка: отпустили — упал", not b.lever_on, "угол %.2f" % b.lever_angle())

	# подняли и примотали лентой к щитку — держится
	await _push_lever(-15.0, 0.4)
	var tip: Vector3 = b.lever.global_transform * Vector3(0, 0.24, 0)
	var t := _tape(b.lever, tip, b.panel, b.panel.global_transform * Vector3(0.27, 0.36, 0.15))
	await _wait(3.0)
	_check("примотанный рубильник держится", b.lever_on and is_instance_valid(t), "угол %.2f" % b.lever_angle())
	_check("свет 2/3 — сектор без пробки тёмный", b.lit_sectors() == 2)
	await get_tree().process_frame
	_check("лампа сектора без пробки не горит, соседняя горит",
		lamp.light_energy < 0.01 and (lvl.table_lamps[2] as OmniLight3D).light_energy > 0.1)

	# вставили пробку обратно (поднесли к гнезду)
	f0.global_position = _slot_at(0) + b.panel.global_basis.z * 0.05
	f0.linear_velocity = Vector3.ZERO
	await _wait(0.2)
	_check("поднесли пробку к гнезду — встала, свет 3/3", b.fuse_in[0] and b.lit_sectors() == 3)

	# мокрая пробка бьёт током
	b.warn_sector = 1
	b.surge()
	await _wait(1.2)
	var f1: RigidBody3D = b.fuses[1]
	lvl.flood.level = 0.2
	f1.global_position = b.panel.global_position + b.panel.global_basis.z * 1.0 + Vector3(0, -0.6, 0)
	f1.global_position.y = 0.1
	await _wait(0.5)
	lvl.flood.level = 0.0
	await _wait(0.3)
	k.teleport(_slot_at(1) + b.panel.global_basis.z * 0.9 + Vector3.DOWN * 0.3)
	await _wait(0.6)
	f1.global_position = _slot_at(1) + b.panel.global_basis.z * 0.05
	f1.linear_velocity = Vector3.ZERO
	await _wait(0.3)
	_check("мокрая пробка не встаёт и бьёт током того, кто рядом", not b.fuse_in[1] and k.is_ko(), "вставлена %s, нокаут %s" % [b.fuse_in[1], k.is_ko()])
	await _wait(Board.WET_TIME)
	f1.global_position = _slot_at(1) + b.panel.global_basis.z * 0.05
	f1.linear_velocity = Vector3.ZERO
	await _wait(0.3)
	_check("высохла — встаёт", b.fuse_in[1])

	# вода до розеток — короткое
	k.teleport(b.panel.global_position + b.panel.global_basis.z * 2.5 + Vector3.UP * 0.3)
	await _wait(2.5)
	lvl.flood.level = b.contacts_y() + 0.03
	await _wait(0.3)
	_check("вода до розеток — короткое, все пробки вылетели, темно", b.short and b.fuse_in == [false, false, false] and b.lit_sectors() == 0, str(b.fuse_in))
	var kos := 0
	for i in 8:
		await _wait(0.5)
		if k.is_ko():
			kos += 1
	_check("при коротком стоящего в воде бьёт током", kos >= 1, "нокаутов в замерах %d" % kos)
	var dry_f: RigidBody3D = b.fuses[2]
	dry_f.global_position = _slot_at(2) + b.panel.global_basis.z * 0.05
	await _wait(0.2)
	_check("при коротком пробка не вставляется", not b.fuse_in[2])

	# повесили щиток на крюк — короткое ушло
	lvl.flood.level = 0.45
	var e_off: Vector3 = b.panel.global_position - b.eye_point()
	b.panel.global_transform = Transform3D(b.panel.global_basis, b.hook_point + e_off + Vector3(0, 0.05, 0))
	b.panel.linear_velocity = Vector3.ZERO
	b.panel.angular_velocity = Vector3.ZERO
	await _wait(3.0)
	_check("щиток висит на крюке", b.hooked and b.eye_point().distance_to(b.hook_point) < 0.15, "до крюка %.2f" % b.eye_point().distance_to(b.hook_point))
	_check("на крюке розетки выше воды — короткого нет", not b.short and b.contacts_y() > 0.45, "розетки %.2f" % b.contacts_y())
	lvl.flood.level = 0.0

	# кабель не даёт унести далеко
	b.panel.global_position = b.anchor + Vector3(0, -1.5, 0) + b.panel.global_basis.z * 0.0 + (b.panel.global_basis.z) * 3.5
	b.panel.linear_velocity = Vector3.ZERO
	await _wait(2.0)
	var at: Vector3 = b.panel.global_transform * Board.CABLE_AT
	_check("кабель тянет щиток обратно", at.distance_to(b.anchor) < Board.CABLE_LEN + 0.25, "%.2f м" % at.distance_to(b.anchor))

	# снять с крюка, приподняв
	b.panel.global_transform = Transform3D(b.global_basis, b.hook_point - b.global_basis * Board.EYE)
	b.panel.linear_velocity = Vector3.ZERO
	b.panel.angular_velocity = Vector3.ZERO
	await _wait(1.0)
	var was: bool = b.hooked
	for i in 30:
		b.panel.linear_velocity = Vector3.UP * 1.2 + b.global_basis.z * 1.2
		b.panel.angular_velocity = Vector3.ZERO
		await get_tree().physics_frame
	await _wait(1.5)
	_check("приподняли и отвели — снялся с крюка и упал", was and not b.hooked and b.eye_point().y < Board.HOOK_Y - 0.3, "висел %s, висит %s, ушко на %.2f" % [was, b.hooked, b.eye_point().y])

	# живой Комбез хватает щиток двумя руками и тянет вверх
	await _wait(1.0)
	var home := Transform3D(b.global_basis, b.global_position + b.global_basis.z * 1.0 + Vector3.UP * (Board.STAND_H + Board.PANEL_SIZE.y * 0.5 + 0.01))
	b.panel.global_transform = home
	b.panel.linear_velocity = Vector3.ZERO
	b.panel.angular_velocity = Vector3.ZERO
	await _wait(1.0)
	var y0: float = b.panel.global_position.y
	var fwd: Vector3 = b.global_basis.z
	k.in_grab_l = false
	k.in_grab_r = false
	await _wait(6.0)
	k.teleport(b.panel.global_position + fwd * 0.75 + Vector3(0, 0.2, 0), atan2(fwd.x, fwd.z))
	k.in_aim_yaw = atan2(fwd.x, fwd.z)
	await _wait(1.0)
	k.in_aim_pitch = -0.35
	k.in_grab_l = true
	k.in_grab_r = true
	await _wait(1.0)
	var got: bool = k.hand_l.held == b.panel and k.hand_r.held == b.panel
	k.in_aim_pitch = 0.7
	var top := 0.0
	for i in 120:
		await get_tree().physics_frame
		top = maxf(top, b.panel.global_position.y - y0)
	print("INFO  один Комбез: схватил %s, поднял щиток на %.2f м, усилие %.2f" % [got, top, k.effort()])
	_check("один Комбез может схватить щиток двумя руками", got)
	k.in_grab_l = false
	k.in_grab_r = false
