extends SceneTree
# The "larger interface" accessibility option: the UI step grows by one whole
# step and is applied by rebuilding the menu, never by a partial rescale.
# Run: godot --headless --path . --script res://tests/d_ui_big.gd
#
# --script harness: the settings autoload and the menu are loaded at runtime,
# after the tree is active, never through compile-time names.
var fails := 0
var frames := 0
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
			cfg.ui_big = false
			var mm = load("res://scenes/main_menu.tscn").instantiate()
			root.add_child(mm)
			var base: int = load("res://scripts/ui/ui_theme.gd").base_step()
			check(load("res://scripts/ui/ui_theme.gd").step() == base,
				"the step starts at the auto base (%d)" % load("res://scripts/ui/ui_theme.gd").step())

			# The live settings screen toggles with persistence (changed emitted);
			# here the change is silent (no save), so the listener is applied
			# explicitly — and the explicit call is idempotent.
			cfg.set_value("ui_big", true, false)
			mm._apply_ui_rebuild()
			check(load("res://scripts/ui/ui_theme.gd").step() == clampi(base + 1, 1, 3),
				"the toggle grows the step by one (%d)" % load("res://scripts/ui/ui_theme.gd").step())
			mm._apply_ui_rebuild()
			check(load("res://scripts/ui/ui_theme.gd").step() == clampi(base + 1, 1, 3),
				"re-applying is idempotent (%d)" % load("res://scripts/ui/ui_theme.gd").step())
			# The rebuilt interface is really bigger: a nav label uses the new step.
			var nav_px: int = load("res://scripts/ui/ui_theme.gd").nav_item("MAP").get_theme_font_size("font_size")
			check(nav_px == 20 * load("res://scripts/ui/ui_theme.gd").step(),
				"the built labels use the new step (%d)" % nav_px)

			# Whole steps only: toggling back returns the base, never a fraction.
			cfg.set_value("ui_big", false, false)
			mm._apply_ui_rebuild()
			check(load("res://scripts/ui/ui_theme.gd").step() == base,
				"turning it off returns the base step (%d)" % load("res://scripts/ui/ui_theme.gd").step())
			load("res://scripts/ui/ui_theme.gd").force_step(0)
			cfg.ui_big = false
			mm.queue_free()
			if fails == 0: print("ALL PASS")
			else: print("FAILS %d" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false
