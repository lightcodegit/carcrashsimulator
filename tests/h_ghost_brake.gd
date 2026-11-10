extends Node3D
# Complaint: "the car randomly slows down hard on some objects". Hard braking by
# itself is not the bug — the bug is when it happens WITHOUT a collision: you drive
# your lane, hit nothing, yet the speed vanishes. So the check runs dead straight over
# the live maps, and at every braking jump it asks the physics world who is to blame:
# a foreign body (wall, barrier, knocked-over barrel) is a crash — measured by
# h_crash and h_handling; air (a jump and its landing) is h_landing and h_slope_land;
# but if the car is on all four wheels on the road holding onto nothing, braking above
# the threshold is exactly that bug.
#
# We measure the HORIZONTAL loss: a jump landing changes |v| via the vertical, and on
# the full vector a jump is indistinguishable from hitting an invisible wall. Longitudinal
# speed is what the player reads as "the car lost speed".

const KMPS := 3.6
const WINDOW := 4            # ticks over which we measure deceleration — as in the impact detector
const THRESH := 60.0         # km/h/s (~1.7 g): horizontal braking without a collision
const TICKS := 1200          # per map: 20 s of driving, enough to reach both the jumps and the bumps
const SPEED := 200.0         # km/h at entry: keep accelerating with throttle; braking should come only from the road

var _fails := 0
var _events := 0
var _explained := 0
var _ticks := 0
var _maps := 0
var _seen: Dictionary = {}
var gm: GameManager
var _map := ""
var _ground: Array = []
var _hist: Array[Vector3] = []

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	for id in MapDB.ids():
		await _sweep(id)
	check(_ticks >= 4000, "the test is not empty: drove %d ticks" % _ticks)
	# Map coverage is counted by actual ticks, not by loop iterations:
	# a counter incremented once per id from the same list checks nothing.
	for id in MapDB.ids():
		var t := int(_seen.get(id, 0))
		# Per-map baseline: arena/speedway/circuit/endless give the full 1200 ticks,
		# bigcity 1065, town 301 — there the car leaves the polygon bounds and the sweep
		# cuts short. A threshold of 120 (2 s of observation) keeps twice that headroom
		# and still catches a map that was never driven at all.
		check(t >= 120, "map %s driven with measurements (%d ticks)" % [id, t])
	print("ticks %d, braking jumps ≥ %.0f km/h/s: %d, of which explained: %d" % [
		_ticks, THRESH, _events, _explained])
	print("ticks per map: %s" % str(_seen))
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _sweep(id: String) -> void:
	if gm != null and is_instance_valid(gm):
		gm.queue_free()
		for _i in 4:
			await get_tree().physics_frame
	_map = id
	_maps += 1
	GameContext.select("sport", id)
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for _i in 30:
		await get_tree().physics_frame
	gm._endless = false        # the "endless" strip reshuffles, coordinates drift
	_ground = _ground_bodies()
	gm.car.respawn(gm._spawn)
	for _i in 25:
		await get_tree().physics_frame
	gm.car.chassis.linear_velocity = _forward() * (SPEED / KMPS)
	Input.action_press("throttle")
	var prev := gm.car.chassis.global_position
	_hist = []
	for _i in TICKS:
		await get_tree().physics_frame
		_ticks += 1
		_seen[_map] = int(_seen.get(_map, 0)) + 1
		var p := gm.car.chassis.global_position
		# GameManager teleports the car to spawn if it left the bounds: the run
		# is over, there is nothing left to measure
		if p.distance_to(prev) > 12.0: break
		prev = p
		var v: Vector3 = gm.car.chassis.linear_velocity
		# compute braking on the horizontal plane: the vertical changes on landing, and
		# "car speed" for the player is the longitudinal travel
		var flat := Vector3(v.x, 0.0, v.z)
		_hist.append(flat)
		while _hist.size() > WINDOW + 1: _hist.pop_front()
		if _hist.size() < WINDOW + 1: continue
		var d := (_hist[0].length() - _hist[WINDOW].length()) * KMPS / (WINDOW / 60.0)
		if d < THRESH: continue
		_events += 1
		var air := 0
		for w in gm.car._wheels:
			if not w.is_in_contact(): air += 1
		var crash := _foreign()
		if air > 0 or crash != "":
			_explained += 1
			continue
		var why := ("%s x=%.0f z=%.0f: horizontal braking %.0f km/h/s (%.1f g) at %.0f km/h "
			+ "on all wheels, the chassis holds onto nothing — the road itself eats the speed") % [
				_map, p.x, p.z, d, d / 3.6 / 9.81, gm.car.speed_kmh()]
		check(false, why)
	Input.action_release("throttle")
	gm.queue_free()

# Does the chassis touch a body that is not a road slab? That is the collision.
# get_colliding_bodies() will not do: the VehicleBody3D contact list is incomplete
# (measured: 7 g braking at the speedway end wall with an empty list), so we ask the
# physics world directly with a shape query around the chassis.
func _foreign() -> String:
	var col := _col_shape()
	if col == null: return ""
	var q := PhysicsShapeQueryParameters3D.new()
	q.set_shape(col.shape)
	q.transform = gm.car.chassis.global_transform * col.transform
	# 0.6 m, not a zero-contact query: a knocked barrier flies out from under the chassis
	# within the same tick, and a check looking only at the current intersection is left
	# without a culprit (measured speedway x=576: minus 4.6 m/s in one tick is five 25 kg
	# barriers accelerating — not the road; by the next tick they are already outside the chassis).
	q.margin = 0.6
	q.collision_mask = gm.car.chassis.collision_mask
	q.exclude = [gm.car.chassis.get_rid()]
	var out := ""
	for h in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var b: Object = h["collider"]
		if b == null or _ground.has(b): continue
		out += String((b as Node).name) + " "
	return out.trim_suffix(" ")

func _col_shape() -> CollisionShape3D:
	for c in gm.car.chassis.get_children():
		var cs := c as CollisionShape3D
		if cs != null and cs.shape != null: return cs
	return null

# Floor slabs: long flat boxes — in MapDB each slab has its own body. Ramps and
# bumps place their own trimesh bodies; we count those as obstacles, braking on them is allowed (h_ramp_run).
func _ground_bodies() -> Array:
	var out: Array = []
	for c in gm.get_children():
		for n in c.get_children():
			var sb := n as StaticBody3D
			if sb == null: continue
			for cs in sb.get_children():
				var csi := cs as CollisionShape3D
				if csi == null or csi.shape == null: continue
				var b := csi.shape as BoxShape3D
				if b != null and maxf(b.size.x, b.size.z) > 40.0 and b.size.y <= 2.5:
					out.append(sb)
	return out

# The car's heading, not its frame's X axis: VehicleBody3D points its nose at +Z
# (YAW_OFFSET in CarRig), and setting the velocity along X makes the car drive sideways,
# the tyres scrub the asphalt, and the test catches braking the player never sees
# (measured: 68 "unexplained" jumps over 5831 ticks).
func _forward() -> Vector3:
	return gm.car._flat_forward()
