extends RefCounted
## Единый стиль «бюро»: палитра, шрифты, тема и общие кирпичики для всех экранов.
## Экраны собираются только из того, что здесь (плашка-жестянка, бумага, стикер,
## сигнальная полоса, клавиша, подсказка «клавиша + действие», кнопки трёх видов).
##
## Шрифты (OFL, лицензии рядом в ui/theme/fonts):
##   HEAD  — Russo One: заголовки, кнопки, таблички (плотный «рабочий»);
##   BODY  — Rubik: обычный текст; BOLD — Rubik SemiBold;
##   HAND  — Caveat: от руки (подписи, заметки на стикерах, ворчание клиента);
##   MONO  — PT Mono: «печатная машинка» (бланки, акт приёмки, планшет).

const KeyCap := preload("res://ui/theme/key_cap.gd")
const Plate := preload("res://ui/theme/plate.gd")
const Stripe := preload("res://ui/theme/hazard_stripe.gd")

# --- Палитра ---------------------------------------------------------------
const NAVY := Color("14233a")        # фон, обводки, «чернила» на жёлтом
const NAVY_DEEP := Color("0c1626")
const PANEL := Color("1f3654")       # плашка-жестянка
const PANEL_HI := Color("2b4a70")    # кнопка, поле
const STEEL := Color("3b5f8a")
const SIGNAL := Color("f2a81d")      # сигнальный жёлто-оранжевый
const SIGNAL_HI := Color("ffc24a")
const SIGNAL_DK := Color("c7820a")
const PAPER := Color("efe6d2")       # бумага, картон
const PAPER_DK := Color("d9cdb2")
const STICKER := Color("ffe27a")     # жёлтый стикер
const INK := Color("2b2a33")         # текст на бумаге
const STAMP := Color("c8372d")       # красный штамп
const OK := Color("5ba35a")          # зелёный «принято»
const TEXT := Color("f4efe4")
const MUTED := Color("9db0c6")

# Старые имена — чтобы код уровней и тестов не ломался.
const BG := NAVY
const ACCENT := SIGNAL
const DANGER := Color("f0997b")

# --- Шрифты ----------------------------------------------------------------
const HEAD: FontFile = preload("res://ui/theme/fonts/RussoOne-Regular.ttf")
const BODY: FontFile = preload("res://ui/theme/fonts/Rubik-Regular.ttf")
const BOLD: FontFile = preload("res://ui/theme/fonts/Rubik-SemiBold.ttf")
const HAND: FontFile = preload("res://ui/theme/fonts/Caveat-SemiBold.ttf")
const MONO: FontFile = preload("res://ui/theme/fonts/PTMono-Regular.ttf")

const LOGO: Texture2D = preload("res://ui/theme/icons/logo.svg")

static var _theme: Theme

## Тема создаётся один раз и делится всеми экранами.
static func make_theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme

