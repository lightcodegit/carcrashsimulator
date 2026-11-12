class_name UiTheme
extends RefCounted
# Единый дизайн-язык меню и настроек — как в BeamNG.drive: тёмные полупрозрачные
# панели, янтарный акцент, гуманистический гротеск с настоящими начертаниями для
# заголовков и моноширинный для цифр. Контролы (флажки, ползунки, карточки)
# собираются здесь же, процедурными текстурами: движковые картинки ассетов не
# нужны, а вид остаётся управляемым одним местом.
#
# Раскладка — одна сетка на все экраны: левый край MARGIN, колонка навигации
# NAV_W, контент CONTENT_X. Разрывы кратны RHYTHM.

const AMBER := Color(0.96, 0.62, 0.13)
const AMBER_HI := Color(1.0, 0.74, 0.26)
const AMBER_DEEP := Color(0.78, 0.47, 0.07)
const AMBER_SOFT := Color(0.96, 0.62, 0.13, 0.45)
const TEXT := Color(0.95, 0.96, 0.98)
const DIM := Color(0.63, 0.67, 0.73)
const FAINT := Color(0.45, 0.49, 0.55)
const PANEL := Color(0.045, 0.05, 0.065, 0.80)
const PANEL_HOVER := Color(0.12, 0.125, 0.15, 0.92)
const PANEL_CARD := Color(0.115, 0.12, 0.145, 0.96)
const LINE := Color(0.85, 0.87, 0.92, 0.22)
const OK := Color(0.42, 0.88, 0.55)
const WARN := Color(0.96, 0.74, 0.24)
const BAD := Color(0.95, 0.32, 0.24)

const MARGIN := 64.0         # левый край навигации на всех экранах (дизайн-px)
const NAV_W := 300.0         # ширина колонки навигации (дизайн-px)
const CONTENT_X := 420.0     # левый край контента (за навигацией)
const RHYTHM := 8.0          # базовый шаг вертикальных отступов

# Ступень интерфейса. Дробный коэффициент движок отдаёт передёргиванием уже
# отрисованных глифов (замерено: и 1.2×, и точные 2× мыльнее нативных), поэтому
# интерфейс растёт целыми ступенями и own числами раскладки, а не трансформом.
# Ступень замеряется один раз на первом же построении UI: переезд через границу
# посреди сессии не должен оставить часть панелей в одном масштабе.
static var _step := 0

# Заводская ступень по экрану. Живёт отдельно: настройка «большой интерфейс»
# прибавляет к ней единицу и применяется пересборкой меню, поэтому и слушатель
# настроек, и тест ступени должны уметь спросить базу без верчения кэша.
static func base_step() -> int:
	# высота ЭКРАНА, а не окна: игрок с 4K-монитором стартует в окне 1600×900
	# и по размеру окна получил бы первую ступень навсегда
	return 2 if DisplayServer.screen_get_size().y >= 1700 else 1

static func step() -> int:
	if _step == 0:
		_step = base_step()
	return _step

static func force_step(v: int) -> void:
	_step = v

static func px(v: int) -> int:
	return v * step()

static func fx(v: float) -> float:
	return v * float(step())

# ---------------------------------------------------------------- шрифты
static var _sans_cache := {}
static var _mono_cache := {}

# weight — настоящее начертание (400 обычное, 600 полужирное, 800 заголовки):
# заголовки перестают быть «увеличенным текстом» и становятся типографикой.
# italic — наклон для логотипа: скорость в самом слове, как у гоночных брендов
static func sans_font(weight: int = 400, italic := false) -> SystemFont:
	var key := "%d%d" % [weight, int(italic)]
	if not _sans_cache.has(key):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI Variable Display", "Segoe UI", "Inter", "Roboto", "DejaVu Sans", "Liberation Sans"])
		f.font_weight = weight
		f.font_italic = italic
		_sans_cache[key] = f
	return _sans_cache[key]

static func mono_font(weight: int = 400) -> SystemFont:
	if not _mono_cache.has(weight):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["JetBrains Mono", "Cascadia Mono", "DejaVu Sans Mono", "Liberation Mono", "Courier New"])
		f.font_weight = weight
		_mono_cache[weight] = f
	return _mono_cache[weight]

