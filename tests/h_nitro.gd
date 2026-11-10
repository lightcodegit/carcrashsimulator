extends Node3D
# Nitro. The first thing checked here: boost is a property of the car MODEL, not a line in
# a preset. The parameters live in VehicleParams with defaults, so the test looks both at a
# bare VehicleParams.new() and at every car in the list — a new body has to get nitro on its
# own, otherwise "give nitro to all new cars" would be something to remember by hand.
# Then — that boost accelerates, drains the tank, does not help on an empty tank, refills
# itself and is never spent without throttle.

var _fails := 0
var car: CarRig
var _emits := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body); floor_body.global_position = Vector3(0, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sport"), get_world_3d())
	car.nitro_changed.connect(func(_a: bool) -> void: _emits += 1)
	_check_all_cars()
	await _check_boost_over_vmax()
	await _check_boost_off_the_line()
	await _check_drain_and_refill()
	await _check_no_throttle()
	_check_inputs()
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _check_all_cars() -> void:
	var fresh := VehicleParams.new()
	check(fresh.nitro_capacity > 0.0 and fresh.nitro_accel > 0.0 and fresh.nitro_vmax > 1.0,
		"a fresh VehicleParams already carries boost (tank %.0f, pull %.1f, ceiling ×%.2f)" % [
			fresh.nitro_capacity, fresh.nitro_accel, fresh.nitro_vmax])
	for id in VehicleDB.ids():
		var p := VehicleDB.get_params(id)
		check(p != null and p.nitro_capacity > 0.0, "%s: nitro exists" % id)
		check(p != null and p.nitro_accel > 0.0 and p.nitro_vmax > 1.0, "%s: boost gives pull and a ceiling" % id)

func _launch(kmh: float, with_nitro: bool) -> void:
	car.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	for _i in 20:
		await get_tree().physics_frame
	car.chassis.linear_velocity = Vector3(kmh / 3.6, 0.0, 0.0)
	Input.action_press("throttle")
	if with_nitro: Input.action_press("nitro")

func _release() -> void:
	Input.action_release("throttle")
	Input.action_release("nitro")

func _settle_frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

# At the published ceiling the pull along the curve is zero, which is exactly where nitro
# has to show: without it the car sits at vmax, with it — it drives past.
func _check_boost_over_vmax() -> void:
	var vmax: float = car.params.vmax_kmh
	await _launch(vmax * 0.95, false)
	await _settle_frames(240)
	var plain := car.speed_kmh()
	await _launch(vmax * 0.95, true)
	await _settle_frames(240)
	var boost := car.speed_kmh()
	_release()
	print("ceiling %.0f km/h: without nitro %.0f, with nitro %.0f (%.2f×)" % [vmax, plain, boost,
		boost / maxf(vmax, 1.0)])
	check(plain < vmax * 1.06,
		"without boost the car does not crawl past the spec sheet (%.0f at %.0f)" % [plain, vmax])
	check(boost > vmax * 1.15,
		"boost raises the ceiling by at least 15%% (%.0f at %.0f)" % [boost, vmax])

# Launch from a standstill: the distance comparison is what the player feels as "yanked forward".
func _check_boost_off_the_line() -> void:
	await _launch(0.0, false)
	await _settle_frames(180)
	var plain := car.speed_kmh()
	await _launch(0.0, true)
	await _settle_frames(180)
	var boost := car.speed_kmh()
	_release()
	print("from a standstill in 3 s: without nitro %.0f km/h, with nitro %.0f km/h (+%.0f%%)" % [
		plain, boost, 100.0 * (boost / maxf(plain, 1.0) - 1.0)])
	check(boost > plain * 1.25,
		"boost adds at least a quarter of the speed in 3 s (%.0f vs %.0f)" % [boost, plain])

func _check_drain_and_refill() -> void:
	_emits = 0
	await _launch(120.0, true)
	var start := car.nitro_fraction()
	var low_before := 1.0
	var spent := 0.0
	for _k in 6:
		await _settle_frames(30)
		low_before = car.nitro_fraction()
		spent += 0.5
	check(start > 0.99, "the tank is full at the start of the run (%.2f)" % start)
	check(low_before < 0.35, "the tank drains visibly over %.1f s (%.2f)" % [spent, low_before])
	for _k in 12:
		await _settle_frames(15)
	check(car.nitro_fraction() < 0.02, "the tank empties completely (%.2f)" % car.nitro_fraction())
	check(not car.nitro_active, "boost does not light on an empty tank")
	# boost must not come back on its own: on an empty tank, holding nitro and throttle,
	# the tank is not topped up and NOT A SINGLE frame gives boost. The previous code topped
	# it up within a frame and opened boost again — a limit cycle behind "it ran out, yet it
	# still pushes as if nitro were on". The check above catches that only through frame parity.
	var flicker := false
	for _k in 60:
		await get_tree().physics_frame
		if car.nitro_active: flicker = true
	check(not flicker, "on an empty tank with nitro held, boost neither flickers nor tops up")
	check(car.nitro_fraction() < 0.02, "an empty tank does not refill itself while nitro is held (%.2f)" % car.nitro_fraction())
	check(_emits >= 2, "boost announces both its start and its end (%d signals)" % _emits)
	# and it does refill: with the nitro key released the tank fills four times slower than it drains
	Input.action_release("nitro")
	await _settle_frames(60)
	var back := car.nitro_fraction()
	check(back > 0.10, "the tank refills on its own (%.2f in 1 s)" % back)
	Input.action_press("nitro")
	await _settle_frames(2)
	check(car.nitro_active, "trying again, the player gets boost once more")
	Input.action_release("nitro")
	await _settle_frames(40)
	_release()

func _check_no_throttle() -> void:
	await _settle_frames(40)
	var before := car.nitro_fraction()
	Input.action_press("nitro")
	await _settle_frames(60)
	var after := car.nitro_fraction()
	Input.action_release("nitro")
	# coasting never burns boost (meanwhile the tank refills calmly — it must not drain)
	check(after >= before - 0.001, "without throttle the tank is not spent (%.2f -> %.2f)" % [before, after])
	check(not car.nitro_active, "without throttle boost does not light")

func _check_inputs() -> void:
	check(InputRouter.DEFAULTS.has("nitro"), "the nitro action exists in the layout")
	var d: Dictionary = InputRouter.DEFAULTS.get("nitro", {})
	check((d.get("keys", []) as Array).size() > 0, "nitro is bound to a key")
	check((d.get("joy", []) as Array).size() > 0, "nitro is bound to a gamepad button")
	check(InputMap.has_action("nitro"), "nitro is registered in the InputMap")
	var kb := 0
	var pad := 0
	for e in InputMap.action_get_events("nitro"):
		if e is InputEventKey: kb += 1
		elif e is InputEventJoypadButton or e is InputEventJoypadMotion: pad += 1
	check(kb > 0 and pad > 0, "in the InputMap nitro lives on both keyboard and gamepad (%d/%d)" % [kb, pad])
