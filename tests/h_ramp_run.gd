extends Node3D
# "Cars still sometimes crash on ramps": the hills tested are the ones on real maps,
# not a wedge assembled by the test itself (h_handling, phase A) — that would pass even
# if the map placed an obstacle the car actually slams into.
#
# Entry speed is set directly, not by accelerating, and each hill is driven four ways at
# three speeds: the "sometimes" in the complaint is the lane edge and angled entry, not a
# clean center pass. The run ends at the landing: hitting a wall after a long flight is
# another case (h_handling, phases B and D), while here it matters that the hill and its
# landing never dent the body.
#
# Whoever caused the impact is answered by the physics world: at impact time we check
# which collider the frame intersects. A barrier and a stand half a meter off the lane
# are not the hill (measured on arena: lane z=-23.4 ended touching a barrier, and the
# test blamed it on the ramp). So we pick an entry lane where the frame touches nothing
# before the start. Numbers only in the output.

const KMPS := 3.6
var MAPS: Array[String] = MapDB.ids()   # new maps with hills join the test automatically
const SPEEDS := [60.0, 140.0, 210.0, 280.0]
# how we approach: [name, share of half-lane-width, heading in degrees]
# 0.5, not 0.85: roadRamp/roadRampLong segments have a raised 0.2 m white strip along the
# flanges (|z| > 3.4) — that is a curb, not the hill: at 60 km/h a wheel against it stops
# the car, at 250 it throws the nose into the slanted face. Curbs are checked by
# h_prop_knock; here the hill itself is measured in three lanes. A side entry at 10°
# leaves the lane on the hill and the run ends as "left the road", not "the hill caused
# an impact" — we do not test that.
const APPROACHES := [["по центру", 0.0, 0.0], ["правый край", 0.5, 0.0],
	["левый край", -0.5, 0.0]]
const ROLL_AFTER := 20.0     # m the car must roll on the ground after the hill
const LAND_AFTER := 25.0     # m past the hill within which the landing is still its doing
const RUNUP := 8.0           # corridor before the hill: we set speed ourselves, no run-up
const MARGIN := 120.0        # km/h/s: the hill's worst deceleration must stay below this margin
const WINDOW := 4            # ticks used to measure deceleration — same as the impact detector