static func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = BODY
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)

	# Кнопки: «физическая» кнопка — толстый нижний край, при нажатии проседает.
	_button_type(t, "Button", PANEL_HI, TEXT, SIGNAL, NAVY)
	t.set_type_variation("PrimaryButton", "Button")      # главное действие — сигнальная
	_button_type(t, "PrimaryButton", SIGNAL, NAVY, SIGNAL_HI, NAVY)
	t.set_type_variation("DangerButton", "Button")       # выход, сброс
	_button_type(t, "DangerButton", Color("6b2a2a"), TEXT, STAMP, TEXT)
	t.set_type_variation("FlatButton", "Button")         # тихая ссылка-кнопка
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		var e := StyleBoxEmpty.new()
		e.set_content_margin_all(6)
		t.set_stylebox(s, "FlatButton", e)
	t.set_color("font_color", "FlatButton", MUTED)
	t.set_color("font_hover_color", "FlatButton", SIGNAL)
	t.set_color("font_pressed_color", "FlatButton", SIGNAL_HI)
	t.set_color("font_focus_color", "FlatButton", SIGNAL)

	# Поле ввода — «прорезь» в жестянке.
	var le := _box(NAVY_DEEP, 6, 12)
	le.set_border_width_all(2)
	le.border_color = PANEL_HI
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate()
	lef.border_color = SIGNAL
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED.darkened(0.25))
	t.set_color("caret_color", "LineEdit", SIGNAL)
	t.set_color("selection_color", "LineEdit", SIGNAL.darkened(0.4))

	# Плашки.
	t.set_stylebox("panel", "PanelContainer", plate_box())
	t.set_type_variation("PaperPanel", "PanelContainer")
	t.set_stylebox("panel", "PaperPanel", paper_box())
	t.set_type_variation("StickerPanel", "PanelContainer")
	t.set_stylebox("panel", "StickerPanel", sticker_box())
	t.set_stylebox("panel", "TooltipPanel", sticker_box())
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font("font", "TooltipLabel", HAND)
	t.set_font_size("font_size", "TooltipLabel", 24)

	# Подписи по ролям.
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", HEAD)
	t.set_font_size("font_size", "TitleLabel", 40)
	t.set_color("font_color", "TitleLabel", SIGNAL)
	t.set_type_variation("HeadLabel", "Label")
	t.set_font("font", "HeadLabel", HEAD)
	t.set_font_size("font_size", "HeadLabel", 24)
	t.set_type_variation("MutedLabel", "Label")
	t.set_font_size("font_size", "MutedLabel", 18)
	t.set_color("font_color", "MutedLabel", MUTED)
	t.set_type_variation("InkLabel", "Label")           # на бумаге
	t.set_font("font", "InkLabel", MONO)
	t.set_color("font_color", "InkLabel", INK)
	t.set_type_variation("HandLabel", "Label")          # от руки
	t.set_font("font", "HandLabel", HAND)
	t.set_font_size("font_size", "HandLabel", 28)
	t.set_color("font_color", "HandLabel", INK)

	# Галочка/переключатель, ползунок, выпадающий список, вкладки — для настроек.
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var e := StyleBoxEmpty.new()
		e.set_content_margin_all(4)
		t.set_stylebox(s, "CheckBox", e)
		t.set_stylebox(s, "CheckButton", e)
	for type in ["CheckBox", "CheckButton"]:
		for c in ["font_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(c, type, TEXT)
		t.set_color("font_hover_color", type, SIGNAL_HI)
		t.set_color("font_hover_pressed_color", type, SIGNAL_HI)
		t.set_constant("h_separation", type, 12)
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false))

	var track := _box(NAVY_DEEP, 4, 0)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	var fill := _box(SIGNAL, 4, 0)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _knob_icon(TEXT))
	t.set_icon("grabber_highlight", "HSlider", _knob_icon(SIGNAL_HI))

	t.set_icon("arrow", "OptionButton", _arrow_icon())
	var pm := _box(NAVY_DEEP, 6, 8)
	pm.set_border_width_all(2)
	pm.border_color = SIGNAL
	t.set_stylebox("panel", "PopupMenu", pm)
	var pmh := _box(SIGNAL, 4, 6)
	t.set_stylebox("hover", "PopupMenu", pmh)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", NAVY)
	t.set_font_size("font_size", "PopupMenu", 20)

	var tab_sel := _box(PANEL, 0, 12)
	tab_sel.corner_radius_top_left = 8
	tab_sel.corner_radius_top_right = 8
	tab_sel.border_width_top = 4
	tab_sel.border_color = SIGNAL
	var tab_un := tab_sel.duplicate()
	tab_un.bg_color = NAVY_DEEP
	tab_un.border_color = PANEL_HI
	var tab_hov := tab_un.duplicate()
	tab_hov.bg_color = PANEL_HI
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, tab_sel)
		t.set_stylebox("tab_unselected", type, tab_un)
		t.set_stylebox("tab_hovered", type, tab_hov)
		t.set_stylebox("tab_focus", type, StyleBoxEmpty.new())
		t.set_font("font", type, HEAD)
		t.set_font_size("font_size", type, 20)
		t.set_color("font_selected_color", type, SIGNAL)
		t.set_color("font_unselected_color", type, MUTED)
		t.set_color("font_hovered_color", type, TEXT)
	t.set_stylebox("panel", "TabContainer", plate_box())

	var sc := _box(NAVY_DEEP, 4, 0)
	sc.content_margin_left = 5
	sc.content_margin_right = 5
	t.set_stylebox("scroll", "VScrollBar", sc)
	for s in ["grabber", "grabber_highlight", "grabber_pressed"]:
		t.set_stylebox(s, "VScrollBar", _box(SIGNAL if s != "grabber" else STEEL, 4, 0))

	# Гнездо под клавишу в настройках управления: тёмная прорезь, при наведении — сигнальный кант,
	# «Conflict» — красный кант (клавиша занята другим действием), «Waiting» — ждём нажатия.
	t.set_type_variation("SlotButton", "Button")
	var slot := _box(NAVY_DEEP, 6, 6)
	slot.set_border_width_all(2)
	slot.border_color = PANEL_HI
	var slot_h := slot.duplicate()
	slot_h.border_color = SIGNAL
	var slot_p := slot_h.duplicate()
	slot_p.bg_color = PANEL
	for st in [["normal", slot], ["hover", slot_h], ["pressed", slot_p], ["hover_pressed", slot_p],
			["focus", slot_h], ["disabled", slot]]:
		t.set_stylebox(st[0], "SlotButton", st[1])
	t.set_font("font", "SlotButton", HEAD)
	t.set_font_size("font_size", "SlotButton", 18)
	t.set_color("font_color", "SlotButton", MUTED)
	t.set_color("font_hover_color", "SlotButton", SIGNAL_HI)
	t.set_type_variation("SlotConflict", "SlotButton")
	var slot_c := slot.duplicate()
	slot_c.border_color = STAMP
	slot_c.set_border_width_all(3)
	slot_c.bg_color = Color("3a1a1f")
	var slot_ch := slot_c.duplicate()
	slot_ch.border_color = Color("ff6a5c")
	for st in [["normal", slot_c], ["hover", slot_ch], ["pressed", slot_ch], ["hover_pressed", slot_ch], ["focus", slot_ch]]:
		t.set_stylebox(st[0], "SlotConflict", st[1])
	t.set_type_variation("SlotWaiting", "SlotButton")
	var slot_w := _box(SIGNAL, 6, 6)
	slot_w.set_border_width_all(2)
	slot_w.border_color = SIGNAL_HI
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(st, "SlotWaiting", slot_w)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "SlotWaiting", NAVY)

	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	return t

