extends Node3D
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	# All maps, not four of six: otherwise circuit and endless get no landing, no
	# light and no materials from any test. Cars — short and long-wheelbase, so the
	# wheelbase and overhangs are checked on every map without tripling run time.
	for map_id in MapDB.ids():
		for car_id in ["sedan", "limousine"]:
			GameContext.select(car_id, map_id)
			var gm: GameManager = load("res://scenes/game.tscn").instantiate()
			add_child(gm)
			for f in 30:
				await get_tree().physics_frame
			check(gm.car != null and gm.car.chassis != null, "%s/%s car built" % [map_id, car_id])
			check(gm.hud != null and gm.camera != null, "%s/%s hud+camera" % [map_id, car_id])
			var nose := gm.car.chassis.global_position + Vector3(gm.car.params.length * 0.5, 0, 0)
			gm.car.body.apply_impact(nose, Vector3(1, 0, 0), 90.0)
			check(gm.car.body.dent_count > 0, "%s/%s dent applied" % [map_id, car_id])
			check(gm.car.body.deformation() > 0.05, "%s/%s body deformed (%.2f m)" % [map_id, car_id, gm.car.body.deformation()])
			gm._respawn_now()
			check(gm.car.body.dent_count == 0 and gm.car.body.deformation() < 1e-6, "%s/%s respawn restored body" % [map_id, car_id])
			# Body paint: gloss comes from clearcoat and low roughness, not metallic —
			# metallic suppresses the diffuse term, and the car turns black in shadow.
			var mat: StandardMaterial3D = gm.car.body._mat
			check(mat.metallic <= 0.25, "%s/%s metallic is low (%.2f)" % [map_id, car_id, mat.metallic])
			check(mat.roughness < 0.5, "%s/%s paint is glossy (roughness %.2f)" % [map_id, car_id, mat.roughness])
			check(mat.clearcoat_enabled and mat.clearcoat > 0.3,
				"%s/%s clearcoat enabled (%.2f)" % [map_id, car_id, mat.clearcoat])
			check(mat.albedo_texture != null, "%s/%s colormap texture present" % [map_id, car_id])
			check(mat.vertex_color_use_as_albedo, "%s/%s vertex color for wear enabled" % [map_id, car_id])
			var suns := 0
			var amb := false
			var long_shadow := false
			var env: Environment = null
			for c in gm.get_children():
				if c is DirectionalLight3D:
					suns += 1
					long_shadow = long_shadow or (c as DirectionalLight3D).directional_shadow_max_distance >= 100.0
				if c is WorldEnvironment: env = (c as WorldEnvironment).environment
			if env != null:
				# on Compatibility the sky is dark, so light from it comes as a flat color — see GameManager
				amb = env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY \
					or (env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
						and env.ambient_light_energy > 0.1 and env.ambient_light_color.v > 0.4)
			check(suns >= 2, "%s/%s sun plus fill light (%d)" % [map_id, car_id, suns])
			check(amb, "%s/%s ambient light from the sky" % [map_id, car_id])
			check(long_shadow, "%s/%s shadow range covers the car with margin" % [map_id, car_id])
			# environment: physical sky, fog and screen-space indirect light — otherwise
			# bodies in building shadows stay black and far distances cut off
			# The sky is a procedural gradient: the physical one on this renderer gives
			# "milk" (measured: blue minus red 0.046 vs 0.121). What is checked is the
			# gradient sky with a blue zenith itself, not a specific material class.
			var sm := (env.sky.sky_material if env != null and env.sky != null else null) as ProceduralSkyMaterial
			check(sm != null and sm.sky_top_color.b > sm.sky_top_color.r + 0.3,
				"%s/%s sky is a gradient with a blue zenith" % [map_id, car_id])
			check(env != null and env.fog_enabled and env.fog_density > 0.0,
				"%s/%s fog enabled" % [map_id, car_id])
			# SSIL lives only on Forward+: on Compatibility the engine does not know it, and
			# requiring it would be requiring a setting that does not exist
			check(env != null and env.ssil_enabled == (Settings.ssil and Settings.supports_ssil()),
				"%s/%s screen-space indirect light follows the setting and the renderer" % [map_id, car_id])
			check(env != null and env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY,
				"%s/%s reflections from the sky" % [map_id, car_id])
			if map_id == "bigcity" and car_id == "sedan":
				_check_surface_index()
			gm.queue_free()
			await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# Surface index against full brute force: compared both by value and by cost in one
# process — so the check does not depend on the speed of the car it runs on. Before
# the surface_y grid it was brute force, hence the ratio was 1.0.
func _check_surface_index() -> void:
	var surfaces := MapKit.surfaces()
	check(surfaces.size() > 200, "the city has something to index (%d surfaces)" % surfaces.size())
	if surfaces.size() <= 1: return
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 20261107
	var pts: Array[Vector2] = []
	for i in 4000:
		# take the point inside a random rectangle: otherwise half the queries
		# would miss and not touch the index at all
		var rect: AABB = surfaces[rnd.randi() % surfaces.size()]["rect"]
		pts.append(Vector2(rnd.randf_range(rect.position.x, rect.end.x),
			rnd.randf_range(rect.position.z, rect.end.z)))
	for i in 200:
		pts.append(Vector2(9000.0 + float(i), 9000.0))
	var brute := func(p: Vector2) -> float:
		var g := INF
		for r in surfaces:
			if (r["rect"] as AABB).has_point(Vector3(p.x, 0.0, p.y)): g = minf(g, float(r["y"]))
		return g if is_finite(g) else MapDefs.FLOOR_Y + 0.001
	var same := 0
	for p in pts:
		if is_equal_approx(brute.call(p), MapKit.surface_y(p.x, p.y)): same += 1
	check(same == pts.size(),
		"the grid returns exactly the heights brute force does (%d of %d)" % [same, pts.size()])
	var tb := Time.get_ticks_usec()
	for p in pts: brute.call(p)
	tb = Time.get_ticks_usec() - tb
	var tg := Time.get_ticks_usec()
	for p in pts: MapKit.surface_y(p.x, p.y)
	tg = Time.get_ticks_usec() - tg
	check(tg * 3 < tb,
		"the index is 3× faster than brute force on the same points (%d us vs %d)" % [tg, tb])
	print("NOTE: surface_y %d queries: brute force %d us, grid %d us, speedup %.1f×" %
		[pts.size(), tb, tg, float(tb) / maxf(float(tg), 1.0)])
