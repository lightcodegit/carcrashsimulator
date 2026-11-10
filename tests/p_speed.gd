extends Node3D
var _f := 0
var _max_x := -1e9
var _shot: bool = DisplayServer.get_name() != "headless"   # screenshots only make sense with live rendering
var gm: GameManager
func _ready() -> void:
	GameContext.select("sport", "speedway")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	DirAccess.make_dir_recursive_absolute("res://tests/out")
	await get_tree().process_frame
func _physics_process(_dt: float) -> void:
	_f += 1
	if _f == 5: Input.action_press("throttle")
	# Awaiting frame_post_draw inside a physics tick is only safe with live
	# rendering: in headless no frame is drawn, the coroutine froze mid-function,
	# and the metric lied (x_max=451 instead of 583 — that is mid-jump, not the finish).
	if _shot and _f in [100, 420, 1000, 1690]:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/out/s%d.png" % _f)
	# the maximum, not the current x: after the hit on the finish wall the car is
	# thrown back and drives off again — "did it reach the finish" is not readable
	# from the current coordinate
	_max_x = maxf(_max_x, gm.car.chassis.global_position.x)
	if _f == 1691:
		var thru := 0
		for i in gm.car.body.vertex_count():
			if gm.car.body.vertex_world(i).x > 585.8: thru += 1
		print("SPEED done thru_wall=%d y=%.1f dents=%d deform=%.2f x_max=%.1f x=%.1f" % [
			thru, gm.car.chassis.global_position.y, gm.car.body.dent_count,
			gm.car.body.deformation(), _max_x, gm.car.chassis.global_position.x])
		get_tree().quit(0)
