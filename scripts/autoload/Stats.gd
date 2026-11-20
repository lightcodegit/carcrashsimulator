extends Node
# Lifetime statistics across runs: how many runs were started, how many impacts
# happened, best impact and top speed, distance and time on the tracks, photos
# taken. Stored in user://stats_v1.json - player state, not something the repo
# ships. Written atomically (tmp + rename) the same way as the garage and
# settings files, so a disk error mid-write keeps the previous file intact.
#
# Values accumulate live during a run and are saved after a quiet moment plus on
# exit: a crashed process loses at most one debounce window, not the whole day.
#
# Since v2 the same records are also kept per map and per car. GameManager calls
# begin_run() once when a run is built; every later add_*() lands both in the
# lifetime totals and in the current map/car buckets. Best lap is per map/car
# pair because LapTracker already stores ghosts under that key.

const FILE := "user://stats_v1.json"
const VERSION := 2
const CFG_MAX_BYTES := 65536
const SAVE_DEBOUNCE_MS := 10000
const MAX_BUCKETS := 64
const MAX_ID_LEN := 64

var runs := 0
var crashes := 0
var best_impact := 0.0          # km/h
var top_speed := 0.0            # km/h
var distance := 0.0             # meters
var seconds := 0.0              # simulated seconds on the tracks
var shots := 0                  # photos taken in photo mode and replays
var maps: Dictionary = {}       # map id -> {runs, crashes, best_impact, ...}
var cars: Dictionary = {}       # car id -> the same record shape

var _map_id := ""
var _car_id := ""
var _dirty := false
var _next_save := 0

func _ready() -> void:
	# Saving must also happen while the run is paused: the debounce timer is not
	# gameplay, and a long pause must not push the write past the next tick.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_values()

func _process(_dt: float) -> void:
	if not _dirty or _next_save == 0 or Time.get_ticks_msec() < _next_save: return
	_next_save = 0
	save()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _dirty: save()

func _exit_tree() -> void:
	if _dirty: save()

func _touch() -> void:
	# Дебаунс ставится только фиксацией тика (скорость, время): живой заезд
	# трогает счётчики каждый тик, и сдвиг дедлайна отложил бы запись навсегда.
	_dirty = true
	if _next_save == 0: _next_save = Time.get_ticks_msec() + SAVE_DEBOUNCE_MS

# Called once at the start of a run. Unknown/empty ids are ignored rather than
# written as junk keys into the save file.
func begin_run(map_id: String, car_id: String) -> void:
	_map_id = _clean_id(map_id)
	_car_id = _clean_id(car_id)

static func _clean_id(id: String) -> String:
	var s := id.strip_edges()
	return s if s.length() > 0 and s.length() <= MAX_ID_LEN else ""

static func _blank_record() -> Dictionary:
	return {
		"runs": 0, "crashes": 0, "best_impact": 0.0, "top_speed": 0.0,
		"distance": 0.0, "seconds": 0.0, "best_lap": 0.0,
	}

func _record(store: Dictionary, id: String) -> Dictionary:
	if not store.has(id) or not (store[id] is Dictionary):
		store[id] = _blank_record()
	return store[id] as Dictionary

# The current run always updates two buckets: its map and its car. They are
# independent, so a run on the arena with the sedan also moves arena's and
# sedan's lifetime records. Without begin_run (unit tests, menu reads) the
# global totals still work.
func _buckets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _map_id != "": out.append(_record(maps, _map_id))
	if _car_id != "": out.append(_record(cars, _car_id))
	return out

func add_run() -> void:
	runs += 1
	for r in _buckets(): r["runs"] = int(r["runs"]) + 1
	_touch()

func add_impact(kmh: float) -> void:
	var v := maxf(kmh, 0.0)
	crashes += 1
	best_impact = maxf(best_impact, v)
	for r in _buckets():
		r["crashes"] = int(r["crashes"]) + 1
		r["best_impact"] = maxf(float(r["best_impact"]), v)
	_touch()

func add_speed(kmh: float) -> void:
	var v := maxf(kmh, 0.0)
	top_speed = maxf(top_speed, v)
	for r in _buckets(): r["top_speed"] = maxf(float(r["top_speed"]), v)
	_touch()

func add_distance(m: float) -> void:
	var v := maxf(m, 0.0)
	distance += v
	for r in _buckets(): r["distance"] = float(r["distance"]) + v
	_touch()