static func _button_type(t: Theme, type: String, base: Color, fg: Color, hover: Color, hover_fg: Color) -> void:
	var normal := _box(base, 8, 14)
	normal.border_width_bottom = 5
	normal.border_color = base.darkened(0.45)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	var hov := normal.duplicate()
	hov.bg_color = hover
	hov.border_color = hover.darkened(0.45)
	var pressed := normal.duplicate()
	pressed.bg_color = hover.darkened(0.15)
	pressed.border_width_bottom = 1
	pressed.border_width_top = 4
	pressed.border_color = hover.darkened(0.55)
	var disabled := normal.duplicate()
	disabled.bg_color = base.darkened(0.35).lerp(PANEL, 0.5)
	disabled.border_color = disabled.bg_color.darkened(0.3)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(10)
	focus.set_border_width_all(3)
	focus.border_color = SIGNAL_HI
	focus.set_expand_margin_all(3)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hov)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, focus)
	t.set_font("font", type, HEAD)
	t.set_font_size("font_size", type, 22)
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, hover_fg)
	t.set_color("font_pressed_color", type, hover_fg)
	t.set_color("font_hover_pressed_color", type, hover_fg)
	t.set_color("font_focus_color", type, fg)
	t.set_color("font_disabled_color", type, MUTED.darkened(0.3))

