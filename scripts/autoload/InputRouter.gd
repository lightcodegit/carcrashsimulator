extends Node
# Раскладка клавиш. Дефолт живёт в DEFAULTS, игрок может переопределить любое действие
# на клавишу, кнопку или ось геймпада; переопределение хранится в user://settings.cfg
# вместе с остальными настройками (см. Settings).
#
# Каждое действие держит по одному событию на класс устройства: клавиатура и геймпад
# не перетирают друг друга, поэтому, назначив ручник на кнопку геймпада, игрок не
# теряет пробел.

const DEFAULTS := {
	"throttle":   {"keys": [[KEY_W], [KEY_UP]], "joy": [["motion", 5, 0.5]]},
	"brake":      {"keys": [[KEY_S], [KEY_DOWN]], "joy": [["motion", 4, 0.5]]},
	"steer_left": {"keys": [[KEY_A], [KEY_LEFT]], "joy": [["motion", 0, -0.5]]},
	"steer_right":{"keys": [[KEY_D], [KEY_RIGHT]], "joy": [["motion", 0, 0.5]]},
	# Ручник на геймпаде — и крестик, и L1: на консолях ручную стояночную почти всегда
	# ждут на плечевой кнопке, и второй вариант ничего не стоит
	"handbrake":  {"keys": [[KEY_SPACE]], "joy": [["button", 0], ["button", 9]]},
	# Нитро на Shift — гоночная привычка; Слоу-мо уступает ей Shift и переезжает на Ctrl,
	# потому что две болезни на одной кнопке игрок почувствует как «сломался Shift».
	"nitro":      {"keys": [[KEY_SHIFT]], "joy": [["button", 10]]},
	"slowmo":     {"keys": [[KEY_CTRL]], "joy": [["button", 1]]},
	"cam_cycle":  {"keys": [[KEY_C]], "joy": [["button", 2]]},
	"respawn":    {"keys": [[KEY_R]], "joy": [["button", 3]]},
	"pause":      {"keys": [[KEY_ESCAPE]], "joy": [["button", 6]]},
}

# Индексы — нормализованные Godot JoyButton/JoyAxis (перепроверены на этой сборке
# печатью самих констант: JOY_BUTTON_A=0 … JOY_BUTTON_START=6, D-PAD 11..14,
# курки — оси 4 и 5). Подписи должны совпадать с тем, что игрок видит на геймпаде,
# иначе экран настроек враньём про кнопки хуже, чем их отсутствие.
const BUTTON_NAMES := {
	0: "A", 1: "B", 2: "X", 3: "Y", 4: "SELECT", 5: "PS", 6: "START",
	7: "L3", 8: "R3", 9: "L1", 10: "R1",
	11: "D-PAD ↑", 12: "D-PAD ↓", 13: "D-PAD ←", 14: "D-PAD →",
}
const AXIS_NAMES := {
	0: "СТИК L →/←", 1: "СТИК L ↑/↓", 2: "СТИК R →/←", 3: "СТИК R ↑/↓",
	4: "КУРОК L", 5: "КУРОК R",
}

var _custom := {}      # action -> Array[InputEvent]: то, что назначил игрок

func _ready() -> void:
	for name_v in DEFAULTS:
		if not InputMap.has_action(name_v): InputMap.add_action(name_v)
		_rebuild(name_v)

# Собирает InputMap действия из дефолта и из назначенного игроком.
func _rebuild(action: String) -> void:
	var events: Array[InputEvent] = []
	for kd in DEFAULTS[action].keys:
		var e := InputEventKey.new()
		e.physical_keycode = kd[0]
		events.append(e)
	for jd in DEFAULTS[action].joy:
		events.append(_joy_event(jd))
	var over: Array = _custom.get(action, [])
	if over.is_empty():
		_apply(action, events)
	else:
		# Замещается ТОЛЬКО тот класс устройств, для которого игрок что-то назначил:
		# назначил клавишу — штатные клавиры убраны, геймпад остался. Раньше класс
		# определялся по первому элементу списка, и после назначения и клавиши, и кнопки
		# обратно воскресал дефолтный пробел.
		var has_key := false
		var has_joy := false
		for e in over:
			if _kind(e) == "key": has_key = true
			else: has_joy = true
		var out: Array[InputEvent] = []
		for e in events:
			if _kind(e) == "key" and not has_key: out.append(e)
			elif _kind(e) != "key" and not has_joy: out.append(e)
		for e in over: out.append(e)
		_apply(action, out)

