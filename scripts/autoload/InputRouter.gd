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
	"handbrake":  {"keys": [[KEY_SPACE]], "joy": [["button", 0]]},
	"slowmo":     {"keys": [[KEY_SHIFT]], "joy": [["button", 1]]},
	"cam_cycle":  {"keys": [[KEY_C]], "joy": [["button", 2]]},
	"respawn":    {"keys": [[KEY_R]], "joy": [["button", 3]]},
	"pause":      {"keys": [[KEY_ESCAPE]], "joy": [["button", 6]]},
}

# Короткие подписи для строки управления в меню: полная таблица ACTION_NAMES живёт
# в экране настроек, здесь нужны именно однострочные ярлыки.
const TITLES := {
	"throttle": "ГАЗ", "brake": "ТОРМОЗ", "steer_left": "РУЛЬ ←", "steer_right": "РУЛЬ →",
	"handbrake": "РУЧНИК", "slowmo": "СЛОУ-МО", "cam_cycle": "КАМЕРА", "respawn": "РЕСТАРТ",
	"pause": "ПАУЗА",
}

const BUTTON_NAMES := {
	0: "A", 1: "B", 2: "X", 3: "Y", 4: "LB", 5: "RB", 6: "SELECT", 7: "START",
	8: "L3", 9: "R3", 10: "L", 11: "R", 12: "D-PAD ↑", 13: "D-PAD ↓", 14: "D-PAD ←", 15: "D-PAD →",
}
const AXIS_NAMES := {
	0: "СТИК L→R", 1: "СТИК L↑↓", 2: "ТРИГГЕР L/R", 4: "КУРОК L", 5: "КУРОК R",
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
		# одно событие класса замещает весь класс: назначил клавишу — дефолтные клавиры
		# этого действия убраны, геймпад при этом остался прежний
		var keys := _class_of(over[0]) == "key"
		var out: Array[InputEvent] = []
		for e in events:
			if _kind(e) == "key" and not keys: out.append(e)
			elif _kind(e) != "key" and keys: out.append(e)
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
		return "pad " + String(BUTTON_NAMES.get((e as InputEventJoypadButton).button_index,
			"КНОПКА %d" % (e as InputEventJoypadButton).button_index))
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
		var arr: Array = []
		for tok in String(cf.get_value(Settings.KEYS_SECTION, action, "")).split(",", false):
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
		return "b%d" % (e as InputEventJoypadButton).button_index
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		return "a%d_%d" % [m.axis, int(round(m.axis_value * 100.0))]
	return ""

static func _decode(tok: String) -> InputEvent:
	if tok.length() < 2: return null
	var head := tok.substr(0, 1)
	var rest := tok.substr(1)
	if head == "k":
		var e := InputEventKey.new()
		e.physical_keycode = int(rest)
		return e
	if head == "b":
		var b := InputEventJoypadButton.new()
		b.button_index = int(rest)
		return b
	if head == "a":
		var parts := rest.split("_")
		if parts.size() != 2: return null
		var m := InputEventJoypadMotion.new()
		m.axis = int(parts[0])
		m.axis_value = float(parts[1]) / 100.0
		return m
	return null