# ---------------------------------------------------------------- тексты
# args — аргументы формата для живой надписи: ключ-шаблон переводится целиком,
# а подстановка происходит при каждой смене языка, а не один раз при сборке.
static func label(text: String, size_px: int, color: Color, weight := 400, mono := false, args: Array = []) -> Label:
	var l := Label.new()
	I18n.bind(l, text, args)
	return _style_label(l, size_px, color, weight, mono)

# Надпись-строка длинного ключа: описание в каталоге хранится целиком,
# а на карточке показывается только первая или вторая его строка.
static func label_line(key: String, line: int, size_px: int, color: Color, weight := 400, mono := false) -> Label:
	var l := Label.new()
	I18n.bind_line(l, key, line)
	return _style_label(l, size_px, color, weight, mono)

# Надпись, склеенная из многострочного ключа в одну строку.
static func label_flat(key: String, size_px: int, color: Color, weight := 400, mono := false) -> Label:
	var l := Label.new()
	I18n.bind_flat(l, key)
	return _style_label(l, size_px, color, weight, mono)

static func _style_label(l: Label, size_px: int, color: Color, weight: int, mono: bool) -> Label:
	l.add_theme_font_override("font", mono_font(weight) if mono else sans_font(weight))
	l.add_theme_font_size_override("font_size", px(size_px))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---------------------------------------------------------------- навигация
# Строка левого меню: плоский текст БЕЗ фоновых плашек — на светлом городке
# тёмный прямоугольник под строкой выглядел «тарелкой». Единственный индикатор —
# янтарная полоса слева: у активной она горит постоянно, у наведённой — тускло.
static func nav_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_width_left = px(3)
	s.border_color = AMBER if selected else Color(0, 0, 0, 0)
	s.corner_radius_top_right = px(4); s.corner_radius_bottom_right = px(4)
	s.content_margin_left = px(23)
	s.content_margin_top = px(11); s.content_margin_bottom = px(11)
	return s

static func nav_item(text: String, big := false) -> Button:
	var b := Button.new()
	I18n.bind(b, text)
	# flat=false: под flat движок не рисует стейт-стильбоксы, и полоса активного
	# пункта исчезала, стоило навести мышь (жалоба со скриншота). Все наши
	# стильбоксы с прозрачным фоном — плашки не появится, полоса рисуется всегда
	b.flat = false
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = px(26)
	empty.content_margin_top = px(11); empty.content_margin_bottom = px(11)
	var lit := nav_style(true)
	var hov := nav_style(false)
	hov.border_color = AMBER_SOFT
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", lit)
	b.add_theme_stylebox_override("focus", hov)
	b.add_theme_stylebox_override("disabled", empty)
	b.add_theme_font_override("font", sans_font(600))
	b.add_theme_font_size_override("font_size", px(26 if big else 20))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	b.add_theme_constant_override("shadow_offset_y", 1)
	return b

# Пометить активный пункт: янтарная полоса держится на кнопке постоянно, а не
# только на наведении; фон — нет, полоса сама по себе читается на любом кадре.
# Важно перекрыть ВСЕ состояния: после клика кнопка в фокусе, и если править
# только normal, фокусный стиль с тусклой полосой съедал индикатор активного
# пункта — ровно жалоба «полосочка пропадает после нажатия».
static func nav_mark_active(b: Button, active: bool) -> void:
	var lit := nav_style(true)
	var plain := nav_style(false)
	plain.border_color = AMBER_SOFT
	b.add_theme_stylebox_override("normal", nav_style(active))
	b.add_theme_stylebox_override("focus", lit if active else plain)
	b.add_theme_stylebox_override("hover", lit if active else plain)
	b.add_theme_color_override("font_color", AMBER if active else TEXT)
	b.add_theme_color_override("font_focus_color", AMBER if active else Color.WHITE)
	# hover обязан согласоваться с активным состоянием: без этого наведённая мышь
	# перекрашивала янтарную надпись обратно в белую
	b.add_theme_color_override("font_hover_color", AMBER if active else Color.WHITE)

# ---------------------------------------------------------------- карточки
static func card_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.20, 0.15, 0.06, 0.97) if selected else PANEL_CARD
	s.set_border_width_all(px(2 if selected else 1))
	s.border_color = AMBER if selected else LINE
	s.set_corner_radius_all(px(8))
	s.content_margin_left = px(18); s.content_margin_right = px(18)
	s.content_margin_top = px(12); s.content_margin_bottom = px(12)
	if selected:
		s.shadow_color = Color(0.96, 0.62, 0.13, 0.18)
		s.shadow_size = px(6)
	return s

