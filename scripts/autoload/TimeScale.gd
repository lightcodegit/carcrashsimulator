extends Node
var _auto_until_ms := 0
var _held := false
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
func play_auto(factor: float, real_secs: float) -> void:
	Engine.time_scale = factor
	_auto_until_ms = Time.get_ticks_msec() + int(real_secs * 1000.0)
func set_hold(flag: bool) -> void:
	_held = flag
	if flag: Engine.time_scale = 0.3
func _process(_d: float) -> void:
	if Engine.time_scale == 1.0: return
	if Time.get_ticks_msec() >= _auto_until_ms and not _held:
		Engine.time_scale = 1.0
