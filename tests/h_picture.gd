extends Node3D
# The picture must stay a picture: players' main complaint was "the cars are black",
# and it can be broken accidentally — e.g. by switching the render backend. therefore
# frame bands are measured numerically (nobody inspects PNGs).
#
# headless has no GPU: the check is skipped there and prints PARTIAL. For tuning
# compensations there are environment variables BGEN / SKYENERGY / AMBIENT.
const BANDS := [
	# [name, y from, y to, min brightness, max]
	["НЕБО", 0.00, 0.22, 0.30, 0.85],
	["ЦЕНТР", 0.40, 0.60, 0.40, 0.85],
	["ЗЕМЛЯ", 0.80, 1.00, 0.18, 0.60],
]
var _fails := 0
var gm: GameManager

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _live() -> bool:
	return DisplayServer.get_name() != "headless"

func _ready() -> void:
	if not _live():
		print("PARTIAL: live rendering unavailable — frame brightness check skipped")
		print("SKIP (headless): frame brightness was not measured")
		get_tree().quit(0)
		return
	GameContext.select("sport", "arena")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	var bg := float(OS.get_environment("BGEN"))
	if bg > 0.0: gm._env.background_energy_multiplier = bg
	var se := float(OS.get_environment("SKYENERGY"))
	if se > 0.0: gm._env.sky.sky_material.energy_multiplier = se
	var ae := float(OS.get_environment("AMBIENT"))
	if ae > 0.0: gm._env.ambient_light_energy = ae
	for _i in 90:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var h := img.get_height()
	var w := img.get_width()
	print("RENDER method=%s size=%s" % [RenderingServer.get_current_rendering_method(), str(img.get_size())])
	for band in BANDS:
		var sum := Vector3.ZERO
		var n := 0
		var clipped := 0
		var y0 := int(h * float(band[1]))
		var y1 := int(h * float(band[2]))
		var y := y0
		while y < y1:
			var x := 0
			while x < w:
				var c := img.get_pixel(x, y)
				sum += Vector3(c.r, c.g, c.b)
				if c.r > 0.99 and c.g > 0.99 and c.b > 0.99: clipped += 1
				n += 1
				x += 4
			y += 4
		var m := sum / maxf(float(n), 1.0)
		var l := 0.2126 * m.x + 0.7152 * m.y + 0.0722 * m.z
		# hue: the sky must be blue, not grey — otherwise its light drifted too
		var blueish := m.z > m.x
		print("LUM %s: r=%.3f g=%.3f b=%.3f brightness=%.3f burned=%d%%" % [
			band[0], m.x, m.y, m.z, l, int(100.0 * float(clipped) / maxf(float(n), 1.0))])
		check(l >= float(band[3]), "%s: band is not black (%.3f < %.3f)" % [band[0], l, float(band[3])])
		check(l <= float(band[4]), "%s: band is not burned out (%.3f > %.3f)" % [band[0], l, float(band[4])])
		check(float(clipped) / maxf(float(n), 1.0) < 0.25, "%s: no more than a quarter of pixels clipped" % band[0])
		if band[0] == "НЕБО":
			# "clear" is not just "bluish": threshold from measurement. Physical sky
			# gave 0.046 (milky), the gradient gives 0.11-0.12.
			check(m.z - m.x >= 0.08,
				"sky is clear: blue exceeds red by %.3f (expected >= 0.08)" % (m.z - m.x))
	# Body measured separately: project its bounding box to screen and sample brightness
	# exactly where the car is. The "black car" complaint is not about the frame average
	# (there the body is brighter than asphalt) but the share of near-black pixels in its box.
	var box := _car_box(img, Vector2(img.get_width(), img.get_height()))
	var sum2 := Vector3.ZERO
	var n2 := 0
	var dark := 0
	var y := int(box.position.y)
	while y < int(box.end.y):
		var x := int(box.position.x)
		while x < int(box.end.x):
			var col := img.get_pixel(x, y)
			var cl := 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b
			sum2 += Vector3(col.r, col.g, col.b)
			if cl < 0.05: dark += 1
			n2 += 1
			x += 1
		y += 1
	var m2 := sum2 / maxf(float(n2), 1.0)
	var dark_frac := float(dark) / maxf(float(n2), 1.0)
	var lum2 := 0.2126 * m2.x + 0.7152 * m2.y + 0.0722 * m2.z
	print("BODY: box %.0fx%.0f, brightness=%.3f, black=%d%%" % [
		box.size.x, box.size.y, lum2, int(100.0 * dark_frac)])
	check(dark_frac < 0.08, "body is not black: near-black pixels %d%%" % int(100.0 * dark_frac))
	check(lum2 > 0.15, "body is distinguishable in frame (%.3f)" % lum2)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# Body screen box: the eight corners of the world-space bounding volume are projected
# by the camera; take the bounding rect and clamp it to the frame edges.
func _car_box(img: Image, size: Vector2) -> Rect2:
	var c: Vector3 = gm.car.chassis.global_position
	var lo := Vector2(size)
	var hi := Vector2.ZERO
	for sx in [-1.0, 1.0]:
		for sy in [-0.6, 0.6]:
			for sz in [-1.0, 1.0]:
				var p := gm.camera.unproject_position(c + Vector3(sx * 0.9, sy * 0.5, sz * 2.2))
				lo.x = minf(lo.x, clampf(p.x, 0, size.x - 1))
				lo.y = minf(lo.y, clampf(p.y, 0, size.y - 1))
				hi.x = maxf(hi.x, clampf(p.x, 0, size.x - 1))
				hi.y = maxf(hi.y, clampf(p.y, 0, size.y - 1))
	return Rect2(lo, hi - lo)