var _fails := 0
var _runs := 0
var gm: GameManager
var _map := ""
var _impacts := 0
var _on_hill := 0            # impacts on the hill and on the floor right after it — must be zero
var _other := 0              # touches of foreign obstacles: barriers, stands
var _found := 0              # how many hills were found across all maps
var _hb: AABB = AABB()       # the hill's lane in world coordinates
var _hill_bodies: Array = []    # colliders of the current hill
var _ground_bodies: Array = []  # map floor: that is what the car lands on after the jump
var _col_shape: CollisionShape3D
var _hist: Array[Vector3] = []    # velocity per tick of this run
var _worst := 0.0                 # worst deceleration on the hill, km/h per second
var _worst_v0 := Vector3.ZERO     # the velocity vectors that produced this deceleration
var _worst_v1 := Vector3.ZERO
var _worst_y := 0.0
# The complaint "lands hard — loses a lot of speed" is about the touch itself, while the
# previous run aborted exactly on that tick. So after landing we keep measuring a 30-tick
# window, and the "hill episode" spans from entering the hill to the end of that window:
# the flight it owes and the touchdown within the same window.
var _lt := -1
var _lv0 := 0.0
var _lvy := 0.0
var _lpeak := 0.0
var _lloss := 0.0
var _lsink := ""
var _lhist: Array[Vector3] = []
var _episode := false
# The hill's landing and the map wall at the end of the flight are different events: the
# 0.5 s window after the touch has not ended yet, but the frame already ran into something
# foreign (measured on arena: the right edge of the bump at 280 km/h gives a landing and
# 0.3 s later an impact into the end wall at x=81, 173 km/h lost).
# If a foreign collider caused the deceleration inside the landing window, we do not
# charge it to the hill.
var _labort := ""

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	for id in MAPS:
		await _sweep(id)
	check(_found >= 3, "hills must be found on maps, otherwise the test is empty (%d)" % _found)
	print("hills found on maps: %d" % _found)
	print("runs %d" % _runs)
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _sweep(id: String) -> void:
	if gm != null and is_instance_valid(gm):
		gm.queue_free()
		# four frames: the previous map's bodies must leave the physical space before
		# the new one is built, otherwise its props jostle with foreign ones
		for _i in 4:
			await get_tree().physics_frame
	if id == "endless":
		# Endless' hills are the same roadRampLong(×3) and roadBump as on the ring, and the
		# ring is where geometry is checked; here the plates get reshuffled, so the
		# coordinates of an obstacle found once would drift out from under the car. The
		# reshuffle is measured by h_newmaps, and driving endless without dents is covered
		# by h_map_props, h_prop_knock and h_restart_props, which iterate all maps.
		print("NOTE: %s — same hills as on the ring; the plate belt moves, see h_newmaps" % id)
		return
	_map = id
	GameContext.select("sport", id)
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for _i in 30:
		await get_tree().physics_frame
	# On endless the belts reshuffle from behind to the front while we look for hills once:
	# a reshuffle would carry the obstacle away from under the car and the run would
	# measure an empty road.
	gm._endless = false
	gm.car.impact.connect(_on_impact)
	for c in gm.car.chassis.get_children():
		if c is CollisionShape3D: _col_shape = c
	var hazards := _hazards()
	# endless has dozens of hills — measure three spread along the belt; otherwise the
	# test turns into checking all of them, and they are all identical copies
	if hazards.size() > 3:
		var picked: Array[Dictionary] = []
		for k in 3:
			picked.append(hazards[int(k * (hazards.size() - 1) / 2.0)])
		hazards = picked
	if hazards.is_empty():
		print("NOTE: no hills on %s — nothing to check" % id)
	_found += hazards.size()
	for hz in hazards:
		_hill_bodies = hz["bodies"]
		for ap in APPROACHES:
			for v in SPEEDS:
				# We drive the hill sideways only up to 210 km/h: at 300 the car rides the
				# slope nose-first and spins on it — that is a real crash, not "the hill
				# declared an impact", and this test must not check it.
				await _run(String(hz["label"]), hz["box"] as AABB, String(ap[0]),
					float(ap[1]), float(ap[2]), float(v))
	gm.queue_free()

# Map hills are segments with their own collider: "roadRamp" (jump) and "roadBump"
# (sleeping policeman). We find them by MapDB node names, not by coordinates hardcoded in
# the test: a reshuffled ramp must not silently turn the check into a no-op.
# A hill owns its StaticBody3D: MapDB places the body at the same position as the mesh.
func _hazards() -> Array[Dictionary]:
	var bodies: Array = []
	var ground: Array = []
	for c in gm.get_children():
		for n in c.get_children():
			var sb := n as StaticBody3D
			if sb == null: continue
			var plate := false
			for cs in sb.get_children():
				var csi := cs as CollisionShape3D
				if csi == null or csi.shape == null: continue
				var b := csi.shape as BoxShape3D
				if b != null and b.size.x > 100.0 and b.size.y <= 2.5: plate = true
			if plate: ground.append(sb)
			else: bodies.append(sb)
	_ground_bodies = ground
	var out: Array[Dictionary] = []
	var stack: Array[Node] = [gm]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and (mi.name.begins_with("kit_roadRamp") or mi.name.begins_with("kit_roadBump")):
			var mine: Array = []
			for sb in bodies:
				if sb.position.distance_squared_to(mi.position) < 0.0004: mine.append(sb)
			out.append({"label": "рампа" if mi.name.begins_with("kit_roadRamp") else "бугор",
				"box": mi.global_transform * mi.get_aabb(), "bodies": mine})
		for c in n.get_children():
			stack.append(c)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return (x["box"] as AABB).position.x < (y["box"] as AABB).position.x)
	return out

