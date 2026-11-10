extends RefCounted
## Общий вид интерфейса: цвета и тема. Один источник для всех экранов.

const BG := Color("12202e")
const PANEL := Color("1b3147")
const ACCENT := Color("ef9f27")
const TEXT := Color("f1efe8")
const MUTED := Color("9fb3c8")
const DANGER := Color("f0997b")

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(14)
		sb.bg_color = {"normal": PANEL, "hover": PANEL.lightened(0.12), "pressed": ACCENT.darkened(0.25),
			"disabled": PANEL.darkened(0.3), "focus": Color(0, 0, 0, 0)}[state]
		if state == "focus":
			sb.draw_center = false
			sb.set_border_width_all(2)
			sb.border_color = ACCENT
		t.set_stylebox(state, "Button", sb)
	var le := StyleBoxFlat.new()
	le.bg_color = BG.darkened(0.3)
	le.set_corner_radius_all(8)
	le.set_content_margin_all(12)
	le.set_border_width_all(1)
	le.border_color = PANEL.lightened(0.2)
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate()
	lef.border_color = ACCENT
	t.set_stylebox("focus", "LineEdit", lef)
	return t

static func background() -> ColorRect:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	return bg

static func label(text: String, size := 22, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
