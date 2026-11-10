extends Node
# Slider contract: HSlider is built in SETTING UNITS, and the display multiplier
# multiplies the bounds themselves (see _build_slider: min*mul, max*mul). If the table
# kept display units, the range would drift manyfold and the settings clamp would
# silently eat all slider travel: the player moves the knob while the value stays pinned.
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var menu := preload("res://scripts/ui/settings_menu.gd")
	for row in menu.SLIDERS:
		var key := String(row[0])
		check(Settings.NUMS.has(key), "slider %s has a bound in NUMS" % key)
		if not Settings.NUMS.has(key): continue
		var mul := float(row[6])
		# The table stores REAL setting units: _build_slider multiplies the bounds by mul
		# only for display, and refresh writes value*mul to the slider.
		var lo := float(row[2])
		var hi := float(row[3])
		var wlo := float(Settings.NUMS[key][0])
		var whi := float(Settings.NUMS[key][1])
		check(lo >= wlo - 1e-12 and hi <= whi + 1e-12,
			"%s: slider asks for %.5f..%.5f, allowed %.5f..%.5f (mul=%.1f)" % [key, lo, hi, wlo, whi, mul])
		# the step must fit into the range at least 4 times, otherwise the knob toggles
		# between two values and the setting looks broken
		var steps := (hi - lo) / maxf(absf(float(row[4])), 1e-12)
		check(steps >= 4.0, "%s: step %.5f cuts the range into %.1f parts" % [key, float(row[4]), steps])
		# The step must divide EVERY stock value: Range snaps a programmatically set value
		# to the step (measured: 1.6 with step 0.5 becomes 1.5), so the page caption lies
		# and the very first move pulls the setting off its preset.
		# Compare in DISPLAY UNITS: s.step = row[4] * mul, value = v * mul.
		var dstep := absf(float(row[4]) * mul)
		var shipped: Array = [Settings._defaults.get(key, null)]
		for pr in Settings.PRESETS:
			shipped.append(pr[1].get(key, null))
		for v in shipped:
			if v == null: continue
			var disp := float(v) * mul
			var nearest := roundf(disp / dstep) * dstep
			check(absf(nearest - disp) <= 1e-6 * maxf(1.0, absf(disp)),
				"%s: value %.5f does not sit on slider step %.3f (page will show %.3f)" % [key, float(v), dstep, nearest])
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