# ---------------------------------------------------------------- кнопки
static func action_style() -> Dictionary:
	var norm := StyleBoxFlat.new()
	norm.bg_color = Color(0.86, 0.55, 0.10, 0.97)
	norm.set_corner_radius_all(px(8))
	norm.set_border_width_all(px(1))
	norm.border_color = AMBER_DEEP
	norm.border_width_bottom = px(3)
	norm.content_margin_left = px(24); norm.content_margin_right = px(24)
	norm.content_margin_top = px(14); norm.content_margin_bottom = px(14)
	var hover := norm.duplicate() as StyleBoxFlat
	hover.bg_color = AMBER
	hover.border_color = AMBER_DEEP
	hover.shadow_color = Color(0.96, 0.62, 0.13, 0.25)
	hover.shadow_size = px(8)
	var pressed := norm.duplicate() as StyleBoxFlat
	pressed.bg_color = AMBER_DEEP
	pressed.border_width_bottom = px(1)
	pressed.content_margin_top = px(16); pressed.content_margin_bottom = px(12)
	return {"normal": norm, "hover": hover, "pressed": pressed, "focus": hover, "disabled": norm}

static func action_button(text: String, size_px := 22) -> Button:
	var b := Button.new()
	I18n.bind(b, text)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", sans_font(700))
	b.add_theme_font_size_override("font_size", px(size_px))
	b.add_theme_color_override("font_color", Color(0.07, 0.05, 0.02))
	b.add_theme_color_override("font_hover_color", Color.BLACK)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.BLACK)
	for k in action_style():
		b.add_theme_stylebox_override(k, action_style()[k])
	return b

static func ghost_button(text: String, size_px := 16) -> Button:
	var b := Button.new()
	I18n.bind(b, text)
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", sans_font(600))
	b.add_theme_font_size_override("font_size", px(size_px))
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	var norm := StyleBoxFlat.new()
	norm.set_corner_radius_all(px(6))
	norm.set_border_width_all(px(1))
	norm.border_color = Color(0, 0, 0, 0)
	norm.content_margin_left = px(14); norm.content_margin_right = px(14)
	norm.content_margin_top = px(8); norm.content_margin_bottom = px(8)
	var sel := norm.duplicate() as StyleBoxFlat
	sel.bg_color = PANEL_HOVER
	sel.border_color = AMBER_SOFT
	b.add_theme_stylebox_override("normal", norm)
	b.add_theme_stylebox_override("hover", sel)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("focus", sel)
	return b

# ---------------------------------------------------------------- контролы
# Процедурные текстуры: квадратик-флажок с галочкой и круглая ручка ползунка.
# Image рисуется попиксельно один раз и кэшируется — ассеты не нужны.
static var _tex_cache := {}

static func _rounded_rect_alpha(p: Vector2, size: float, radius: float) -> float:
	# 1 внутри скруглённого прямоугольника, 0 снаружи, гладко на 1 px
	var half := size * 0.5
	var qx := absf(p.x - half) - (half - radius)
	var qy := absf(p.y - half) - (half - radius)
	var d := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - half + radius
	return clampf(0.5 - d, 0.0, 1.0)

static func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	# проекция точки на отрезок считается ОТ НАЧАЛА ОТРЕЗКА: p.dot(ab) вместо
	# (p-a).dot(ab) давала сдвинутый t, и галочка превращалась в пятно в центре
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (p - (a + ab * t)).length()

