class_name LapTracker
extends Node
# Best-lap timing and ghost recording for closed circuits.
#
# The tracker watches the car's position and detects a lap when the car
# returns to the start line after covering at least MIN_LAP_M of driving
# (the circuit perimeter is ~800 m, so 600 m rules out re-crossing at the
# line without a full lap). During each lap it samples the car's transform
# and wheel poses at RATE Hz; the recording becomes the ghost car's path
# when the lap is a new best.
#
# No visuals here: GameManager wires lap_finished to the ghost and the HUD.
# The lap check lives in tick() — a pure function of position, dt and
# forward speed — so the logic is testable without physics.

signal lap_started(lap: int)
signal lap_finished(time_s: float, lap: int, best: bool)

const RATE := 20.0                       # ghost samples per second (same as ReplayRecorder)
const MIN_LAP_M := 600.0                 # a closer return to the line is not a lap
const LINE_RADIUS := 15.0                # distance to the line that counts as "at the line"
const MIN_FORWARD_MS := 1.0              # velocity along the heading to count as a crossing
const MAX_SAVED_BYTES := 262144          # same guard as the settings file
const LAP_VERSION := 1
const MAX_FRAMES := 2400                 # 2 minutes at RATE; a sane lap is ~600 frames

var car: CarRig
var line := Vector3.ZERO                 # start/finish origin (world)
var heading := Vector3.RIGHT             # crossing direction (unit, horizontal)

var lap := 0                             # completed laps (1-based for the last one)
var time := 0.0                          # current lap time (s)
var best := INF                          # best lap time (s); INF = none yet
var last_recording: Array = []           # frames of the most recent completed lap

var _dist := 0.0                         # meters driven since the last line event
var _last := Vector3.ZERO
var _recording: Array = []               # frames of the current lap
var _acc := 0.0

func setup(p_car: CarRig, p_line: Vector3) -> void:
	car = p_car
	line = p_line
	name = "LapTracker"
	var fwd := car.forward()
	fwd.y = 0.0
	heading = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.RIGHT
	_last = car.chassis.global_position

func reset() -> void:
	# Respawn: the lap count survives, the current lap restarts.
	time = 0.0
	_dist = 0.0
	_recording.clear()
	_acc = 0.0
	if car != null and car.chassis != null:
		_last = car.chassis.global_position

func _physics_process(dt: float) -> void:
	if car == null or car.chassis == null: return
	if get_tree().paused: return
	if car.replaying: return
	tick(car.chassis.global_position, dt, car.chassis.linear_velocity.dot(heading))

# One tracking step. Returns true when a lap was completed this call.
# Callable from tests with fake positions — no physics required.
func tick(pos: Vector3, dt: float, forward_ms: float) -> bool:
	var delta := pos - _last
	delta.y = 0.0
	_last = pos
	_dist += delta.length()
	time += dt

	# ghost recording at RATE Hz
	_acc += dt
	if _acc >= 1.0 / RATE:
		_acc = minf(_acc - 1.0 / RATE, 1.0 / RATE)
		if _recording.size() < MAX_FRAMES:
			_recording.append(_sample(pos))

	var flat := Vector3(pos.x, 0.0, pos.z)
	var line_flat := Vector3(line.x, 0.0, line.z)
	if flat.distance_to(line_flat) >= LINE_RADIUS: return false
	if _dist < MIN_LAP_M: return false
	if forward_ms < MIN_FORWARD_MS: return false

	lap += 1
	var t := time
	var is_best := t < best
	if is_best: best = t
	last_recording = _recording
	_recording = []
	_acc = 0.0
	time = 0.0
	_dist = 0.0
	lap_finished.emit(t, lap, is_best)
	lap_started.emit(lap)
	return true

func _sample(pos: Vector3) -> Dictionary:
	var xf := car.chassis.global_transform if car != null and car.chassis != null else Transform3D.IDENTITY
	var b := xf.basis
	var nw := car.wheel_count() if car != null else 0
	var wheels := PackedFloat32Array()
	wheels.resize(nw * 3)
	for i in nw:
		var wp := car.wheel_pose(i)
		wheels[i * 3] = wp.x
		wheels[i * 3 + 1] = wp.y
		wheels[i * 3 + 2] = wp.z
	return {
		"t": time,
		"p": PackedFloat32Array([pos.x, pos.y, pos.z]),
		"b": PackedFloat32Array([b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]),
		"w": wheels,
	}

# Seconds → "M:SS.CC" for HUD and tips.
static func fmt_time(t: float) -> String:
	var cs := int(round(maxf(t, 0.0) * 100.0))
	return "%d:%02d.%02d" % [cs / 6000, (cs % 6000) / 100, cs % 100]

# ---- best lap persistence ----------------------------------------------------
# Keyed by map + car: a ghost of a different model would mislead the player,
# and different cars have different lap times.

static func best_path(map_id: String, car_id: String) -> String:
	return "user://bestlap_%s_%s.lap" % [map_id, car_id]

static func save_best(map_id: String, car_id: String, time_s: float, frames: Array) -> bool:
	if frames.is_empty(): return false
	var f := FileAccess.open(best_path(map_id, car_id), FileAccess.WRITE)
	if f == null: return false
	f.store_var({"version": LAP_VERSION, "time": time_s, "frames": frames})
	var ok := f.get_error() == OK
	f.close()   # the file must be on disk before the ghost reads it back
	return ok

static func load_best(map_id: String, car_id: String) -> Dictionary:
	var path := best_path(map_id, car_id)
	if not FileAccess.file_exists(path): return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	if f.get_length() > MAX_SAVED_BYTES:
		f.close()
		return {}
	var v: Variant = f.get_var()
	f.close()
	if not _recording_valid(v): return {}
	return v

static func _recording_valid(v: Variant) -> bool:
	# Same discipline as ReplayRecorder.tape_at: the file is untrusted input,
	# and a malformed frame would crash the ghost mid-lap.
	if not (v is Dictionary) or int(v.get("version", 0)) != LAP_VERSION: return false
	if not (v.get("frames", []) is Array): return false
	var frames: Array = v["frames"]
	if frames.is_empty() or frames.size() > MAX_FRAMES: return false
	if not (v.get("time", 0.0) is float) or not is_finite(v["time"]): return false
	for fr in frames:
		if not (fr is Dictionary): return false
		if not fr.has("t") or not fr.has("p") or not fr.has("b") or not fr.has("w"): return false
		if not (fr["t"] is float) or not is_finite(fr["t"]): return false
		if not (fr["p"] is PackedFloat32Array) or (fr["p"] as PackedFloat32Array).size() != 3: return false
		if not _finite_all(fr["p"]): return false
		if not (fr["b"] is PackedFloat32Array) or (fr["b"] as PackedFloat32Array).size() != 9: return false
		if not _finite_all(fr["b"]): return false
		if not (fr["w"] is PackedFloat32Array) or (fr["w"] as PackedFloat32Array).size() % 3 != 0: return false
		if not _finite_all(fr["w"]): return false
	return true

static func _finite_all(arr: Variant) -> bool:
	if not (arr is PackedFloat32Array): return false
	for v in (arr as PackedFloat32Array):
		if not is_finite(v): return false
	return true
