extends Node
## Пользовательские настройки. Хранятся в user://settings.cfg.
##   [player] имя; [net] последний IP, порт;
##   [controls] переназначенные клавиши (их применяет Controls), чувствительность, инверсия, подсказки;
##   [graphics] пресет и отдельные опции; [audio] громкость шин.
## Окно настроек (ui/settings_menu.gd) меняет поля и зовёт apply_*() и save().
## Кто зависит от настроек (камера, подсказки), слушает сигнал changed.

signal changed   # что-то поменялось — перечитать нужное

const PATH := "user://settings.cfg"

var player_name := "Ремонтник"
var last_address := ""
var port := 27015

# --- Управление ---
var bindings := {}            ## действие -> ["key:87", "mouse:1", ""] (только переназначенные)
var mouse_sens := 1.0         ## множитель к базовой чувствительности камеры
var invert_y := false
var show_hints := true

# --- Графика ---
const PRESETS := ["low", "medium", "high"]
const PRESET_NAMES := {"low": "Низко", "medium": "Средне", "high": "Высоко", "custom": "Своё"}
const PRESET_VALUES := {
	"low":    {"shadows": 0, "aa": 0, "render_scale": 0.75},
	"medium": {"shadows": 1, "aa": 1, "render_scale": 1.0},
	"high":   {"shadows": 2, "aa": 3, "render_scale": 1.0},
}
const SHADOW_NAMES := ["Выкл", "Обычные", "Чёткие"]
const AA_NAMES := ["Выкл", "FXAA (дёшево)", "MSAA 2×", "MSAA 4×"]
const FPS_LIMITS := [30, 60, 120, 144, 0]   ## 0 — без ограничения

var preset := "medium"        ## low / medium / high / custom
var shadows := 1              ## 0 выкл, 1 обычные, 2 чёткие
var aa := 1                   ## индекс AA_NAMES
var render_scale := 1.0       ## 0.5 … 1.0
var fps_limit := 0            ## кадров в секунду (одно из FPS_LIMITS), 0 — без ограничения
var vsync := true
var fullscreen := false
var fov := 62.0

# --- Звук (0…1) ---
const BUSES := ["Master", "SFX", "Music", "UI"]
var volume := {"Master": 0.8, "SFX": 1.0, "Music": 0.7, "UI": 0.8}

const DEFAULT_CONTROLS := {"mouse_sens": 1.0, "invert_y": false, "show_hints": true}
const DEFAULT_GRAPHICS := {"preset": "medium", "fps_limit": 0, "vsync": true, "fullscreen": false, "fov": 62.0}
const DEFAULT_VOLUME := {"Master": 0.8, "SFX": 1.0, "Music": 0.7, "UI": 0.8}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_file()
	get_tree().node_added.connect(_on_node_added)
	apply_graphics()
	apply_window()
	apply_audio()

func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	player_name = str(cfg.get_value("player", "name", player_name))
	last_address = str(cfg.get_value("net", "last_address", last_address))
	port = int(cfg.get_value("net", "port", port))
	var b = cfg.get_value("controls", "bindings", {})
	bindings = b if b is Dictionary else {}
	mouse_sens = clampf(float(cfg.get_value("controls", "mouse_sens", mouse_sens)), 0.2, 3.0)
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	show_hints = bool(cfg.get_value("controls", "show_hints", show_hints))
	preset = str(cfg.get_value("graphics", "preset", preset))
	if not PRESET_NAMES.has(preset):
		preset = "medium"
	shadows = clampi(int(cfg.get_value("graphics", "shadows", shadows)), 0, 2)
	aa = clampi(int(cfg.get_value("graphics", "aa", aa)), 0, AA_NAMES.size() - 1)
	render_scale = clampf(float(cfg.get_value("graphics", "render_scale", render_scale)), 0.5, 1.0)
	fps_limit = int(cfg.get_value("graphics", "fps_limit", fps_limit))
	if not FPS_LIMITS.has(fps_limit):
		fps_limit = 0
	vsync = bool(cfg.get_value("graphics", "vsync", vsync))
	fullscreen = bool(cfg.get_value("graphics", "fullscreen", fullscreen))
	fov = clampf(float(cfg.get_value("graphics", "fov", fov)), 50.0, 90.0)
	for bus in BUSES:
		volume[bus] = clampf(float(cfg.get_value("audio", bus, volume[bus])), 0.0, 1.0)
	if preset != "custom":
		set_preset(preset)

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("net", "last_address", last_address)
	cfg.set_value("net", "port", port)
	cfg.set_value("controls", "bindings", bindings)
	cfg.set_value("controls", "mouse_sens", mouse_sens)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "show_hints", show_hints)
	cfg.set_value("graphics", "preset", preset)
	cfg.set_value("graphics", "shadows", shadows)
	cfg.set_value("graphics", "aa", aa)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "fps_limit", fps_limit)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "fov", fov)
	for bus in BUSES:
		cfg.set_value("audio", bus, volume[bus])
	cfg.save(PATH)