static func check_tex(checked: bool) -> ImageTexture:
	var sz := px(22)
	var key := "check%d_%d" % [int(checked), sz]
	if _tex_cache.has(key): return _tex_cache[key]
	# вся геометрия рисуется в единицах базовых 22 px: на ступени 2× квадратик
	# остаётся той же формы, просто в два раза больше пикселей
	var u := float(sz) / 22.0
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in sz:
		for x in sz:
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var a := _rounded_rect_alpha(p, float(sz), 5.0 * u)
			if a <= 0.0: continue
			if checked:
				# янтарный квадрат + белая галочка
				var col := AMBER
				var d1 := _dist_seg(p, Vector2(5.5, 11.5) * u, Vector2(9.5, 15.5) * u)
				var d2 := _dist_seg(p, Vector2(9.5, 15.5) * u, Vector2(17.0, 6.5) * u)
				if minf(d1, d2) < 2.4 * u: col = Color(0.98, 0.98, 1.0)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
			else:
				# рамка — кольцо фиксированной толщины: внутренний прямоугольник
				# с тем же скруглением, что внешний минус отступ, иначе на углах
				# «рамка» расходилась пятном и квадратик выглядел обрезанным
				var inner := _rounded_rect_alpha(p - Vector2(1.5, 1.5) * u, float(sz) - 3.0 * u, 3.5 * u)
				var col := Color(0.07, 0.075, 0.09, 0.95 * a) if inner >= 0.5 \
					else Color(0.72, 0.76, 0.82, 0.9 * a)
				img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

static func knob_tex() -> ImageTexture:
	var sz := px(24)
	var key := "knob_%d" % sz
	if _tex_cache.has(key): return _tex_cache[key]
	var u := float(sz) / 24.0
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(sz * 0.5, sz * 0.5)
	for y in sz:
		for x in sz:
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var d := p.distance_to(c)
			if d > 10.0 * u: continue
			var a := clampf(10.0 * u - d, 0.0, 1.0)
			var col := Color(0.93, 0.94, 0.96)
			if d > 8.6 * u: col = Color(0.10, 0.105, 0.13)      # тёмный ободок
			elif d < 3.2 * u: col = AMBER                        # янтарная сердцевина
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

static func style_check(c: CheckBox) -> void:
	c.add_theme_font_override("font", sans_font(500))
	c.add_theme_font_size_override("font_size", px(16))
	c.add_theme_color_override("font_color", TEXT)
	c.add_theme_color_override("font_hover_color", Color.WHITE)
	c.add_theme_color_override("font_pressed_color", AMBER)
	c.add_theme_color_override("font_focus_color", Color.WHITE)
	c.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	c.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	c.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	c.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	c.add_theme_icon_override("checked", check_tex(true))
	c.add_theme_icon_override("unchecked", check_tex(false))

static func style_slider(s: HSlider) -> void:
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(1, 1, 1, 0.10)
	groove.set_corner_radius_all(px(3))
	groove.set_border_width_all(px(1))
	groove.border_color = Color(1, 1, 1, 0.06)
	groove.content_margin_top = px(4); groove.content_margin_bottom = px(4)
	s.add_theme_stylebox_override("slider", groove)
	var fill := StyleBoxFlat.new()
	fill.bg_color = AMBER
	fill.set_corner_radius_all(px(3))
	s.add_theme_stylebox_override("grabber_area", fill)
	var fill_hi := StyleBoxFlat.new()
	fill_hi.bg_color = AMBER_HI
	fill_hi.set_corner_radius_all(px(3))
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	s.add_theme_icon_override("grabber", knob_tex())
	s.add_theme_icon_override("grabber_highlight", knob_tex())

static func style_option(o: OptionButton) -> void:
	var norm := StyleBoxFlat.new()
	norm.bg_color = PANEL_CARD
	norm.set_border_width_all(px(1))
	norm.border_color = LINE
	norm.set_corner_radius_all(px(6))
	norm.content_margin_left = px(14); norm.content_margin_right = px(14)
	norm.content_margin_top = px(7); norm.content_margin_bottom = px(7)
	var sel := norm.duplicate() as StyleBoxFlat
	sel.border_color = AMBER
	sel.bg_color = Color(0.16, 0.13, 0.08, 0.97)
	o.add_theme_stylebox_override("normal", norm)
	o.add_theme_stylebox_override("hover", sel)
	o.add_theme_stylebox_override("pressed", sel)
	o.add_theme_stylebox_override("focus", sel)
	o.add_theme_font_override("font", sans_font(600))
	o.add_theme_font_size_override("font_size", px(16))
	o.add_theme_color_override("font_color", TEXT)

static func panel_style(corner := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL
	s.set_border_width_all(px(1))
	s.border_color = LINE
	s.set_corner_radius_all(px(corner))
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = px(12)
	s.content_margin_left = px(18); s.content_margin_right = px(18)
	s.content_margin_top = px(14); s.content_margin_bottom = px(14)
	return s
