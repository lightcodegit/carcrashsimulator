extends Node
# Lifetime statistics across runs: how many runs were started, how many impacts
# happened, best impact and top speed, distance and time on the tracks, photos
# taken. Stored in user://stats_v1.json — player state, not something the repo
# ships. Written atomically (tmp + rename) the same way the garage and settings
# files are, so a disk error mid-write keeps the previous file intact.
#
# Values accumulate live during a run and are saved after a quiet moment plus on
# exit: a crashed process loses at most one debounce window, not the whole day.

const FILE := "user://stats_v1.json"
const VERSION := 1
const CFG_MAX_BYTES := 65536
const SAVE_DEBOUNCE_MS := 10000

var runs := 0
var crashes := 0
var best_impact := 0.0          # km/h
var top_speed := 0.0            # km/h
var distance := 0.0             # meters
var seconds := 0.0              # simulated seconds on the tracks
var shots := 0                  # photos taken in photo mode and replays

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
	_dirty = true
	_next_save = Time.get_ticks_msec() + SAVE_DEBOUNCE_MS

func add_run() -> void: runs += 1; _touch()
func add_impact(kmh: float) -> void: crashes += 1; best_impact = maxf(best_impact, maxf(kmh, 0.0)); _touch()
func add_speed(kmh: float) -> void: top_speed = maxf(top_speed, maxf(kmh, 0.0)); _touch()
func add_distance(m: float) -> void: distance += maxf(m, 0.0); _touch()
func add_time(s: float) -> void: seconds += maxf(s, 0.0); _touch()
func add_shot() -> void: shots += 1; _touch()

static func _num(value: Variant, fallback: float) -> float:
	# A hostile file may hold strings, arrays, NaN or INF: none of them reach a
	# counter. Unknown keys and wrong types fall back instead of aborting the
	# whole load — one broken field must not wipe every other stat.
	if value is int or value is float:
		var f := float(value)
		return clampf(f, 0.0, 1e12) if is_finite(f) else fallback
	return fallback

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
	}))
	f.close()
	# tmp stands in until the rename lands: the previous file is only removed
	# when the new one is already on disk.
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
			ProjectSettings.globalize_path(FILE)) != OK:
		DirAccess.remove_absolute(tmp)
		push_warning("stats not saved: rename failed")