## Сообщить всем, что настройки поменялись (камера, подсказки и т.п.).
func notify() -> void:
	changed.emit()

# --- Сбросы по вкладкам ---

func reset_controls() -> void:
	bindings = {}
	mouse_sens = DEFAULT_CONTROLS.mouse_sens
	invert_y = DEFAULT_CONTROLS.invert_y
	show_hints = DEFAULT_CONTROLS.show_hints

func reset_graphics() -> void:
	set_preset(DEFAULT_GRAPHICS.preset)
	fps_limit = DEFAULT_GRAPHICS.fps_limit
	vsync = DEFAULT_GRAPHICS.vsync
	fullscreen = DEFAULT_GRAPHICS.fullscreen
	fov = DEFAULT_GRAPHICS.fov

func reset_audio() -> void:
	volume = DEFAULT_VOLUME.duplicate()

# --- Графика ---

## Пресет задаёт тени, сглаживание и масштаб рендера; остальное (FPS, V-Sync, окно, FOV) — отдельно.
func set_preset(p: String) -> void:
	preset = p
	if PRESET_VALUES.has(p):
		var v: Dictionary = PRESET_VALUES[p]
		shadows = v.shadows
		aa = v.aa
		render_scale = v.render_scale

## Если отдельные опции совпали с каким-то пресетом — показать его, иначе «Своё».
func detect_preset() -> void:
	for p in PRESETS:
		var v: Dictionary = PRESET_VALUES[p]
		if shadows == v.shadows and aa == v.aa and is_equal_approx(render_scale, v.render_scale):
			preset = p
			return
	preset = "custom"

func _compat() -> bool:
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "gl_compatibility" \
		or RenderingServer.get_current_rendering_method() == "gl_compatibility"

func apply_graphics() -> void:
	var vp := get_tree().root
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][aa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_scale = render_scale
	if render_scale < 0.999 and not _compat():
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR   # FSR 1 — чётче простого растягивания
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	# Тени: размер карт и мягкость; 0 — свет без теней вовсе.
	var dir_size: int = [1024, 2048, 4096][shadows]
	RenderingServer.directional_shadow_atlas_set_size(dir_size, true)
	vp.positional_shadow_atlas_size = [1024, 2048, 4096][shadows]
	var q: int = [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][shadows]
	RenderingServer.directional_soft_shadow_filter_set_quality(q)
	RenderingServer.positional_soft_shadow_filter_set_quality(q)
	_apply_shadows(get_tree().root)
	Engine.max_fps = fps_limit
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() == want:
		return
	if not fullscreen and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
		return
	DisplayServer.window_set_mode(want)

## Каждый новый источник света подчиняется настройке теней (уровни ставят shadow_enabled сами,
## поэтому запоминаем их желание и применяем после того, как они достроились).
func _on_node_added(n: Node) -> void:
	if n is Light3D:
		_apply_light.call_deferred(n)

func _apply_shadows(root: Node) -> void:
	for n in root.find_children("*", "Light3D", true, false):
		_apply_light(n)

func _apply_light(l: Light3D) -> void:
	if not is_instance_valid(l):
		return
	if not l.has_meta("wants_shadow"):
		l.set_meta("wants_shadow", l.shadow_enabled)
	l.shadow_enabled = bool(l.get_meta("wants_shadow")) and shadows > 0

# --- Звук ---

func apply_audio() -> void:
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var v: float = volume[bus]
		AudioServer.set_bus_mute(i, v <= 0.001)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))
