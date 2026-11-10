extends Node3D
# What the picture costs — measured by a live window, not headless: headless has
# no GPU, so frame time there says nothing about rendering. Prints not only the
# average but the distribution of frame durations: "30 fps at any settings" is a
# signature of the vsync quantum, visible only in a histogram.
#
# The budget is strict: under Wayland the compositor will not let the app disable
# vsync (the engine plainly writes "V-Sync mode Disabled is not available"), so a
# frame longer than 16.7 ms at 60 Hz lands exactly on 33.3 ms — that is the 30
# fps the player sees.
#
# STAGES=all,shadow,max,s90 — which configurations to measure, one after another.
const SETTLE := 45    # ticks for the framebuffer to rebuild after a settings change
const WINDOW := 180   # frames the statistic is computed over

# Name -> configuration. msaa/shadow are indices from Settings; scale is the
# internal 3D resolution: it cuts the pixel passes while geometry stays, so it is
# the cheapest way to fit into 16.7 ms on a weak GPU.
const PRESETS := {
	"all":    { "msaa": 0, "shadow": 0, "ssao": false, "ssil": false, "fog": false,
		"glow": false, "fxaa": false, "scale": 1.0 },
	"shadow": { "msaa": 0, "shadow": 1, "ssao": false, "ssil": false, "fog": false,
		"glow": false, "fxaa": true, "scale": 1.0 },
	"sglow":  { "msaa": 0, "shadow": 1, "ssao": false, "ssil": false, "fog": false,
		"glow": true, "fxaa": true, "scale": 1.0 },
	"max":    { "msaa": 2, "shadow": 2, "ssao": true, "ssil": true, "fog": true,
		"glow": true, "fxaa": true, "scale": 1.0 },
	# msaa -1 = leave alone: the value comes from the config before the first frame.
	# Needed because switching MSAA on the fly does not always rebuild the
	# multisample buffer, and the cost then measures out at zero — which is why
	# combinations are measured through STAGES=env.
	"keep":   { "msaa": -1, "shadow": 0, "ssao": false, "ssil": false, "fog": false,
		"glow": false, "fxaa": false, "scale": 1.0 },
	# "as at boot": nothing changes except vsync — this checks that the project
	# defaults really do fit into 16.7 ms on a weak GPU
	"boot":   { "msaa": -1, "shadow": -1, "ssao": null, "ssil": null, "fog": null,
		"glow": null, "fxaa": null, "scale": -1.0 },
}

# Presets from the settings: their cost has to be known, not promised.
const PRESET_STAGES := { "p0": 0, "p1": 1, "p2": 2, "p3": 3 }

var _gm: GameManager
var _measuring := false
var _t0 := 0
var _ms := PackedFloat64Array()

func _ready() -> void:
	var ids := OS.get_environment("STAGES")
	if ids == "": ids = "all"
	print("PROBE driver=%s display=%s method=%s adapter=%s type=%d size=%s" % [
		RenderingServer.get_current_rendering_driver_name(),
		DisplayServer.get_name(),
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_type(),
		str(get_window().size)])
	GameContext.select("sport", "speedway")
	_gm = load("res://scenes/game.tscn").instantiate()
	add_child(_gm)
	await get_tree().process_frame
	# "set:N" — only write preset N into the config and exit: a preset has to be
	# measured from a cold start, because MSAA does not rebuild the buffer on the fly
	# (see keep)
	if ids.begins_with("set:"):
		Settings.reset()
		Settings.apply_preset(int(ids.substr(4)))
		print("PROBE preset %d -> %s written" % [int(ids.substr(4)), Settings.preset_name()])
		get_tree().quit(0)
		return
	for id in ids.split(",", false):
		var p: Dictionary = {}
		if id == "env":
			# combinations come from the environment, because their list is longer
			# than one wants to keep in code: SHADOW/GLOW/FOG/SCALE, msaa from config
			var sc := float(OS.get_environment("SCALE"))
			p = { "msaa": -1, "shadow": int(OS.get_environment("SHADOW")),
				"ssao": OS.get_environment("SSAO") == "1", "ssil": false,
				"fog": OS.get_environment("FOG") == "1",
				"glow": OS.get_environment("GLOW") == "1", "fxaa": false,
				"scale": sc if sc > 0.0 else 1.0 }
		elif PRESET_STAGES.has(id):
			# the preset is applied to the settings themselves and _apply changes
			# nothing: this measures exactly what a player choosing it gets
			Settings.reset()
			Settings.apply_preset(PRESET_STAGES[id])
			p = { "msaa": -1, "shadow": -1, "ssao": null, "ssil": null, "fog": null,
				"glow": null, "fxaa": null, "scale": -1.0 }
		elif PRESETS.has(id):
			p = PRESETS[id]
		else:
			push_warning("PROBE: unknown stage " + id)
			continue
		_apply(p)
		await _wait(SETTLE)
		_ms = PackedFloat64Array()
		_t0 = Time.get_ticks_usec()
		_measuring = true
		await _wait(WINDOW)
		_measuring = false
		var total := float(Time.get_ticks_usec() - _t0) / 1000.0 / _ms.size()
		# one vsync interval or two: at 60 Hz that is exactly the difference between
		# "runs at 60" and "runs at 30", and the per-frame average hides it
		var one := 0
		var two := 0
		var rest := 0
		for d in _ms:
			if d < 22.0: one += 1
			elif d < 45.0: two += 1
			else: rest += 1
		print("STAGE %s: %.2f ms/frame = %.1f fps | <=22=%d 22-45=%d >45=%d" % [
			id, total, 1000.0 / total, one, two, rest])
	print("PROBE done")
	get_tree().quit(0)

func _process(dt: float) -> void:
	if _measuring: _ms.append(dt * 1000.0)

func _wait(n: int) -> void:
	for _i in n:
		await get_tree().process_frame

# Settings fields directly, not via set_value(): only the picture matters here, and
# writing every configuration to the file would pollute the player's settings.
func _apply(p: Dictionary) -> void:
	Settings.vsync = Settings.VSync.OFF
	Settings.fps_limit = 0
	if int(p.msaa) >= 0:
		Settings.msaa = int(p.msaa)
	if int(p.shadow) >= 0:
		Settings.shadow_preset = int(p.shadow)
	if p.ssao != null: Settings.ssao = bool(p.ssao)
	if p.ssil != null: Settings.ssil = bool(p.ssil)
	if p.fog != null: Settings.fog = bool(p.fog)
	if p.glow != null: Settings.glow = bool(p.glow)
	if p.fxaa != null: Settings.screen_aa = bool(p.fxaa)
	Settings.apply_window()
	_gm._apply_render()
	# NOSKY=1: keep the sky as a light source (it bakes into the cubemap once) but
	# do not draw it every frame — that is a fullscreen shader with rayleigh/mie,
	# and its cost decides whether switching drivers means anything
	if OS.get_environment("NOSKY") == "1":
		_gm._env.background_mode = Environment.BG_COLOR
		_gm._env.bg_color = Color(0.35, 0.5, 0.68)
	if float(p.scale) > 0.0:
		get_window().scaling_3d_scale = float(p.scale)
	print("CFG msaa=%d shadow=%d glow=%d fog=%d ssao=%d fxaa=%d scale=%.2f nosky=%d" % [
		Settings.msaa, Settings.shadow_preset, int(Settings.glow), int(Settings.fog),
		int(Settings.ssao), int(Settings.screen_aa), get_window().scaling_3d_scale,
		int(OS.get_environment("NOSKY") == "1")])
