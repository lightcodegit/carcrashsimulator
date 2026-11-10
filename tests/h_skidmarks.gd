extends Node3D
# Tire marks: a strip appears only where a wheel actually slides.
# A) straight acceleration — no marks
# B) handbrake drift — marks exist, lie on the ground, width and length within the contact patch
# C) handbrake released — grip returned, marks stopped growing
# D) respawn breaks the strip: no smear across the whole map from the crash site to the start
# E) the ring overwrites the oldest slots and does not grow
# F) GameManager attaches SkidMarks to the live car
const SLOTS_HALF := SkidMarks.SLOTS / 2

var _fails := 0
var car: CarRig
var skid: SkidMarks
var _phase := "A"
var _ticks := 0
var _marks_at_phase := 0
var _spawn := Vector3(-20, 1.0, 0)
var _marks_before_respawn := 0
var _marks_at_drift := 0
var _marks_settled := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _enter(phase: String) -> void:
	_phase = phase
	_ticks = 0
	_marks_at_phase = skid.marks_drawn()

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(2400, 2, 900); cs.shape = box
	floor_body.add_child(cs); add_child(floor_body)
	floor_body.global_position = Vector3(600, -1, 0)
	await get_tree().process_frame
	car = CarRig.new(); add_child(car)
	car.build(VehicleDB.get_params("sedan"), get_world_3d())
	car.respawn(Transform3D(Basis.IDENTITY, _spawn))
	skid = SkidMarks.new(); add_child(skid)
	skid.setup(car)
	Input.action_press("throttle")

func _physics_process(_dt: float) -> void:
	if car == null or not is_instance_valid(car) or car.chassis == null: return
	_ticks += 1
	match _phase:
		"A":
			if _ticks == 90:
				check(skid.marks_drawn() == 0, "A: straight acceleration leaves no marks (%d)" % skid.marks_drawn())
				check(car.speed_kmh() > 30.0, "A: the car accelerated (%.1f km/h)" % car.speed_kmh())
				Input.action_press("handbrake")
				Input.action_press("steer_left")
				_enter("B")
		"B":
			if _ticks == 60:
				check(skid.marks_drawn() - _marks_at_phase > 30,
					"B: the handbrake drift left marks (%d segments)" % (skid.marks_drawn() - _marks_at_phase))
				_check_geometry()
				Input.action_release("handbrake")
				Input.action_release("steer_left")
				_enter("C")
		"C":
			# the drift is killed by ESP not instantly: first let the grip return, and only
			# then demand the marks stop growing altogether
			if _ticks == 90:
				_marks_settled = skid.marks_drawn()
			if _ticks == 180:
				check(skid.marks_drawn() == _marks_settled,
					"C: marks do not grow after grip returns (%d in 1.5 s)" % (skid.marks_drawn() - _marks_settled))
				_marks_before_respawn = skid.marks_drawn()
				car.respawn(Transform3D(Basis.IDENTITY, Vector3(400, 1.0, 200)))
				skid.respawn()
				_enter("D")
		"D":
			if _ticks == 60:
				check(skid.marks_drawn() == _marks_before_respawn,
					"D: respawn did not draw a strip across the map (%d → %d)" % [_marks_before_respawn, skid.marks_drawn()])
				check(car.speed_kmh() > 15.0, "D: the car moves again after respawn (%.1f km/h)" % car.speed_kmh())
				_marks_at_drift = skid.marks_drawn()
				Input.action_press("handbrake")
				Input.action_press("steer_left")
				_enter("E")
		"E":
			if _ticks == 8:
				var drawn := skid.marks_drawn() - _marks_at_drift
				check(drawn > 0, "D: the drift after respawn draws again (%d)" % drawn)
				var here := car.chassis.global_position
				for k in drawn:
					var t := skid.segment((_marks_at_drift + k) % SkidMarks.SLOTS)
					var flat := Vector2(t.origin.x - here.x, t.origin.z - here.z).length()
					check(flat < 10.0, "D: the new mark is by the car, not at the old spot (%.1f m)" % flat)
				Input.action_release("handbrake")
				Input.action_release("steer_left")
				Input.action_release("throttle")
				_enter("F")
		"F":
			if _ticks == 5:
				_check_ring()
				var live := skid.marks_live()
				check(live > 0, "F: strips are alive before expiry (%d)" % live)
				# 1 second of game time — and the mark must vanish on its own
				Settings.skid_life = 1.0
				_enter("G")
		"G":
			if _ticks == 120:
				check(skid.marks_live() == 0,
					"G: lifetime expired — no live rings left (%d)" % skid.marks_live())
				var seen := 0
				for i in SkidMarks.SLOTS:
					if skid.segment(i).basis.get_scale().length() > 0.001: seen += 1
				check(seen == 0, "G: vanished strips are really hidden, not overwritten (%d)" % seen)
				# 0 = "never expire": keep the ring's old behavior checkable
				Settings.skid_life = 0.0
				car.respawn(Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 0)))
				Input.action_press("throttle")
				_enter("H")
		"H":
			if _ticks == 150:
				Input.action_press("handbrake")
				Input.action_press("steer_left")
			if _ticks == 165:
				var drawn := skid.marks_live()
				check(drawn > 0, "H: with no expiry strips are drawn (%d)" % drawn)
				Input.action_release("handbrake")
				Input.action_release("steer_left")
				Input.action_release("throttle")
			if _ticks == 400:
				check(skid.marks_live() > 0,
					"H: with lifetime 0 strips never vanish (%d alive after 4 s)" % skid.marks_live())
				Settings.skid_life = 30.0
				_check_manager()
				print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
				get_tree().quit(0 if _fails == 0 else 1)