func add_time(s: float) -> void:
	var v := maxf(s, 0.0)
	seconds += v
	for r in _buckets(): r["seconds"] = float(r["seconds"]) + v
	_touch()

func add_shot() -> void: shots += 1; _touch()

# Best lap only improves. Zero means "no lap yet"; negative and non-finite input
# is ignored, so a broken tracker cannot poison the record.
func add_best_lap(time_s: float) -> void:
	if not is_finite(time_s) or time_s <= 0.0: return
	for r in _buckets():
		var old := float(r["best_lap"])
		r["best_lap"] = time_s if old <= 0.0 else minf(old, time_s)
	_touch()

func map_record(map_id: String) -> Dictionary:
	return (maps[map_id] as Dictionary).duplicate() if maps.get(map_id) is Dictionary else {}

func car_record(car_id: String) -> Dictionary:
	return (cars[car_id] as Dictionary).duplicate() if cars.get(car_id) is Dictionary else {}

static func _num(value: Variant, fallback: float) -> float:
	# A hostile file may hold strings, arrays, NaN or INF: none of them reach a
	# counter. Unknown keys and wrong types fall back instead of aborting the
	# whole load - one broken field must not wipe every other stat.
	if value is int or value is float:
		var f := float(value)
		return clampf(f, 0.0, 1e12) if is_finite(f) else fallback
	return fallback

static func _record_from(raw: Dictionary) -> Dictionary:
	return {
		"runs": int(_num(raw.get("runs", 0.0), 0.0)),
		"crashes": int(_num(raw.get("crashes", 0.0), 0.0)),
		"best_impact": _num(raw.get("best_impact", 0.0), 0.0),
		"top_speed": _num(raw.get("top_speed", 0.0), 0.0),
		"distance": _num(raw.get("distance", 0.0), 0.0),
		"seconds": _num(raw.get("seconds", 0.0), 0.0),
		"best_lap": _num(raw.get("best_lap", 0.0), 0.0),
	}

# A hand-edited file can hold thousands of keys or arbitrary nested objects:
# take only sane string ids and flat record dictionaries, with a hard cap.
static func _records(value: Variant) -> Dictionary:
	var out := {}
	if not (value is Dictionary): return out
	for key in (value as Dictionary):
		if out.size() >= MAX_BUCKETS: break
		if not (key is String): continue
		var id := _clean_id(key as String)
		var raw: Variant = (value as Dictionary)[key]
		if id == "" or not (raw is Dictionary): continue
		out[id] = _record_from(raw as Dictionary)
	return out

func load_values() -> void:
	if not FileAccess.file_exists(FILE): return
	var probe := FileAccess.open(FILE, FileAccess.READ)
	var size := 0 if probe == null else probe.get_length()
	probe = null
	# Same parser-bomb guard as settings.cfg: a file-sized log would stall the
	# whole startup on the JSON parse.
	if size > CFG_MAX_BYTES:
		push_warning("stats file too large, factory values used")
		return
	var json := JSON.new()
	var raw := FileAccess.get_file_as_string(FILE)
	if json.parse(raw) != OK or not json.data is Dictionary:
		push_warning("broken stats file, factory values used")
		return
	var d: Dictionary = json.data
	runs = int(_num(d.get("runs", runs), float(runs)))
	crashes = int(_num(d.get("crashes", crashes), float(crashes)))
	best_impact = _num(d.get("best_impact", best_impact), best_impact)
	top_speed = _num(d.get("top_speed", top_speed), top_speed)
	distance = _num(d.get("distance", distance), distance)
	seconds = _num(d.get("seconds", seconds), seconds)
	shots = int(_num(d.get("shots", shots), float(shots)))
	maps = _records(d.get("maps", {}))
	cars = _records(d.get("cars", {}))
	_dirty = false

func save() -> void:
	_dirty = false
	var tmp := FILE + ".part"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("stats not saved: cannot create " + tmp)
		return
	f.store_string(JSON.stringify({
		"version": VERSION, "runs": runs, "crashes": crashes,
		"best_impact": best_impact, "top_speed": top_speed,
		"distance": distance, "seconds": seconds, "shots": shots,
		"maps": maps, "cars": cars,
	}))
	f.close()
	# tmp stands in until the rename lands: the previous file is only removed
	# when the new one is already on disk.
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
			ProjectSettings.globalize_path(FILE)) != OK:
		DirAccess.remove_absolute(tmp)
		push_warning("stats not saved: rename failed")
