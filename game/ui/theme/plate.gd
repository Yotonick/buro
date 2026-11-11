extends PanelContainer
## Плашка-жестянка: панель темы + заклёпки по углам и (по желанию) сигнальная полоса сверху.

const RIVET := Color("8fa3bd")
const RIVET_DK := Color("0c1626")
const SIGNAL := Color("f2a81d")
const NAVY := Color("14233a")

var stripe := false:
	set(v):
		stripe = v
		queue_redraw()

func _ready() -> void:
	if stripe:
		var sb: StyleBoxFlat = get_theme_stylebox("panel").duplicate()
		sb.content_margin_top += 14
		add_theme_stylebox_override("panel", sb)

func _draw() -> void:
	var s := size
	if stripe:
		var h := 12.0
		var x := -h
		draw_rect(Rect2(6, 5, s.x - 12, h), NAVY)
		while x < s.x:
			var p := PackedVector2Array([Vector2(x, 5 + h), Vector2(x + h, 5), Vector2(x + h * 2, 5), Vector2(x + h, 5 + h)])
			for i in p.size():
				p[i].x = clampf(p[i].x, 6, s.x - 6)
			draw_colored_polygon(p, SIGNAL)
			x += h * 2
	for c in [Vector2(11, 11 + (14 if stripe else 0)), Vector2(s.x - 11, 11 + (14 if stripe else 0)),
			Vector2(11, s.y - 11), Vector2(s.x - 11, s.y - 11)]:
		draw_circle(c + Vector2(0, 1), 4.0, RIVET_DK)
		draw_circle(c, 3.5, RIVET)
		draw_circle(c - Vector2(1, 1), 1.2, Color(1, 1, 1, 0.6))
