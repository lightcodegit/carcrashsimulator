extends Node3D
var _fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame
	for map_id in ["arena", "town", "speedway"]:
		for car_id in ["sedan", "pickup", "sport"]:
			GameContext.select(car_id, map_id)
			var gm: GameManager = load("res://scenes/game.tscn").instantiate()
			add_child(gm)
			for f in 30:
				await get_tree().physics_frame
			check(gm.car != null and gm.car.chassis != null, "%s/%s car built" % [map_id, car_id])
			check(gm.hud != null and gm.camera != null, "%s/%s hud+camera" % [map_id, car_id])
			gm.damage.report_breaks(Zones.FRONT, 40)
			check(gm.damage.hp(Zones.FRONT) < 100.0, "%s/%s damage applied" % [map_id, car_id])
			gm._respawn_now()
			check(gm.damage.hp(Zones.FRONT) == 100.0, "%s/%s respawn restored hp" % [map_id, car_id])
			gm.queue_free()
			await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
