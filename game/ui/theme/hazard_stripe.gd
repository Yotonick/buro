extends Control
## Жёлто-чёрная сигнальная полоса (как на ограждении).

const SIGNAL := Color("f2a81d")
const NAVY := Color("14233a")

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), NAVY)
	var x := -h
	while x < size.x:
		var p := PackedVector2Array([Vector2(x, h), Vector2(x + h, 0), Vector2(x + h * 2, 0), Vector2(x + h, h)])
		for i in p.size():
			p[i].x = clampf(p[i].x, 0, size.x)
		draw_colored_polygon(p, SIGNAL)
		x += h * 2