static func _box(c: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb

## Жестянка: тёмно-синяя плашка со светлым кантом и тенью.
static func plate_box() -> StyleBoxFlat:
	var sb := _box(PANEL, 8, 22)
	sb.set_border_width_all(3)
	sb.border_color = STEEL
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	return sb

## Бумага: светлый лист с мягкой тенью и почти прямыми углами.
static func paper_box() -> StyleBoxFlat:
	var sb := _box(PAPER, 2, 28)
	sb.border_width_bottom = 3
	sb.border_color = PAPER_DK
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(4, 8)
	return sb

## Стикер: жёлтый квадратик «от руки».
static func sticker_box() -> StyleBoxFlat:
	var sb := _box(STICKER, 1, 14)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(3, 5)
	return sb

# --- Маленькие нарисованные иконки (без файлов, масштабируются ровно) ----------

static func _img(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)

static func _fill_rrect(img: Image, r: Rect2, rad: float, c: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var p := Vector2(x + 0.5, y + 0.5)
			var q := (p - r.get_center()).abs() - r.size / 2.0 + Vector2(rad, rad)
			var d := Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0.0) - rad
			var a := clampf(0.5 - d, 0.0, 1.0)
			if a > 0.0:
				var old := img.get_pixel(x, y)
				img.set_pixel(x, y, old.blend(Color(c, c.a * a)))

static func _check_icon(on: bool) -> Texture2D:
	var img := _img(30, 30)
	_fill_rrect(img, Rect2(1, 1, 28, 28), 6, NAVY_DEEP)
	_fill_rrect(img, Rect2(3, 3, 24, 24), 5, SIGNAL if on else PANEL_HI)
	if on:   # галочка
		for i in 14:
			var t := i / 13.0
			var p := Vector2(8, 15).lerp(Vector2(13, 20), t) if t < 0.5 else Vector2(13, 20).lerp(Vector2(22, 9), (t - 0.5) * 2.0)
			_fill_rrect(img, Rect2(p - Vector2(2, 2), Vector2(4, 4)), 2, NAVY)
	return ImageTexture.create_from_image(img)

static func _switch_icon(on: bool) -> Texture2D:
	var img := _img(52, 28)
	_fill_rrect(img, Rect2(1, 2, 50, 24), 12, SIGNAL if on else NAVY_DEEP)
	_fill_rrect(img, Rect2(31 if on else 3, 4, 20, 20), 10, NAVY if on else MUTED)
	return ImageTexture.create_from_image(img)

static func _knob_icon(c: Color) -> Texture2D:
	var img := _img(26, 26)
	_fill_rrect(img, Rect2(1, 1, 24, 24), 12, NAVY)
	_fill_rrect(img, Rect2(4, 4, 18, 18), 9, c)
	return ImageTexture.create_from_image(img)

static func _arrow_icon() -> Texture2D:
	var img := _img(18, 12)
	for y in 10:
		for x in range(y, 17 - y):
			img.set_pixel(x, y + 1, SIGNAL)
	return ImageTexture.create_from_image(img)

# --- Кирпичики экранов -------------------------------------------------------

## Фон экрана: тёмно-синий с едва заметной «сеткой чертежа».
static func background() -> Control:
	var bg := ColorRect.new()
	bg.color = NAVY
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(func():
		var s := bg.size
		var step := 48.0
		var line := Color(STEEL, 0.10)
		var x := 0.0
		while x < s.x:
			bg.draw_line(Vector2(x, 0), Vector2(x, s.y), line, 1.0)
			x += step
		var y := 0.0
		while y < s.y:
			bg.draw_line(Vector2(0, y), Vector2(s.x, y), line, 1.0)
			y += step)
	bg.resized.connect(bg.queue_redraw)
	return bg

static func label(text: String, size := 22, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## Заголовок шрифтом табличек.
static func title(text: String, size := 40, color := SIGNAL) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", HEAD)
	return l

## Надпись «от руки» (стикеры, подписи, заметки).
static func hand(text: String, size := 28, color := INK) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", HAND)
	return l

## «Печатный» текст для бланков и планшета.
static func typed(text: String, size := 20, color := INK) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", MONO)
	return l

## Обводка, чтобы текст читался прямо поверх мира.
static func outlined(l: Label, width := 8) -> Label:
	l.add_theme_color_override("font_outline_color", NAVY_DEEP)
	l.add_theme_constant_override("outline_size", width)
	return l

## Кнопка. kind: "" | "primary" | "danger" | "flat".
static func button(text: String, action: Callable = Callable(), kind := "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = {"": "", "primary": "PrimaryButton", "danger": "DangerButton", "flat": "FlatButton"}[kind]
	if action.is_valid():
		b.pressed.connect(action)
	return b

## Плашка-жестянка с заклёпками (и, по желанию, сигнальной полосой сверху).
static func plate(stripe := false) -> PanelContainer:
	var p: PanelContainer = Plate.new()
	p.stripe = stripe
	return p

static func paper() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "PaperPanel"
	return p

## Стикер, чуть повёрнутый — как приклеенный рукой. width > 0 — переносить строки по этой ширине.
## Контейнеры сбрасывают поворот у прямых детей, поэтому стикер сидит в обёртке.
static func sticker(text: String, tilt_deg := -2.0, width := 0.0, size := 26) -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = "StickerPanel"
	var l := hand(text, size)
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width, 0)
	p.add_child(l)
	p.rotation_degrees = tilt_deg
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(p)
	var fit := func():
		wrap.custom_minimum_size = p.get_combined_minimum_size()
		p.size = wrap.size
		p.pivot_offset = p.size / 2.0
	p.minimum_size_changed.connect(fit)
	wrap.resized.connect(fit)
	fit.call_deferred()
	return wrap

## Жёлто-чёрная сигнальная полоса.
static func stripe(height := 14.0) -> Control:
	var s: Control = Stripe.new()
	s.custom_minimum_size = Vector2(0, height)
	return s

## Клавиша действия из текущей раскладки (подписывается сама, следит за переназначением).
static func key(action: String, size := 34.0) -> Control:
	var k: Control = KeyCap.new()
	k.action = action
	k.cap_height = size
	return k

## Клавиша по событию ввода (для гнёзд в настройках управления).
static func key_event(e: InputEvent, size := 34.0) -> Control:
	var k: Control = KeyCap.new()
	k.event = e
	k.cap_height = size
	return k

## Клавиша с произвольной подписью («Esc», «Tab»…).
static func key_text(text: String, size := 34.0) -> Control:
	var k: Control = KeyCap.new()
	k.text = text
	k.cap_height = size
	return k

## Подсказка «[клавиша] действие».
static func key_hint(action: String, what: String, size := 20) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := key(action, size + 12.0)
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(k)
	var l := outlined(label(what, size), 6)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row

## Эмблема бюро.
static func logo(px := 96.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = LOGO
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
