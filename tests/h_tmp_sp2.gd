extends Node3D
var gm: GameManager
var _f := 0
func _ready() -> void:
	GameContext.select("sport", "speedway")
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().process_frame
	Input.action_press("throttle")
func _physics_process(_dt: float) -> void:
	_f += 1
	if _f in [100, 420, 1000, 1690]:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/out/x%d.png" % _f)
	if _f % 100 == 0 and _f <= 1700:
		var p := gm.car.chassis.global_position
		print("S %4d x=%7.1f v=%6.1f ts=%.2f dents=%d dt=%.4f" % [
			_f, p.x, gm.car.speed_kmh(), Engine.time_scale, gm.car.body.dent_count, _dt])
	if _f == 1700: get_tree().quit(0)