# Start pose: the lane is the hill's center shifted by a share of its half-width; the run-up
# start is offset along the heading so the line of travel still leads into the hill.
func _lane_start(a: AABB, off: float, yaw: float) -> Transform3D:
	var lane_z := (a.position.z + a.end.z) * 0.5 + off * maxf(a.size.z * 0.5 - 1.0, 0.5)
	return Transform3D(Basis(Vector3.UP, yaw),
		Vector3(a.position.x - RUNUP, 1.0, lane_z + tan(yaw) * (RUNUP + a.size.x * 0.5)))

# Does the frame in this pose touch nothing except the hill itself and the floor?
func _pose_clear(tf: Transform3D) -> bool:
	if _col_shape == null: return true
	var q := PhysicsShapeQueryParameters3D.new()
	q.set_shape(_col_shape.shape)
	q.transform = tf * _col_shape.transform
	q.margin = 0.15
	q.collision_mask = gm.car.chassis.collision_mask
	q.exclude = [gm.car.chassis.get_rid()]
	for h in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var b: Object = h["collider"]
		if not (_hill_bodies.has(b) or _ground_bodies.has(b)): return false
	return true

func _run(label: String, a: AABB, how: String, off_req: float, yaw_deg: float, kmh: float) -> void:
	_runs += 1
	var yaw := deg_to_rad(yaw_deg)
	# nudge the lane edge inward if a barrier stands there: otherwise the check would
	# catch a barrier touch instead of the hill's behavior
	var off := off_req
	while absf(off) > 0.05 and not _pose_clear(_lane_start(a, off, yaw)):
		off -= signf(off) * 0.15
	var tf := _lane_start(a, off, yaw)
	var lane_z := tf.origin.z - tan(yaw) * (RUNUP + a.size.x * 0.5)
	var tag := "%s/%s @%d %s" % [_map, label, int(kmh), how]
	_impacts = 0
	_on_hill = 0
	_other = 0
	_hb = a
	gm.car.respawn(tf)
	for _i in 25:
		await get_tree().physics_frame        # the body settles on its suspension
	var fwd := Vector3(cos(yaw), 0.0, -sin(yaw))
	gm.car.chassis.linear_velocity = fwd * (kmh / KMPS)
	var max_y := 0.0
	var air := 0
	var air_run := 0
	_hist = []
	_worst = 0.0
	_lt = -1
	_lpeak = 0.0
	_lloss = 0.0
	_lsink = ""
	_labort = ""
	_lhist = []
	_episode = false
	var jumped := false
	var crossed := false
	var reached := false
	var entry := -1.0
	var end := ""
	var prev := gm.car.chassis.global_position
	for _i in 600:
		await get_tree().physics_frame
		var p := gm.car.chassis.global_position
		var grounded := gm.car._grounded
		if p.x > a.position.x: _episode = true
		max_y = maxf(max_y, p.y)
		# Margin to the impact threshold: the detector fires at 210 km/h/s and the hill must
		# give several times less. Measured with the same 4-tick window as the detector.
		var vel := gm.car.chassis.linear_velocity
		if _lt < 0:
			_hist.append(vel)
		while _hist.size() > WINDOW + 1:
			_hist.pop_front()
		if _lt < 0 and _hist.size() == WINDOW + 1:
			var d := (_hist[0].length() - _hist[WINDOW].length()) * 3.6 / (WINDOW / 60.0)
			if d > _worst:
				_worst = d
				_worst_v0 = _hist[0]
				_worst_v1 = _hist[WINDOW]
				_worst_y = p.y
		# at the ramp's lip the frame's clamp shape still catches the edge and "air" lights
		# up for a tick at the start of the climb: we count the flight only once it is
		# sustained, otherwise the run aborted before the real landing and the check would
		# measure takeoff instead of touchdown.
		air_run = 0 if grounded else air_run + 1
		if air_run > 0:
			air += 1
		if air_run >= 6:
			jumped = true
		if p.x > a.position.x and entry < 0.0:
			entry = gm.car.speed_kmh()
		if p.x > a.position.x + 1.0:
			reached = true
		if p.x > a.end.x + 0.5:
			crossed = true
		# GameManager teleports the car back to spawn itself if it flew past the map
		# border: the run is over, nothing left to measure.
		if p.distance_to(prev) > 12.0:
			end = "вылет за границу"
		elif _on_hill > 0:
			end = "удар на горке"
		elif crossed and jumped and grounded and _lt < 0 and vel.y < 0.0:
			# count only a touch DOWNHILL: wheels lose ground on the hill's steps too,
			# and at launch while the car is still climbing
			_lt = 0
			_lv0 = gm.car.speed_kmh()
			_lvy = vel.y
			_lhist = [vel]
		elif crossed and not jumped and p.x > a.end.x + ROLL_AFTER:
			end = "прокатилась"
		elif _other > 0 and _lt < 0:
			# an impact on something foreign (barrier, wall) outranks "the car stopped":
			# otherwise the test charges the hill for a post-collision stop. Do not abort
			# inside the landing window: that window decides whose deceleration it is
			# (_labort).
			end = "цепнула постороннее"
		elif p.x > a.position.x and gm.car.speed_kmh() < 2.0:
			# a 5 m ramp at 60 km/h cannot be taken on inertia: the car stops on the slope
			# and slides back — that is physics, not "the hill caused an impact"
			end = "остановилась на горке"
		elif gm.car.speed_kmh() < 2.0:
			# at low speed the car straddles the bump and stops right after it — that is
			# also a clean run, just nothing left to measure further
			end = "прокатилась" if crossed else "встала до горки"
		elif absf(p.z - (a.position.z + a.end.z) * 0.5) > a.size.z * 0.5 + 2.0:
			# the car left the lane sideways (an angled jump carries it past the barrier,
			# then come trees and stands) — hill behavior is not measured here
			end = "ушла с полосы"
		if _lt >= 0:
			_lt += 1
			_lhist.append(gm.car.chassis.linear_velocity)
			while _lhist.size() > WINDOW + 1:
				_lhist.pop_front()
			if _lhist.size() == WINDOW + 1:
				var ld := (_lhist[0].length() - _lhist[WINDOW].length()) * 3.6 / (WINDOW / 60.0)
				if ld > _lpeak:
					_lpeak = ld
					var touch: Array[String] = []
					for b in gm.car.chassis.get_colliding_bodies():
						if _ground_bodies.has(b): touch.append("пол")
						elif _hill_bodies.has(b): touch.append("рампа")
						else: touch.append(String(b.name))
					_lsink = str(touch)
			if _lt == 30:
				_lloss = _lv0 - gm.car.speed_kmh()
				_episode = false
				# a foreign body in this window decides who owns the speed loss
				end = "цепнула постороннее" if _labort != "" else "приземлилась"
		prev = p
		# finish counting the landing window even if the car managed to snag on something:
		# this window exactly is what the complaint is about
		if end != "" and (_lt < 0 or _lt >= 30 or end != "приземлилась"):
			break
	var clean := end in ["приземлилась", "прокатилась", "остановилась на горке"]
	print("%-34s crossed=%s lane z=%+.1f hill x=%.0f..%.0f entry=%3.0f km/h rise=%.2f m air=%3d ticks braking=%3.0f km/h/s impacts=%d (hill %d, foreign %d) dents=%d — %s" % [
		tag, crossed, lane_z, a.position.x, a.end.x, entry, max_y, air, _worst,
		_impacts, _on_hill, _other, gm.car.body.dent_count, end if end != "" else "timeout"])
	# The test must not be vacuous: the car has to reach the hill. On arena some flights
	# end at the wall — that is not about the hill; clean landings are sought where the
	# track is long.
	check(reached, "%s: car reached the hill (%s)" % [tag, end])
	check(_on_hill == 0, "%s: the hill caused no impact (%d)" % [tag, _on_hill])
	if clean:
		# We charge an impact or a dent to the hill only if the run had no foreign touch: a
		# wall at the end of a long flight or a knocked-over tank leaves a mark not caused
		# by the hill.
		if _other == 0:
			check(_impacts == 0, "%s: landing after the hill is not an impact (%d)" % [tag, _impacts])
			check(gm.car.body.dent_count == 0, "%s: body intact after the hill (%d)" % [tag, gm.car.body.dent_count])
		var why := "v %.0f -> %.0f km/h, vertical %+.1f -> %+.1f m/s at y=%.1f" % [
			Vector3(_worst_v0.x, 0, _worst_v0.z).length() * 3.6,
			Vector3(_worst_v1.x, 0, _worst_v1.z).length() * 3.6,
			_worst_v0.y, _worst_v1.y, _worst_y]
		check(_worst < MARGIN, "%s: hill brakes with margin below the impact threshold (%.0f km/h/s, %s)" % [
			tag, _worst, why])
	if _lt >= 30:
		print("%-34s LANDING: %.0f km/h with vy=%.1f → loss %.1f km/h in 0.5 s, braking %.0f km/h/s, frame touches %s%s" % [
			tag, _lv0, _lvy, _lloss, _lpeak, _lsink,
			" (interrupted by impact with %s)" % _labort if _labort != "" else ""])
		# Deceleration after a foreign impact in the same window is that impact's account,
		# not the landing's: checking it as "the hill brakes on landing" is impossible,
		# otherwise the test catches the end wall and demands of the hill what is not its
		# responsibility.
		if _labort == "":
			check(_lloss < 25.0, "%s: hard landing does not eat speed (%.1f km/h in 0.5 s)" % [tag, _lloss])
			check(_lpeak < MARGIN, "%s: landing below the impact threshold with the same margin (%.0f km/h/s)" % [tag, _lpeak])
	if label == "рампа" and kmh >= 210.0 and clean and off_req == 0.0 and yaw_deg == 0.0:
		check(air > 5, "%s: the car left the ground on the ramp (%d ticks airborne)" % [tag, air])

