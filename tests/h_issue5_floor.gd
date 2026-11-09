extends Node3D
# Issue #5: «боковая дорога» (травяной пол) у вечной трассы заканчивался —
# floor_follow дёргает пол за машиной. Проверяем съезд с дороги и долгий
# забег по траве: пол под колёсами не кончается, дорожная лента не видна
# над пустотой.
var _fails := 0
var gm: GameManager

func check(cond: bool, msg: String) -> void:
	if not cond: _fails += 1; print("FAIL: " + msg)

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	GameContext.select("sedan", "endless")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	for f in 10: await get_tree().physics_frame
	var floor_body: StaticBody3D = gm._map_root.get_node_or_null("endless_floor")
	check(floor_body != null, "пол бесконечности найден по имени")
	if floor_body == null: print("FAILS %d" % _fails); get_tree().quit(1); return

	# 1) съезд с дороги на траву и 4 км прямо по ней
	var start_x: float = gm.car.chassis.global_position.x
	# телепорт на траву рядом с дорогой (barrier на ±5 не даёт выехать боком)
	gm.car.respawn(Transform3D(Basis(Vector3.UP, 0.0), Vector3(start_x, 1.0, 40.0)))
	Input.action_press("throttle")
	for f in 600:
		await get_tree().physics_frame
		var d := gm.car.chassis.global_position - floor_body.position
		if absf(d.x) > 60.0 and absf(d.z) > 8.0: break
	# 4 км по траве: пол обязан дёргаться за машиной, машина не падает
	var fell := 0.0
	for f in 4800:
		await get_tree().physics_frame
		if gm.car.chassis.global_position.y < -2.0:
			fell += 1
			break
		if f % 400 == 0 and f > 0:
			var gap := gm.car.chassis.global_position.x - floor_body.position.x
			check(absf(gap) < 11000.0,
				"пол в пределах 11 км от машины (зазор %.0f м на тике %d)" % [gap, f])
	check(fell == 0, "машина не провалилась в пустоту за 4 км по траве")
	check(gm.car.chassis.global_position.x > start_x + 3000.0,
		"машина доехала до дальних километров (%.0f → %.0f)" % [start_x, gm.car.chassis.global_position.x])

	# 2) дорога рядом всё так же есть: луч вниз у машины попадает в пол или плиту
	var space := get_world_3d().direct_space_state
	var from: Vector3 = gm.car.chassis.global_position + Vector3(0, 3.0, 0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -30.0, 0)))
	check(not hit.is_empty(), "под машиной на любом километре есть твёрдая поверхность")

	if _fails == 0: print("ALL PASS")
	else: print("FAILS %d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
