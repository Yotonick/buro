extends Node3D
## Рыбы за стеклом купола — только картинка, физики и сети нет.
## Каждая плывёт по своему кругу; у всех одинаково, потому что движение зависит
## только от времени с начала смены.

const FISH := [
	["res://assets/fish/Fish1.fbx", 0.35, 6],
	["res://assets/fish/Fish2.fbx", 0.5, 6],
	["res://assets/fish/Fish3.fbx", 0.55, 8],
	["res://assets/fish/Manta.fbx", 0.22, 1],
	["res://assets/fish/Shark.fbx", 0.3, 1],
]

var dome_radius := 10.0
var _swimmers: Array = []      ## [узел, радиус, высота, скорость, фаза, качание]
var _t := 0.0

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for f in FISH:
		var scene: PackedScene = load(f[0])
		for i in int(f[2]):
			var n: Node3D = scene.instantiate()
			n.scale = Vector3.ONE * float(f[1]) * rng.randf_range(0.85, 1.2)
			add_child(n)
			var big := int(f[2]) == 1
			var r := rng.randf_range(dome_radius + 6.0, dome_radius + 11.0) if big else rng.randf_range(dome_radius + 1.2, dome_radius + 4.5)
			var h := rng.randf_range(0.8, 5.5) if not big else rng.randf_range(4.0, 9.0)
			var sp := rng.randf_range(0.6, 1.4) / r * (1.0 if rng.randf() < 0.6 else -1.0)
			if big:
				sp *= 0.6
			_swimmers.append([n, r, h, sp, rng.randf() * TAU, rng.randf_range(0.2, 0.8)])
			for ap in n.find_children("*", "AnimationPlayer", true, false):
				var list: PackedStringArray = ap.get_animation_list()
				if list.size() > 0:
					var anim: Animation = ap.get_animation(list[0])
					anim.loop_mode = Animation.LOOP_LINEAR
					ap.play(list[0])
					ap.speed_scale = rng.randf_range(0.8, 1.3)
					ap.seek(rng.randf() * anim.length, true)
	_place(0.0)

func _process(dt: float) -> void:
	_t += dt
	_place(_t)

func _place(t: float) -> void:
	for s in _swimmers:
		var n: Node3D = s[0]
		var r: float = s[1]
		var sp: float = s[3]
		var a: float = s[4] + t * sp
		var y: float = s[2] + sin(t * 0.4 + s[4]) * s[5]
		n.position = Vector3(cos(a) * r, y, sin(a) * r)
		# смотрит по ходу движения (модели смотрят вдоль +Z)
		var dir := Vector3(-sin(a), 0, cos(a)) * signf(sp)
		n.rotation = Vector3(0, atan2(dir.x, dir.z), 0)
