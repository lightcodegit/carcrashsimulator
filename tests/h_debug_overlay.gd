extends Node
# Debug overlay: enabled → the panel exists; each of the four sections
# prints non-empty text without nan/inf; F2 and F3 work through the real InputMap
# (a synthesised event), and the setting survives the round trip to file and back.
var _fails := 0
var gm: GameManager
var hud: HUD
var overlay: Control

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(1600, 900)
	Settings.debug_mode = true
	GameContext.select("sedan", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().physics_frame
	hud = gm.hud
	overlay = _find_overlay(hud)
	check(overlay != null, "overlay built together with the HUD")
	if overlay == null:
		print("FAILS %d" % _fails); get_tree().quit(1); return
	check(hud._gameplay.has(overlay), "overlay counted in the gameplay panel list")

	# Layout: the overlay must fit on screen and not encroach on the other panels.
	# Checked here, not in h_hud_layout: that test has its own label budget and covered
	# area, and squeezing a foreign panel into it would corrupt its contract.
	var rect := overlay.get_global_rect()
	var view := get_viewport().get_visible_rect()
	check(rect.position.x >= 0 and rect.position.y >= 0
		and rect.end.x <= view.size.x and rect.end.y <= view.size.y,
		"overlay inside the screen (%s in %s)" % [str(rect), str(view.size)])
	var hits := 0
	for p in hud._gameplay:
		if p == overlay: continue
		if rect.intersects(p.get_global_rect()): hits += 1
	check(hits == 0, "overlay does not overlap HUD panels (%d)" % hits)

	# data contract: the overlay reads snapshots, not private fields
	var snap: Dictionary = gm.car.debug_snapshot()
	for key in ["speed_kmh", "steer_deg", "steer_max_deg", "slip", "grounded",
		"pedal", "hand", "heading_deg", "contacts", "skid"]:
		check(snap.has(key), "car snapshot exposes key %s" % key)
	check(is_finite(float(snap.speed_kmh)) and is_finite(float(snap.steer_deg)),
		"snapshot numbers are finite")
	var scene: Dictionary = gm.debug_scene()
	for key in ["map_root", "bounds", "spawn", "endless", "map_id", "crashes"]:
		check(scene.has(key), "scene snapshot exposes key %s" % key)
	var counts := MapDB.debug_counts(scene.map_root, gm.camera.global_position)
	check(int(counts.nodes) > 100, "the tree walk found nodes (%d)" % int(counts.nodes))
	check(int(counts.bodies) > 0, "the map has dynamic bodies (%d)" % int(counts.bodies))

	# sections: F3 cycles through them, the text must be live
	for i in 30:
		await get_tree().process_frame
	# Frame counters exist only under a live renderer: in headless the engine does not
	# count draw calls, so "zero" there is not breakage but a missing GPU.
	if DisplayServer.get_name() != "headless":
		var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		check(calls > 0, "draw calls nonzero under a live renderer (%d)" % calls)
	else:
		print("PARTIAL: draw calls are not measurable under headless")
	var seen := {}
	for i in 4:
		var text := String(overlay._label.text)
		check(text.length() > 24, "section %d prints text (%d chars)" % [i, text.length()])
		check(text.begins_with("DEBUG · "), "section %d is titled (%s)" % [i, text.left(16)])
		check("nan" not in text.to_lower() and "inf" not in text.to_lower(),
			"section %d has no nan/inf" % i)
		# Monospace 14px gives ~8.4 px per glyph, the title field is 348 px. Any longer and
		# the text clips at the panel edge — exactly what the first screenshot caught.
		var widest := 0
		for line in text.split("\n"):
			widest = maxi(widest, String(line).length())
		check(widest <= 41, "no line of section %d is clipped (longest %d)" % [i, widest])
		print("section %d: %s" % [i, text.replace("\n", " · ").strip_edges().left(150)])
		seen[text.left(12)] = true
		_press("debug_section")
		await get_tree().process_frame
	check(seen.size() == 4, "four sections give four distinct titles (%d)" % seen.size())

	# disabling: the panel leaves the tree and the panel list stops counting it.
	# has() on a freed object is forbidden by the engine for TypedArray, so we compare
	# the list length before and after instead of searching for a node that no longer exists.
	var panels_before := hud._gameplay.size()
	_press("debug_toggle")
	await get_tree().process_frame
	await get_tree().process_frame
	check(not Settings.debug_mode, "F2 turned the mode off (setting flipped)")
	check(_find_overlay(hud) == null, "after disabling, no overlay left in the tree")
	check(hud._gameplay.size() == panels_before - 1,
		"panel removed from the gameplay list (%d → %d)" % [panels_before, hud._gameplay.size()])
	_press("debug_toggle")
	await get_tree().process_frame
	check(Settings.debug_mode and _find_overlay(hud) != null, "F2 turned the mode back on")

	# Yielding: F2 rebound to a player action must not toggle the debugger. The live
	# input pipeline: the event goes through the viewport, just like a real key.
	var f2 := InputEventKey.new()
	f2.physical_keycode = KEY_F2
	f2.pressed = true
	InputRouter.rebind("nitro", f2)
	var was := Settings.debug_mode
	get_viewport().push_input(f2)
	await get_tree().process_frame
	check(Settings.debug_mode == was, "F2 taken by the player does not toggle the debugger")
	InputRouter.reset_keys()
	await get_tree().process_frame

	# On pause the overlay must stay alive: pause is exactly when reading the numbers is
	# convenient. The HUD switches to ALWAYS and the overlay inherits it — we verify, not assume.
	gm._set_paused(true)
	await get_tree().process_frame
	var ov := _find_overlay(hud)
	var before := String(ov._label.text)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F3
	ev.pressed = true
	ov.call("_unhandled_input", ev)
	await get_tree().process_frame
	check(String(ov._label.text) != before, "F3 works while paused")
	gm._set_paused(false)
	await get_tree().process_frame

	# the setting takes the file → load path
	Settings.debug_mode = false
	Settings.save()
	var cf := ConfigFile.new()
	check(cf.load("user://settings.cfg") == OK, "cfg reloads")
	var raw: Variant = cf.get_value("video", "debug_mode", null)
	check(raw == false, "the file holds false (%s)" % str(raw))
	Settings.debug_mode = true
	Settings.save()
	Settings.debug_mode = false
	Settings.load_values()
	check(Settings.debug_mode, "true survives to the next load")

	Settings.debug_mode = false
	Settings.save()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _find_overlay(h: HUD) -> Control:
	for c in h.get_children():
		if c is CanvasLayer: continue
		var root := c as Control
		if root == null: continue
		for k in root.get_children():
			if k.get_script() != null and String(k.get_script().resource_path).ends_with("debug_overlay.gd"):
				return k
	return null

# A synthesised event goes through InputMap: this also confirms that the
# debug_toggle and debug_section actions are registered on F2 and F3.
func _press(action: String) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F2 if action == "debug_toggle" else KEY_F3
	ev.pressed = true
	var handled := false
	for node in [hud, overlay]:
		if node == null or not is_instance_valid(node): continue
		node.call("_unhandled_input", ev)
		handled = true
	check(handled, "handler for %s invoked" % action)