func _apply(action: String, events: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for e in events: InputMap.action_add_event(action, e)

func _class_of(ev: InputEvent) -> String:
	return "key" if ev is InputEventKey else "joy"

func _kind(e: InputEvent) -> String:
	return "key" if e is InputEventKey else "joy"

func _joy_event(jd: Array) -> InputEvent:
	if jd[0] == "button":
		var b := InputEventJoypadButton.new()
		b.button_index = jd[1]
		return b
	var m := InputEventJoypadMotion.new()
	m.axis = jd[1]
	m.axis_value = jd[2]
	return m

static func _same_event(a: InputEvent, b: InputEvent) -> bool:
	# Device здесь намеренно НЕ сравнивается: он участвует только в сохранении
	# привязки. Конфликт считается по физической кнопке, иначе заводской бинд
	# «любой геймпад» (-1) и назначенный на конкретный (0) сошлись как разные,
	# и одно действие начало бы реагировать на одну кнопку дважды.
	if a == null or b == null: return false
	if (a is InputEventKey) and (b is InputEventKey):
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		var va := ka.physical_keycode if ka.physical_keycode != 0 else ka.keycode
		var vb := kb.physical_keycode if kb.physical_keycode != 0 else kb.keycode
		return va == vb
	if (a is InputEventJoypadButton) and (b is InputEventJoypadButton):
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if (a is InputEventJoypadMotion) and (b is InputEventJoypadMotion):
		var ma := a as InputEventJoypadMotion
		var mb := b as InputEventJoypadMotion
		return ma.axis == mb.axis and signi(ma.axis_value) == signi(mb.axis_value)
	return a.is_class(b.get_class()) and a.as_text() == b.as_text()

# Действие, которое сейчас держит это событие (кроме исключённого). Нужен и UI, и
# самому rebind: одна клавиша на два действия заставляла бы жать газ вместе с тормозом.
func find_owner(ev: InputEvent, except_action: String) -> String:
	for other in DEFAULTS.keys():
		if other == except_action: continue
		for e in InputMap.action_get_events(other):
			if _same_event(e, ev): return other
	return ""

# Переопределение: заменяет только тот класс устройств, к которому относится событие.
func rebind(action: String, ev: InputEvent) -> void:
	if not DEFAULTS.has(action): return
	var arr: Array = _custom.get(action, []).duplicate()
	var cls := _class_of(ev)
	var kept: Array = []
	for e in arr:
		if _class_of(e) != cls: kept.append(e)
	kept.append(ev)
	_custom[action] = kept
	_rebuild(action)
	# Если игрок раньше сам назначил это событие другому действию, снимаем его там:
	# иначе одна клавиша жала бы два действия. Дефолтный конфликт (W у газа) здесь не
	# решается: модель замещения класса не умеет выражать «клавиш нет вовсе», а
	# молча оставить действие без бинда хуже, чем предупредить в интерфейсе.
	for other in _custom.keys():
		if other == action: continue
		var arr2: Array = (_custom[other] as Array).duplicate()
		var left: Array = []
		var stripped := false
		for e in arr2:
			if _same_event(e, ev):
				stripped = true
				continue
			left.append(e)
		if stripped:
			_custom[other] = left
			_rebuild(other)
	Settings.save()

func clear_binding(action: String) -> void:
	_custom.erase(action)
	_rebuild(action)
	Settings.save()

func reset_keys() -> void:
	_custom.clear()
	for a in DEFAULTS: _rebuild(a)

func describe(action: String) -> String:
	var parts: Array[String] = []
	for e in InputMap.action_get_events(action):
		var t := event_name(e)
		if t != "" and not (t in parts): parts.append(t)
	return " · ".join(parts)

static func event_name(e: InputEvent) -> String:
	if e is InputEventKey:
		var k := e as InputEventKey
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return OS.get_keycode_string(code)
	if e is InputEventJoypadButton:
		var i := (e as InputEventJoypadButton).button_index
		return String(BUTTON_NAMES.get(i, "КНОПКА %d" % i))
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		var base: String = AXIS_NAMES.get(m.axis, "ОСЬ %d" % m.axis)
		return base + (" −" if m.axis_value < 0.0 else " +")
	return ""

func save_keys(cf: ConfigFile) -> void:
	for action in _custom:
		var toks: Array[String] = []
		for e in _custom[action]: toks.append(_encode(e))
		cf.set_value(Settings.KEYS_SECTION, action, ",".join(toks))

func load_keys(cf: ConfigFile) -> void:
	_custom.clear()
	if not cf.has_section(Settings.KEYS_SECTION): return
	for action in cf.get_section_keys(Settings.KEYS_SECTION):
		# ключа нет в раскладке (файл отредактирован вручную или action удалён в новой
		# версии) — пропустить: иначе DEFAULTS[action] падает на середине и остальные
		# бинды файла уже не загружаются
		if not DEFAULTS.has(action): continue
		var raw: Variant = cf.get_value(Settings.KEYS_SECTION, action, "")
		# значение мог испортить ручной правкой (массив или словарь вместо строки):
		# String(dict) — ошибка выполнения, и за ней не дочитываются остальные бинды
		if not (raw is String): continue
		var arr: Array = []
		for tok in (raw as String).split(",", false):
			var e := _decode(tok)
			if e != null: arr.append(e)
		if not arr.is_empty(): _custom[action] = arr
		_rebuild(action)

# Своя компактная форма вместо as_text()/create_from_text(): у событий геймпада
# сериализация в Godot 4.7 неполная, а молча потерять биндинг хуже, чем его не иметь.
static func _encode(e: InputEvent) -> String:
	if e is InputEventKey:
		var k := e as InputEventKey
		return "k%d" % (k.physical_keycode if k.physical_keycode != 0 else k.keycode)
	if e is InputEventJoypadButton:
		var jb := e as InputEventJoypadButton
		# device пишется всегда: без него бинд переживает перезапуск как «любой
		# геймпад», хотя в том же заезде он принадлежал конкретному. -1 — и есть
		# «любой», значение сохраняется как есть.
		return "b%d@%d" % [jb.button_index, jb.device]
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		return "a%d_%d@%d" % [m.axis, int(round(m.axis_value * 100.0)), m.device]
	return ""

static func _decode(tok: String) -> InputEvent:
	if tok.length() < 2: return null
	var head := tok.substr(0, 1)
	var rest := tok.substr(1)
	if head == "k":
		var code := int(rest)
		# Физический код 0 нельзя нажать. Оставить его — значит выдать действию
		# бинд-призрак: пауза открывается только клавишей, и в заезде игрок остаётся
		# без выхода до перезапуска процесса.
		if code <= 0: return null
		var e := InputEventKey.new()
		e.physical_keycode = code
		return e
	# «@<device>» есть только у новых записей: старый токен («b0», «a0_50») читается
	# как -1 — «любой геймпад», ровно то поведение, что было до правки.
	var dev := -1
	var at := rest.find("@")
	if at >= 0:
		dev = int(rest.substr(at + 1))
		rest = rest.substr(0, at)
	if head == "b":
		var b := InputEventJoypadButton.new()
		b.button_index = int(rest)
		b.device = dev
		return b
	if head == "a":
		var parts := rest.split("_")
		if parts.size() != 2: return null
		var m := InputEventJoypadMotion.new()
		m.axis = int(parts[0])
		m.axis_value = float(parts[1]) / 100.0
		m.device = dev
		return m
	return null
