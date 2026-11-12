extends SceneTree
# Accessibility: the flash-reduction mode extinguishes the sudden bright bursts
# (impact sparks) while non-flashing effects (dust) stay alive.
# Run: godot --headless --path . --script res://tests/d_flash_reduction.gd
#
# This is a --script harness: autoloads are registered only once the tree is
# active, so every script that touches them (EffectsDirector reads Settings)
# is loaded at runtime, never through a compile-time class name.
var fails := 0
var frames := 0
var fx = null
var cfg = null

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	pass

func _process(_dt: float) -> bool:
	frames += 1
	match frames:
		2:
			cfg = root.get_node("/root/Settings")
			cfg.flash_reduction = false
			var car = load("res://scripts/core/car_rig.gd").new()
			car.build(load("res://scripts/core/vehicle_db.gd").get_params("sedan"), root.get_world_3d())
			root.add_child(car)
			fx = load("res://scripts/core/effects_director.gd").new()
			fx.attach(car)   # attach moves the director under car.chassis itself
		4:
			# default: an impact fires the spark burst and the dust puff together
			fx._on_impact(80.0, Vector3.ZERO, Vector3.UP)
			check(fx._sparks.emitting, "impact fires sparks by default")
			check(fx._dust.emitting, "impact fires dust by default")
			cfg.set_value("flash_reduction", true, false)
			fx.reset_transient()
		6:
			check(not fx._sparks.emitting and not fx._dust.emitting,
				"precondition: the previous burst is out")
		# one burst would have died long ago: with reduction on, a new impact
		# must leave the sparks dark while the dust still reacts
		40:
			fx._on_impact(80.0, Vector3.ZERO, Vector3.UP)
			check(not fx._sparks.emitting, "reduction keeps the impact sparks dark")
			check(fx._dust.emitting, "reduction keeps the dust alive")
			cfg.set_value("flash_reduction", false, false)
			fx.reset_transient()
		70:
			fx._on_impact(80.0, Vector3.ZERO, Vector3.UP)
			check(fx._sparks.emitting, "turning the setting back on restores the sparks")
			fx.reset_transient()
		72:
			if fails == 0: print("ALL PASS")
			else: print("FAILS %d" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false