# Each segment is a flat strip at ground level: higher it hangs above the road,
# lower it sinks into asphalt and disappears.
func _check_geometry() -> void:
	var seen := 0
	var widest := 0.0
	var longest := 0.0
	var highest := 0.0
	var farthest := 0.0
	for i in SkidMarks.SLOTS:
		var t := skid.segment(i)
		var s := t.basis.get_scale()
		if s.length() < 0.001: continue
		seen += 1
		widest = maxf(widest, absf(s.x))
		longest = maxf(longest, absf(s.z))
		highest = maxf(highest, absf(t.origin.y))
		farthest = maxf(farthest, t.origin.distance_to(_spawn))
	check(seen > 30, "B: segments on the ground (%d)" % seen)
	check(is_equal_approx(widest, SkidMarks.WIDTH), "B: width equals the contact patch (%.3f)" % widest)
	check(longest >= SkidMarks.MIN_LEN and longest <= SkidMarks.MAX_LEN + SkidMarks.WIDTH + 1e-4,
		"B: segment length within limits (%.3f)" % longest)
	# the suspension rest height equals the wheel radius within oscillation error, hence the tolerance
	check(highest <= SkidMarks.LIFT + 0.05, "B: the strip lies on the ground (%.4f m)" % highest)
	check(farthest < 200.0, "B: marks near the trajectory (%.1f m)" % farthest)

# A fixed-size ring: synthetic segments with a 1 m step fill every slot, so the old drift
# marks must disappear and the instance count must not grow.
func _check_ring() -> void:
	var before := skid.marks_drawn()
	for k in SkidMarks.SLOTS + 7:
		skid._put(Vector3(float(k), 0.0, -100.0), Vector3.FORWARD, 0.1, 1.0)
	check(skid.marks_drawn() == before + SkidMarks.SLOTS + 7, "E: the counter grows beyond the ring")
	check(skid.multimesh.instance_count == SkidMarks.SLOTS,
		"E: the instance count is fixed (%d)" % skid.multimesh.instance_count)
	var used := 0
	var fresh := 0
	for i in SkidMarks.SLOTS:
		var t := skid.segment(i)
		if t.basis.get_scale().length() < 0.001: continue
		used += 1
		if is_equal_approx(t.origin.z, -100.0) and t.origin.x > float(SLOTS_HALF): fresh += 1
	check(used == SkidMarks.SLOTS, "E: the ring overwrote every slot (%d)" % used)
	check(fresh >= SLOTS_HALF, "E: the oldest marks were evicted by new ones (%d)" % fresh)

# Integration: GameManager creates SkidMarks itself, gives it the car, and keeps the slots empty.
func _check_manager() -> void:
	GameContext.select("sport", "arena")
	var gm: GameManager = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	check(gm.skid != null, "F: GameManager creates SkidMarks")
	check(gm.skid.get_parent() == gm, "F: marks live in the game world")
	check(gm.skid.multimesh != null and gm.skid.multimesh.instance_count == SkidMarks.SLOTS, "F: the ring is allocated")
	check(gm.skid.multimesh.use_colors, "F: mark intensity is set by the instance color")
	check(gm.skid.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "F: marks cast no shadow")
	check(gm.car.wheel_count() == 4, "F: the car has four wheels (%d)" % gm.car.wheel_count())
	var hidden := true
	for i in SkidMarks.SLOTS:
		if gm.skid.segment(i).basis.get_scale().length() >= 0.001:
			hidden = false
			break
	check(hidden, "F: all slots are empty before the drift")
	check(gm.skid.marks_drawn() == 0, "F: no marks at the start (%d)" % gm.skid.marks_drawn())
	gm.queue_free()
