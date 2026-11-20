class_name VideoExport
extends RefCounted
# Replay-to-video export built on Godot's Movie Maker mode.
#
# Movie Maker cannot be toggled from a running game, so the documented path is a
# second instance of the same executable launched with --write-movie. This class
# owns the small contract between the two processes:
#   * the parent saves the current replay tape and builds the child's arguments;
#   * the child sees --replay-export <tape>, sets its map/car from the tape and
#     plays it back with Movie Maker recording.
# Keeping argument construction here (instead of inside GameManager) makes the
# launch contract testable without a window: h_video_export checks the exact
# argv that would be passed to the child.
#
# The video is AVI/MJPEG, the only lossless-container-free format both the editor
# and exported templates can write without extra tools. It is deliberately not a
# per-frame PNG sequence: a 10 s replay at 30 fps would leave 300 files on disk.

const ARG := "--replay-export"
const DIR := "user://videos"
const FPS := 30
const WIDTH := 1280
const HEIGHT := 720
const MAX_ID_LEN := 32

# Filled by MainMenu when the child process starts; consumed and cleared by
# GameManager once the replay is actually playing.
static var request: Dictionary = {}

# Cheap check used by Settings before it touches window geometry: only the
# presence of the flag matters, reading the tape comes later.
static func is_export_run(args: PackedStringArray = []) -> bool:
	var a := args if not args.is_empty() else OS.get_cmdline_user_args()
	return a.find(ARG) >= 0

# Returns {tape, map, car} for a child run, or {} when the flag is absent or the
# tape is unreadable. ReplayRecorder.tape_at is the same validator the replay
# screen uses, so a corrupt tape is rejected before a window is even built.
static func parse_user_args(args: PackedStringArray) -> Dictionary:
	var i := args.find(ARG)
	if i < 0 or i + 1 >= args.size(): return {}
	var tape_path := args[i + 1]
	var tape := ReplayRecorder.tape_at(tape_path)
	if tape.is_empty(): return {}
	var map_id := String(tape.get("map", ""))
	var car_id := String(tape.get("car", ""))
	if map_id == "" or car_id == "": return {}
	return {"tape": tape_path, "map": map_id, "car": car_id}

static func load_tape(req: Dictionary) -> Dictionary:
	return ReplayRecorder.tape_at(String(req.get("tape", "")))

static func absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("user://") else path

# Stable file stem: ids come from the game, but a hand-edited tape or a future
# map id must never turn into path separators or a traversal.
static func safe_id(id: String) -> String:
	var out := ""
	for i in mini(id.length(), MAX_ID_LEN):
		var c := id.substr(i, 1)
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
			or (c >= "0" and c <= "9") or c == "_" or c == "-"
		out += c if ok else "_"
	return out if out != "" else "replay"

static func ensure_dir() -> bool:
	var d := DirAccess.open("user://")
	if d == null: return false
	if d.dir_exists("videos"): return true
	return d.make_dir("videos") == OK

static func _unique(stem: String, ext: String, stamp: int) -> String:
	var base := "%s/%s_%d" % [DIR, stem, stamp]
	var path := base + ext
	var n := 1
	while FileAccess.file_exists(path):
		path = "%s_%d%s" % [base, n, ext]
		n += 1
	return path

static func tape_path(map_id: String, car_id: String, stamp: int) -> String:
	ensure_dir()
	return _unique("replay_%s_%s" % [safe_id(map_id), safe_id(car_id)], ".replay", stamp)

static func output_path(map_id: String, car_id: String, stamp: int) -> String:
	ensure_dir()
	return _unique("replay_%s_%s" % [safe_id(map_id), safe_id(car_id)], ".avi", stamp)

# The child argv. Editor builds need --path because OS.get_executable_path()
# points at the editor binary; exported games already carry their project.
# --fixed-fps makes the replay step exactly once per rendered frame even when the
# machine cannot keep up in real time, which is the whole point of Movie Maker.
# --resolution is a *request*, not a guarantee: Godot 4.7.2 records the project
# viewport size (1600x900 here) and ignored the flag in the measured run. The size
# is still passed so a future build that honours it gets the intended frame.
static func plan(tape_path: String, out_path: String, editor: bool,
		width: int = WIDTH, height: int = HEIGHT, fps: int = FPS) -> Dictionary:
	if not FileAccess.file_exists(tape_path): return {}
	var tape_abs := absolute(tape_path)
	var out_abs := absolute(out_path)
	var args := PackedStringArray()
	if editor:
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))
	args.append("--write-movie")
	args.append(out_abs)
	args.append("--fixed-fps")
	args.append(str(clampi(fps, 1, 240)))
	args.append("--resolution")
	args.append("%dx%d" % [clampi(width, 320, 7680), clampi(height, 240, 4320)])
	args.append("--")
	args.append(ARG)
	args.append(tape_abs)
	return {"path": out_path, "abs": out_abs, "args": args}
