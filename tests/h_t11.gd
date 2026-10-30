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
			var nose := gm.car.chassis.global_position + Vector3(gm.car.params.length * 0.5, 0, 0)
			gm.car.body.apply_impact(nose, Vector3(1, 0, 0), 90.0)
			check(gm.car.body.dent_count > 0, "%s/%s dent applied" % [map_id, car_id])
			check(gm.car.body.deformation() > 0.05, "%s/%s body deformed (%.2f м)" % [map_id, car_id, gm.car.body.deformation()])
			gm._respawn_now()
			check(gm.car.body.dent_count == 0 and gm.car.body.deformation() < 1e-6, "%s/%s respawn restored body" % [map_id, car_id])
			gm.queue_free()
			await get_tree().process_frame
	print("ALL PASS" if _fails == 0 else "FAILS %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