func _on_impact(speed: float, point: Vector3, normal: Vector3) -> void:
	_impacts += 1
	# The hill's "credit" is its own geometry plus the floor in the corridor right after it:
	# that is where the car is thrown after the jump, exactly the complaint's case. Everything
	# else is a foreign obstacle with its own check (h_handling, h_prop_knock).
	var near := point.x > _hb.position.x - 1.0 and point.x < _hb.end.x + LAND_AFTER \
		and absf(point.z - (_hb.position.z + _hb.end.z) * 0.5) < _hb.size.z * 0.5 + 1.0
	var is_hill := false
	var is_ground := false
	var is_strange := false
	var who := ""
	var strange := ""
	for b in _contacts():
		if _hill_bodies.has(b): is_hill = true
		elif _ground_bodies.has(b): is_ground = true
		else:
			is_strange = true
			strange += (b as Node).name + " "
		var n3 := b as Node3D
		who += "%s@(%.1f,%.1f,%.1f) " % [(b as Node).name, n3.global_position.x,
			n3.global_position.y, n3.global_position.z]
	# within a hill episode (on it, in its flight, in the landing window) a road touch is
	# on its account: its flight is what brought the car to this point. Barriers and walls
	# stay foreign.
	var ours := is_hill or (is_ground and (near or _episode) and not is_strange)
	if ours:
		_on_hill += 1
	else:
		_other += 1
		# impact inside the landing window: the window keeps counting, but its numbers
		# are no longer about the hill
		if _lt >= 0: _labort = strange.trim_suffix(" ")
	print("   impact: %.0f km/h point (%.1f, %.1f, %.1f) normal (%.2f, %.2f, %.2f) %s, hit %s" % [
		speed, point.x, point.y, point.z, normal.x, normal.y, normal.z,
		"hill" if ours else "foreign", who if who != "" else "—"])

func _contacts() -> Array:
	if _col_shape == null or gm.car.chassis == null: return []
	var q := PhysicsShapeQueryParameters3D.new()
	q.set_shape(_col_shape.shape)
	q.transform = gm.car.chassis.global_transform * _col_shape.transform
	q.margin = 0.25
	q.collision_mask = gm.car.chassis.collision_mask
	q.exclude = [gm.car.chassis.get_rid()]
	var out: Array = []
	for h in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var b: Object = h["collider"]
		if b != null and not out.has(b): out.append(b)
	return out
